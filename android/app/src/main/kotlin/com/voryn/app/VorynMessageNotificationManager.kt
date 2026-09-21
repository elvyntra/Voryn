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

    // Cached message history for MessagingStyle per thread
    private fun getHistoryPrefs(context: Context, threadId: String) =
        context.getSharedPreferences("voryn_msg_cache_$threadId", Context.MODE_PRIVATE)

    data class CachedMessage(
        val text: String,
        val timestamp: Long,
        val isSelf: Boolean,
        val senderName: String
    )

    private fun loadHistory(context: Context, threadId: String): List<CachedMessage> {
        val raw = getHistoryPrefs(context, threadId).getString("history", "[]") ?: "[]"
        val list = mutableListOf<CachedMessage>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                list.add(
                    CachedMessage(
                        text = obj.getString("text"),
                        timestamp = obj.getLong("timestamp"),
                        isSelf = obj.getBoolean("isSelf"),
                        senderName = obj.getString("senderName")
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
        // Keep at most 10 recent messages
        val trimmed = if (history.size > 10) history.takeLast(10) else history
        for (msg in trimmed) {
            arr.put(
                JSONObject().apply {
                    put("text", msg.text)
                    put("timestamp", msg.timestamp)
                    put("isSelf", msg.isSelf)
                    put("senderName", msg.senderName)
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
        timestamp: Long
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
        Log.d(TAG, "[MESSAGE_NOTIFICATION] messageId=$messageId threadId=$threadId action=post")

        // Update history
        val history = loadHistory(context, threadId).toMutableList()
        val formattedBody = if (remindToCall) "📞 $body" else body
        history.add(
            CachedMessage(
                text = formattedBody,
                timestamp = timestamp,
                isSelf = false,
                senderName = senderName
            )
        )
        saveHistory(context, threadId, history)

        buildAndNotify(context, nm, threadId, senderUid, senderName, history, null)
    }

    fun updateSendingNotification(
        context: Context,
        threadId: String,
        replyText: String
    ) {
        createNotificationChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val history = loadHistory(context, threadId).toMutableList()
        buildAndNotify(context, nm, threadId, "", "", history, "You: $replyText (Sending…)")
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
                text = sentText,
                timestamp = System.currentTimeMillis(),
                isSelf = true,
                senderName = "You"
            )
        )
        saveHistory(context, threadId, history)
        buildAndNotify(context, nm, threadId, "", "", history, null)
    }

    fun updateFailedNotification(
        context: Context,
        threadId: String,
        failedText: String
    ) {
        createNotificationChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val history = loadHistory(context, threadId).toMutableList()
        buildAndNotify(context, nm, threadId, "", "", history, "Failed to send: $failedText")
    }

    private fun buildAndNotify(
        context: Context,
        nm: NotificationManager,
        threadId: String,
        senderUid: String,
        senderName: String,
        history: List<CachedMessage>,
        sendingStatus: String?
    ) {
        Log.d(TAG, "[MESSAGE_NOTIFICATION] phase=build_start threadId=$threadId")
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

        // Tap content intent -> Opens thread in MainActivity
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

        // RemoteInput inline reply
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

        // Mark as read action
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
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .addAction(replyAction)
            .addAction(markReadAction)

        val tag = getTag(threadId)
        Log.d(TAG, "[MESSAGE_NOTIFICATION] phase=notify_start tag=$tag id=$NOTIFICATION_ID")
        nm.notify(tag, NOTIFICATION_ID, notifBuilder.build())
        Log.d(TAG, "[MESSAGE_NOTIFICATION] phase=notify_done tag=$tag id=$NOTIFICATION_ID")
    }

    fun dismissThreadNotification(context: Context, threadId: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val tag = getTag(threadId)
        nm.cancel(tag, NOTIFICATION_ID)
        Log.d(TAG, "[NOTIF] dismissed tag=$tag")
    }
}
