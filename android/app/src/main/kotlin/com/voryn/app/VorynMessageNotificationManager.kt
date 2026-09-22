package com.voryn.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import org.json.JSONArray
import org.json.JSONObject

object VorynMessageNotificationManager {
    private const val TAG = "VorynMsgNotif"
    const val CHANNEL_ID = "voryn_messages_v1"
    private const val CHANNEL_NAME = "Call Messages"
    const val NOTIFICATION_ID = 3001

    const val KEY_TEXT_REPLY = "key_text_reply"
    const val ACTION_REPLY_MESSAGE = "com.voryn.app.ACTION_REPLY_MESSAGE"
    const val ACTION_MARK_READ = "com.voryn.app.ACTION_MARK_READ"
    const val ACTION_NOTIFICATION_DISMISSED = "com.voryn.app.ACTION_NOTIFICATION_DISMISSED"

    const val EXTRA_THREAD_ID = "thread_id"
    const val EXTRA_RECIPIENT_UID = "recipient_uid"
    const val EXTRA_SENDER_NAME = "sender_name"
    const val EXTRA_MESSAGE_ID = "message_id"

    private fun getTag(threadId: String): String = "voryn_message_$threadId"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming call messages and direct replies"
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun getHistoryPrefs(context: Context, threadId: String) =
        context.getSharedPreferences("voryn_msg_cache_$threadId", Context.MODE_PRIVATE)

    data class CachedMessage(
        val messageId: String? = null,
        val text: String,
        val timestamp: Long,
        val isSelf: Boolean,
        val senderName: String,
        val version: Long = 1L,
        val isDeleted: Boolean = false,
        val isEdited: Boolean = false
    )

    fun clearThreadHistory(context: Context, threadId: String) {
        getHistoryPrefs(context, threadId).edit().clear().apply()
        Log.d(TAG, "[NOTIF] cleared history cache for threadId=$threadId")
    }

    fun isNotificationActive(context: Context, threadId: String): Boolean {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val tag = getTag(threadId)
        val active = nm.activeNotifications.any { it.tag == tag && it.id == NOTIFICATION_ID }
        Log.d(TAG, "[NOTIF] isNotificationActive tag=$tag result=$active")
        return active
    }

    private fun loadHistory(context: Context, threadId: String): List<CachedMessage> {
        val raw = getHistoryPrefs(context, threadId).getString("history", "[]") ?: "[]"
        val list = mutableListOf<CachedMessage>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                list.add(
                    CachedMessage(
                        messageId = if (obj.has("messageId")) obj.getString("messageId") else null,
                        text = obj.getString("text"),
                        timestamp = obj.getLong("timestamp"),
                        isSelf = obj.getBoolean("isSelf"),
                        senderName = obj.getString("senderName"),
                        version = obj.optLong("version", 1L),
                        isDeleted = obj.optBoolean("isDeleted", false),
                        isEdited = obj.optBoolean("isEdited", false)
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "[NOTIF] error parsing history: ${e.message}")
        }
        return list
    }

    private fun saveHistory(context: Context, threadId: String, history: List<CachedMessage>) {
        val arr = JSONArray()
        val trimmed = if (history.size > 10) history.takeLast(10) else history
        for (msg in trimmed) {
            arr.put(
                JSONObject().apply {
                    if (msg.messageId != null) put("messageId", msg.messageId)
                    put("text", msg.text)
                    put("timestamp", msg.timestamp)
                    put("isSelf", msg.isSelf)
                    put("senderName", msg.senderName)
                    put("version", msg.version)
                    put("isDeleted", msg.isDeleted)
                    put("isEdited", msg.isEdited)
                }
            )
        }
        getHistoryPrefs(context, threadId).edit().putString("history", arr.toString()).apply()
    }

