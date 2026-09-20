package com.voryn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class VorynActiveCallService : Service() {

    companion object {
        private const val TAG = "VorynCall"
        private const val CHANNEL_ID = "voryn_active_calls_v1"
        private const val CHANNEL_NAME = "Active calls"
        private const val NOTIFICATION_ID = 4001

        const val ACTION_START_CALL = "com.voryn.app.ACTION_START_ACTIVE_CALL"
        const val ACTION_STOP_CALL = "com.voryn.app.ACTION_STOP_ACTIVE_CALL"

        fun start(
            context: Context,
            callId: String,
            callerName: String,
            callType: String
        ) {
            val intent = Intent(context, VorynActiveCallService::class.java).apply {
                action = ACTION_START_CALL
                putExtra("call_id", callId)
                putExtra("caller_name", callerName)
                putExtra("call_type", callType)
            }
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (e: Exception) {
                Log.e(TAG, "[ACTIVE_SERVICE] failed to start foreground service: ${e.message}")
            }
        }

        fun stop(context: Context, callId: String, reason: String = "terminal") {
            val intent = Intent(context, VorynActiveCallService::class.java).apply {
                action = ACTION_STOP_CALL
                putExtra("call_id", callId)
                putExtra("reason", reason)
            }
            try {
                context.startService(intent)
            } catch (e: Exception) {
                Log.e(TAG, "[ACTIVE_SERVICE] failed to stop foreground service: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val callId = intent?.getStringExtra("call_id") ?: ""
        val callerName = intent?.getStringExtra("caller_name") ?: "Voryn User"
        val callType = intent?.getStringExtra("call_type") ?: "audio"
        val reason = intent?.getStringExtra("reason") ?: "normal"

        if (action == ACTION_STOP_CALL) {
            Log.d(TAG, "[ACTIVE_SERVICE] stop reason=$reason callId=$callId")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        if (callId.isNotBlank()) {
            startOngoingNotification(callId, callerName, callType)
        }

        return START_NOT_STICKY
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Ongoing active Voryn call notification"
                    setSound(null, null)
                    enableVibration(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun startOngoingNotification(
        callId: String,
        callerName: String,
        callType: String
    ) {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
        val isLocked = km.isKeyguardLocked
        val targetClass = VorynCallActivity::class.java

        // Return to call intent
        val returnIntent = Intent(this, targetClass).apply {
            action = "RETURN_TO_CALL"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            putExtra("call_id", callId)
            putExtra("callId", callId)
            putExtra("call_type", callType)
            putExtra("caller_name", callerName)
        }
        val returnPendingIntent = PendingIntent.getActivity(
            this,
            (callId + "_return").hashCode(),
            returnIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // End call action intent
        val endIntent = Intent(this, IncomingCallActionReceiver::class.java).apply {
            action = "com.voryn.app.ACTION_END_ACTIVE_CALL"
            putExtra("call_id", callId)
        }
        val endPendingIntent = PendingIntent.getBroadcast(
            this,
            (callId + "_end").hashCode(),
            endIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = "Voryn call"
        val contentText = "$callerName · ${if (callType == "video") "Video call" else "Audio call"}"

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(contentText)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(returnPendingIntent)
            .addAction(0, "Return to call", returnPendingIntent)
            .addAction(0, "End", endPendingIntent)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "[ACTIVE_SERVICE] start callId=$callId")
            Log.d(TAG, "[ACTIVE_SERVICE] notification posted")
        } catch (e: Exception) {
            Log.e(TAG, "[ACTIVE_SERVICE] startForeground error: ${e.message}")
        }
    }
}
