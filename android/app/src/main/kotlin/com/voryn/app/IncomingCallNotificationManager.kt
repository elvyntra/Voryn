package com.voryn.app

import android.Manifest
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat

object IncomingCallNotificationManager {
    private const val CHANNEL_ID = "voryn_incoming_calls_v4"
    private const val CHANNEL_NAME = "Incoming calls"

    private const val PREFS_PENDING = "voryn_pending_calls"
    private const val KEY_CALL_ID = "call_id"
    private const val KEY_CALL_TYPE = "call_type"
    private const val KEY_CALLER_NAME = "caller_name"
    private const val KEY_RECEIVED_AT = "received_at"
    private const val KEY_STATE = "call_state"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming Voryn call alerts"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }
    }

    fun recordPendingIncomingCall(
        context: Context,
        callId: String,
        callType: String,
        callerName: String
    ) {
        val prefs = context.getSharedPreferences(PREFS_PENDING, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_CALL_ID, callId)
            .putString(KEY_CALL_TYPE, callType)
            .putString(KEY_CALLER_NAME, callerName)
            .putLong(KEY_RECEIVED_AT, System.currentTimeMillis())
            .putString(KEY_STATE, "pending_incoming")
            .apply()
    }

    fun setPendingCallAccepting(context: Context, callId: String) {
        val prefs = context.getSharedPreferences(PREFS_PENDING, Context.MODE_PRIVATE)
        if (prefs.getString(KEY_CALL_ID, null) == callId) {
            prefs.edit().putString(KEY_STATE, "accepting").apply()
        }
    }

    fun getPendingIncomingCall(context: Context): Map<String, Any>? {
        val prefs = context.getSharedPreferences(PREFS_PENDING, Context.MODE_PRIVATE)
        val callId = prefs.getString(KEY_CALL_ID, null) ?: return null
        val state = prefs.getString(KEY_STATE, "pending_incoming") ?: "pending_incoming"
        return mapOf(
            "callId" to callId,
            "callType" to (prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"),
            "callerName" to (prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"),
            "receivedAt" to prefs.getLong(KEY_RECEIVED_AT, 0L),
            "state" to state
        )
    }

    fun clearPendingIncomingCall(context: Context, callId: String? = null) {
        val prefs = context.getSharedPreferences(PREFS_PENDING, Context.MODE_PRIVATE)
        if (callId == null || prefs.getString(KEY_CALL_ID, null) == callId) {
            prefs.edit().clear().apply()
        }
    }

    fun showIncomingCall(
        context: Context,
        callId: String,
        callerName: String,
        callType: String
    ) {
        ensureChannel(context)
        recordPendingIncomingCall(context, callId, callType, callerName)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager

        val appForeground = MainActivity.isAppInForeground
        val keyguardLocked = km.isKeyguardLocked
        val screenInteractive = pm.isInteractive
        val notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
        val notificationPermissionGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val canUseFullScreenIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            manager.canUseFullScreenIntent()
        } else {
            true
        }
        val channelImportance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.getNotificationChannel(CHANNEL_ID)?.importance?.toString() ?: "missing"
        } else {
            "legacy"
        }

        Log.d("VorynCall", "[INCOMING] callId=$callId")
        Log.d("VorynCall", "[INCOMING] appForeground=$appForeground")
        Log.d("VorynCall", "[INCOMING] keyguardLocked=$keyguardLocked")
        Log.d("VorynCall", "[INCOMING] screenInteractive=$screenInteractive")
        Log.d("VorynCall", "[INCOMING] notificationsEnabled=$notificationsEnabled")
        Log.d("VorynCall", "[INCOMING] notificationPermissionGranted=$notificationPermissionGranted")
        Log.d("VorynCall", "[INCOMING] canUseFullScreenIntent=$canUseFullScreenIntent")
        Log.d("VorynCall", "[INCOMING] channelId=$CHANNEL_ID")
        Log.d("VorynCall", "[INCOMING] channelImportance=$channelImportance")
        Log.d("VorynCall", "[INCOMING] fullScreenPendingIntentTarget=IncomingCallActivity")

        // Start ringing sound & vibration through authoritative ringtone manager
        IncomingCallRingtoneManager.start(context, callId)

        // 1. Full-screen intent pointing directly to IncomingCallActivity
        val fullScreenIntent = Intent(context, IncomingCallActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("call_id", callId)
            putExtra("caller_name", callerName)
            putExtra("call_type", callType)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            callId.hashCode(),
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 2. Decline action (BroadcastReceiver -> no Flutter shell launch)
        val declineIntent = Intent(context, IncomingCallActionReceiver::class.java).apply {
            action = "com.voryn.app.ACTION_DECLINE_CALL"
            putExtra("call_id", callId)
        }
        val declinePendingIntent = PendingIntent.getBroadcast(
            context,
            (callId + "_decline").hashCode(),
            declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 3. Accept action (Launches MainActivity directly into active call with monotonic timestamp)
        val acceptIntent = Intent(context, MainActivity::class.java).apply {
            action = "ACCEPT_CALL"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("action_id", "accept")
            putExtra("action", "accept")
            putExtra("call_id", callId)
            putExtra("callId", callId)
            putExtra("call_type", callType)
            putExtra("callType", callType)
            putExtra("accept_timestamp", SystemClock.elapsedRealtime())
        }
        val acceptPendingIntent = PendingIntent.getActivity(
            context,
            (callId + "_accept").hashCode(),
            acceptIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val callerPerson = Person.Builder()
            .setName(callerName.ifBlank { "Voryn User" })
            .setImportant(true)
            .build()

        val callStyle = NotificationCompat.CallStyle.forIncomingCall(
            callerPerson,
            declinePendingIntent,
            acceptPendingIntent
        )

        val isVideo = callType == "video"
        val title = if (isVideo) "Incoming video call" else "Incoming call"

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(callerName)
            .setStyle(callStyle)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(fullScreenPendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(true)
            .setSound(null)
            .build()

        manager.notify(callId.hashCode(), notification)
        Log.d("VorynCall", "[INCOMING] notificationPosted")
    }

    fun cancelIncomingCall(context: Context, callId: String, reason: String = "remote_terminal") {
        try {
            clearPendingIncomingCall(context, callId)
            IncomingCallRingtoneManager.stop(reason, callId)
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(callId.hashCode())
        } catch (_: Exception) {}
    }
}