    fun showMessageNotification(
        context: Context,
        messageId: String,
        threadId: String,
        senderUid: String,
        senderName: String,
        body: String,
        remindToCall: Boolean,
        timestamp: Long,
        version: Long = 1L
    ) {
        createNotificationChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val nmc = androidx.core.app.NotificationManagerCompat.from(context)
        val globalPerm = nmc.areNotificationsEnabled()
        val channelEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = nm.getNotificationChannel(CHANNEL_ID)
            channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE
        } else {
            true
        }
        Log.d(TAG, "[MESSAGE_NOTIFICATION] globalPermission=$globalPerm channel=$CHANNEL_ID channelEnabled=$channelEnabled")
        Log.d(TAG, "[MESSAGE_NOTIFICATION] messageId=$messageId threadId=$threadId version=$version action=post")

        val history = loadHistory(context, threadId).toMutableList()
        val formattedBody = if (remindToCall) "📞 $body" else body

        val existingIndex = history.indexOfFirst { it.messageId == messageId }
        if (existingIndex != -1) {
            Log.d(TAG, "[MESSAGE_NOTIFICATION] duplicate messageId=$messageId already in history, updating")
            history[existingIndex] = CachedMessage(
                messageId = messageId,
                text = formattedBody,
                timestamp = timestamp,
                isSelf = false,
                senderName = senderName,
                version = version,
                isDeleted = false,
                isEdited = false
            )
        } else {
            history.add(
                CachedMessage(
                    messageId = messageId,
                    text = formattedBody,
                    timestamp = timestamp,
                    isSelf = false,
                    senderName = senderName,
                    version = version,
                    isDeleted = false,
                    isEdited = false
                )
            )
        }
        saveHistory(context, threadId, history)

