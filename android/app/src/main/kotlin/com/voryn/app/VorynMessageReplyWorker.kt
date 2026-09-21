package com.voryn.app

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class VorynMessageReplyWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        private const val TAG = "VorynReplyWorker"
        const val KEY_THREAD_ID = "thread_id"
        const val KEY_RECIPIENT_UID = "recipient_uid"
        const val KEY_BODY = "body"
        const val KEY_CLIENT_MESSAGE_ID = "client_message_id"
        const val KEY_IS_MARK_READ = "is_mark_read"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val isMarkRead = inputData.getBoolean(KEY_IS_MARK_READ, false)
        val threadId = inputData.getString(KEY_THREAD_ID) ?: return@withContext Result.failure()

        Log.d(TAG, "[WORKER] start threadId=$threadId isMarkRead=$isMarkRead attempt=$runAttemptCount")

        var session = VorynBackgroundAuthStore.getSession(applicationContext)
        if (session == null) {
            Log.e(TAG, "[WORKER] no background auth session available")
            return@withContext Result.failure()
        }

        if (session.isExpiredOrNearExpiry) {
            Log.d(TAG, "[WORKER] session expired or near expiry, refreshing token...")
            val newToken = VorynBackgroundAuthStore.refreshAccessToken(applicationContext)
            if (newToken != null) {
                session = VorynBackgroundAuthStore.getSession(applicationContext) ?: return@withContext Result.failure()
            }
        }

        if (isMarkRead) {
            return@withContext executeMarkRead(session, threadId)
        }

        val recipientUid = inputData.getString(KEY_RECIPIENT_UID) ?: ""
        val body = inputData.getString(KEY_BODY) ?: ""
        val clientMessageId = inputData.getString(KEY_CLIENT_MESSAGE_ID) ?: ""

        executeSendMessage(session, threadId, recipientUid, body, clientMessageId)
    }

    private fun executeMarkRead(
        session: VorynBackgroundAuthStore.Session,
        threadId: String
    ): Result {
        return try {
            val rpcUrl = URL("${session.supabaseUrl.trimEnd('/')}/rest/v1/rpc/mark_thread_read")
            val conn = (rpcUrl.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10_000
                readTimeout = 10_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("apikey", session.anonKey)
                setRequestProperty("Authorization", "Bearer ${session.accessToken}")
            }

            val bodyJson = JSONObject().apply {
                put("p_thread_id", threadId)
            }
            OutputStreamWriter(conn.outputStream).use { it.write(bodyJson.toString()) }

            val code = conn.responseCode
            Log.d(TAG, "[WORKER] mark_thread_read responseCode=$code")
            if (code in 200..299) Result.success() else Result.retry()
        } catch (e: Exception) {
            Log.e(TAG, "[WORKER] mark_thread_read exception: ${e.message}")
            Result.retry()
        }
    }

    private fun executeSendMessage(
        session: VorynBackgroundAuthStore.Session,
        threadId: String,
        recipientUid: String,
        body: String,
        clientMessageId: String
    ): Result {
        try {
            val rpcUrl = URL("${session.supabaseUrl.trimEnd('/')}/rest/v1/rpc/send_call_message")
            val conn = (rpcUrl.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 12_000
                readTimeout = 12_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("apikey", session.anonKey)
                setRequestProperty("Authorization", "Bearer ${session.accessToken}")
            }

            val payload = JSONObject().apply {
                if (recipientUid.isNotBlank()) {
                    put("p_recipient_uid", recipientUid)
                }
                put("p_body", body)
                put("p_remind_to_call", false)
                if (clientMessageId.isNotBlank()) {
                    put("p_client_message_id", clientMessageId)
                }
            }

            OutputStreamWriter(conn.outputStream).use { it.write(payload.toString()) }

            val responseCode = conn.responseCode
            Log.d(TAG, "[WORKER] send_call_message responseCode=$responseCode clientMessageId=$clientMessageId")

            if (responseCode in 200..299) {
                val rawResponse = conn.inputStream.bufferedReader().use(BufferedReader::readText).trim()
                val messageId = rawResponse.replace("\"", "").trim()

                Log.d(TAG, "[WORKER] send_call_message succeeded messageId=$messageId")

                // Update notification to show message has been sent
                VorynMessageNotificationManager.appendSentMessage(applicationContext, threadId, body)

                // Trigger server-side push outbox dispatch (best-effort)
                if (messageId.isNotEmpty()) {
                    triggerPushDispatch(session, messageId)
                }

                return Result.success()
            } else if (responseCode == 401 && runAttemptCount < 2) {
                Log.w(TAG, "[WORKER] received 401, refreshing token...")
                val newToken = VorynBackgroundAuthStore.refreshAccessToken(applicationContext)
                if (newToken != null) {
                    return Result.retry()
                }
            }

            if (responseCode in 500..599 && runAttemptCount < 4) {
                return Result.retry()
            }

            // Unrecoverable or exceeded retries
            Log.e(TAG, "[WORKER] send failed permanently with HTTP $responseCode")
            VorynMessageNotificationManager.updateFailedNotification(applicationContext, threadId, body)
            return Result.failure()
        } catch (e: Exception) {
            Log.e(TAG, "[WORKER] send exception: ${e.message}")
            if (runAttemptCount < 4) {
                return Result.retry()
            }
            VorynMessageNotificationManager.updateFailedNotification(applicationContext, threadId, body)
            return Result.failure()
        }
    }

    private fun triggerPushDispatch(session: VorynBackgroundAuthStore.Session, messageId: String) {
        try {
            val fnUrl = URL("${session.supabaseUrl.trimEnd('/')}/functions/v1/send-message-notification")
            val conn = (fnUrl.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 8_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("apikey", session.anonKey)
                setRequestProperty("Authorization", "Bearer ${session.accessToken}")
            }
            val body = JSONObject().apply {
                put("messageId", messageId)
            }
            OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }
            val code = conn.responseCode
            Log.d(TAG, "[WORKER] triggerPushDispatch responseCode=$code")
        } catch (e: Exception) {
            Log.w(TAG, "[WORKER] triggerPushDispatch error (non-fatal): ${e.message}")
        }
    }
}
