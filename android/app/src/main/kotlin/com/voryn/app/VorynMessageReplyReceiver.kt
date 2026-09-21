package com.voryn.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.RemoteInput
import androidx.work.BackoffPolicy
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.UUID
import java.util.concurrent.TimeUnit

class VorynMessageReplyReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "VorynReplyReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val threadId = intent.getStringExtra(VorynMessageNotificationManager.EXTRA_THREAD_ID) ?: return

        Log.d(TAG, "[REPLY_RCV] onReceive action=$action threadId=$threadId")

        when (action) {
            VorynMessageNotificationManager.ACTION_REPLY_MESSAGE -> {
                val bundle = RemoteInput.getResultsFromIntent(intent)
                val replyText = bundle?.getCharSequence(VorynMessageNotificationManager.KEY_TEXT_REPLY)?.toString()?.trim()

                if (replyText.isNullOrEmpty()) {
                    Log.w(TAG, "[REPLY_RCV] replyText is empty")
                    return
                }

                if (replyText.length > 120) {
                    Log.w(TAG, "[REPLY_RCV] replyText exceeds 120 characters")
                    VorynMessageNotificationManager.updateFailedNotification(
                        context,
                        threadId,
                        "Message too long (max 120 chars)"
                    )
                    return
                }

                val recipientUid = intent.getStringExtra(VorynMessageNotificationManager.EXTRA_RECIPIENT_UID) ?: ""
                val clientMessageId = UUID.randomUUID().toString()

                Log.d(TAG, "[REPLY_RCV] enqueuing reply worker clientMessageId=$clientMessageId")

                // Update notification immediately to show "(Sending…)"
                VorynMessageNotificationManager.updateSendingNotification(context, threadId, replyText)

                // Enqueue durable WorkManager job
                val inputData = Data.Builder()
                    .putString(VorynMessageReplyWorker.KEY_THREAD_ID, threadId)
                    .putString(VorynMessageReplyWorker.KEY_RECIPIENT_UID, recipientUid)
                    .putString(VorynMessageReplyWorker.KEY_BODY, replyText)
                    .putString(VorynMessageReplyWorker.KEY_CLIENT_MESSAGE_ID, clientMessageId)
                    .build()

                val workRequest = OneTimeWorkRequestBuilder<VorynMessageReplyWorker>()
                    .setInputData(inputData)
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 5, TimeUnit.SECONDS)
                    .build()

                WorkManager.getInstance(context).enqueue(workRequest)
            }
            VorynMessageNotificationManager.ACTION_MARK_READ -> {
                Log.d(TAG, "[REPLY_RCV] mark as read for threadId=$threadId")
                VorynMessageNotificationManager.dismissThreadNotification(context, threadId)

                val inputData = Data.Builder()
                    .putString(VorynMessageReplyWorker.KEY_THREAD_ID, threadId)
                    .putBoolean(VorynMessageReplyWorker.KEY_IS_MARK_READ, true)
                    .build()

                val workRequest = OneTimeWorkRequestBuilder<VorynMessageReplyWorker>()
                    .setInputData(inputData)
                    .build()

                WorkManager.getInstance(context).enqueue(workRequest)
            }
        }
    }
}