        buildAndNotify(context, nm, threadId, senderUid, senderName, history, null, isSilentMutation = false)
    }

    fun updateMessageNotification(
        context: Context,
        messageId: String,
        threadId: String,
        body: String,
        remindToCall: Boolean,
        incomingVersion: Long
    ) {
        if (!isNotificationActive(context, threadId)) {
            Log.d(TAG, "[MESSAGE_MUTATION] edit ignored because notification is not active for threadId=$threadId")
            return
        }

        val history = loadHistory(context, threadId).toMutableList()
        val msgIndex = history.indexOfFirst { it.messageId == messageId }
        if (msgIndex == -1) {
            Log.d(TAG, "[MESSAGE_MUTATION] edit ignored: messageId=$messageId not found in notification history")
            return
        }

        val currentMsg = history[msgIndex]
        if (incomingVersion <= currentMsg.version) {
            Log.d(TAG, "[MESSAGE_MUTATION] edit ignored: incomingVersion=$incomingVersion <= currentVersion=${currentMsg.version}")
            return
        }

        if (currentMsg.isDeleted) {
            Log.d(TAG, "[MESSAGE_MUTATION] edit ignored: messageId=$messageId is already deleted")
            return
        }

        val formattedBody = if (remindToCall) "📞 $body" else body
        history[msgIndex] = currentMsg.copy(
            text = formattedBody,
            version = incomingVersion,
            isEdited = true
        )
        saveHistory(context, threadId, history)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        buildAndNotify(context, nm, threadId, "", "", history, null, isSilentMutation = true)
        Log.d(TAG, "[MESSAGE_MUTATION] edit applied messageId=$messageId version=$incomingVersion")
    }

    fun deleteMessageNotification(
        context: Context,
        messageId: String,
        threadId: String,
        incomingVersion: Long
    ) {
        if (!isNotificationActive(context, threadId)) {
            Log.d(TAG, "[MESSAGE_MUTATION] delete ignored because notification is not active for threadId=$threadId")
            val history = loadHistory(context, threadId).toMutableList()
            val msgIndex = history.indexOfFirst { it.messageId == messageId }
            if (msgIndex != -1) {
                history[msgIndex] = history[msgIndex].copy(
                    text = "Message deleted",
                    version = incomingVersion,
                    isDeleted = true
                )
                saveHistory(context, threadId, history)
            }
            return
        }

        val history = loadHistory(context, threadId).toMutableList()
        val msgIndex = history.indexOfFirst { it.messageId == messageId }
        if (msgIndex == -1) {
            Log.d(TAG, "[MESSAGE_MUTATION] delete ignored: messageId=$messageId not in history")
            return
        }

        val currentMsg = history[msgIndex]
        if (incomingVersion <= currentMsg.version && currentMsg.isDeleted) {
            Log.d(TAG, "[MESSAGE_MUTATION] delete ignored: already deleted with version >= incomingVersion")
            return
        }

        history[msgIndex] = currentMsg.copy(
            text = "Message deleted",
            version = incomingVersion,
            isDeleted = true
        )
        saveHistory(context, threadId, history)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val hasActiveMessages = history.any { !it.isDeleted }
        if (!hasActiveMessages) {
            Log.d(TAG, "[MESSAGE_MUTATION] all messages in thread are deleted, dismissing notification")
            dismissThreadNotification(context, threadId)
        } else {
            buildAndNotify(context, nm, threadId, "", "", history, null, isSilentMutation = true)
        }
        Log.d(TAG, "[MESSAGE_MUTATION] delete applied messageId=$messageId version=$incomingVersion")
    }

    fun removeMessageFromNotification(
        context: Context,
        threadId: String,
        messageId: String
    ) {
        val history = loadHistory(context, threadId).toMutableList()
        val index = history.indexOfFirst { it.messageId == messageId }
        if (index == -1) {
            Log.d(TAG, "[MESSAGE_MUTATION] removeMessageFromNotification ignored: not in history")
            return
        }

        history.removeAt(index)
        saveHistory(context, threadId, history)

        if (!isNotificationActive(context, threadId)) {
            Log.d(TAG, "[MESSAGE_MUTATION] removeMessageFromNotification: cache cleaned, notification not active")
            return
        }

        val hasActiveMessages = history.any { !it.isDeleted }
        if (!hasActiveMessages || history.isEmpty()) {
            Log.d(TAG, "[MESSAGE_MUTATION] no active messages left, dismissing notification")
            dismissThreadNotification(context, threadId)
        } else {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            buildAndNotify(context, nm, threadId, "", "", history, null, isSilentMutation = true)
            Log.d(TAG, "[MESSAGE_MUTATION] removeMessageFromNotification applied silently messageId=$messageId")
        }
    }

    fun updateSendingNotification(
        context: Context,
        threadId: String,
        replyText: String
    ) {
        createNotificationChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val history = loadHistory(context, threadId).toMutableList()
        buildAndNotify(context, nm, threadId, "", "", history, "You: $replyText (Sending…)", isSilentMutation = true)
    }

    fun appendSentMessage(
        context: Context,
        threadId: String,
        sentText: String
    ) {
        createNotificationChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val history = loadHistory(context, threadId).toMutableList()
        history.add(
            CachedMessage(
                messageId = null,
                text = sentText,
                timestamp = System.currentTimeMillis(),
                isSelf = true,
                senderName = "You"
            )
        )
        saveHistory(context, threadId, history)
        buildAndNotify(context, nm, threadId, "", "", history, null, isSilentMutation = false)
    }

    fun updateFailedNotification(
        context: Context,
        threadId: String,
        failedText: String
    ) {
        createNotificationChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val history = loadHistory(context, threadId).toMutableList()
        buildAndNotify(context, nm, threadId, "", "", history, "Failed to send: $failedText", isSilentMutation = true)
    }

    private fun buildAndNotify(
        context: Context,
        nm: NotificationManager,
        threadId: String,
        senderUid: String,
        senderName: String,
        history: List<CachedMessage>,
        sendingStatus: String?,
        isSilentMutation: Boolean = false
    ) {
        Log.d(TAG, "[MESSAGE_NOTIFICATION] phase=build_start threadId=$threadId isSilentMutation=$isSilentMutation")
        val userPerson = Person.Builder().setName("You").setKey("self").build()
        val displayName = if (senderName.isNotBlank()) senderName else {
            history.firstOrNull { !it.isSelf }?.senderName ?: "Call Message"
        }

        val messagingStyle = NotificationCompat.MessagingStyle(userPerson)
            .setConversationTitle(displayName)

        for (msg in history) {
            val person = if (msg.isSelf) null else {
                Person.Builder().setName(msg.senderName).build()
            }
            messagingStyle.addMessage(msg.text, msg.timestamp, person)
        }

        if (sendingStatus != null) {
            messagingStyle.addMessage(sendingStatus, System.currentTimeMillis(), userPerson)
        }

        val contentIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("voryn://messages/thread/$threadId")
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            threadId.hashCode(),
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val deleteIntent = Intent(context, VorynMessageReplyReceiver::class.java).apply {
            action = ACTION_NOTIFICATION_DISMISSED
            data = Uri.parse("voryn://messages/dismiss/$threadId")
            putExtra(EXTRA_THREAD_ID, threadId)
        }
        val deletePendingIntent = PendingIntent.getBroadcast(
            context,
            threadId.hashCode() + 2,
            deleteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val remoteInput = RemoteInput.Builder(KEY_TEXT_REPLY)
            .setLabel("Reply…")
            .build()

        val replyIntent = Intent(context, VorynMessageReplyReceiver::class.java).apply {
            action = ACTION_REPLY_MESSAGE
            data = Uri.parse("voryn://messages/reply/$threadId")
            putExtra(EXTRA_THREAD_ID, threadId)
            putExtra(EXTRA_RECIPIENT_UID, senderUid)
            putExtra(EXTRA_SENDER_NAME, displayName)
        }

        val replyPendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            threadId.hashCode(),
            replyIntent,
            replyPendingFlags
        )

        val replyAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send,
            "Reply",
            replyPendingIntent
        ).addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(true)
            .build()

        val markReadIntent = Intent(context, VorynMessageReplyReceiver::class.java).apply {
            action = ACTION_MARK_READ
            data = Uri.parse("voryn://messages/read/$threadId")
            putExtra(EXTRA_THREAD_ID, threadId)
        }
        val markReadPendingIntent = PendingIntent.getBroadcast(
            context,
            threadId.hashCode() + 1,
            markReadIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val markReadAction = NotificationCompat.Action.Builder(
            android.R.drawable.checkbox_on_background,
            "Mark as Read",
            markReadPendingIntent
        ).build()

        val notifBuilder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setStyle(messagingStyle)
            .setContentIntent(contentPendingIntent)
            .setDeleteIntent(deletePendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .addAction(replyAction)
            .addAction(markReadAction)

        if (isSilentMutation) {
            notifBuilder.setOnlyAlertOnce(true)
            notifBuilder.setSilent(true)
        }

        val tag = getTag(threadId)
        Log.d(TAG, "[MESSAGE_NOTIFICATION] phase=notify_start tag=$tag id=$NOTIFICATION_ID silent=$isSilentMutation")
        nm.notify(tag, NOTIFICATION_ID, notifBuilder.build())
        Log.d(TAG, "[MESSAGE_NOTIFICATION] phase=notify_done tag=$tag id=$NOTIFICATION_ID")
    }

    fun dismissThreadNotification(context: Context, threadId: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val tag = getTag(threadId)
        nm.cancel(tag, NOTIFICATION_ID)
        clearThreadHistory(context, threadId)
        Log.d(TAG, "[NOTIF] dismissed tag=$tag and cleared history")
    }

    fun cancelAllMessageNotifications(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancelAll()
        Log.d(TAG, "[NOTIF] cancelAllMessageNotifications")
    }
}
