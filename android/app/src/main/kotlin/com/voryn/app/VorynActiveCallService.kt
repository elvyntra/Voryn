package com.voryn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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

        @Volatile
        var isRunning = false

        @Volatile
        var isScreenSharing = false

        const val ACTION_START_CALL = "com.voryn.app.ACTION_START_ACTIVE_CALL"
        const val ACTION_STOP_CALL = "com.voryn.app.ACTION_STOP_ACTIVE_CALL"
        const val ACTION_SET_SCREEN_SHARE = "com.voryn.app.ACTION_SET_SCREEN_SHARE"

        fun setScreenShareActive(context: Context, active: Boolean) {
            isScreenSharing = active
            val intent = Intent(context, VorynActiveCallService::class.java).apply {
                action = ACTION_SET_SCREEN_SHARE
                putExtra("is_screen_sharing", active)
            }
            try {
                if (active) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    if (isRunning) {
                        context.startService(intent)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "[ACTIVE_SERVICE] failed to update screen share state: ${e.message}")
            }
        }

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

        if (action == ACTION_SET_SCREEN_SHARE) {
            isScreenSharing = intent?.getBooleanExtra("is_screen_sharing", false) ?: false
            ensureChannel()
            val currentCallId = VorynCallStateManager.getCurrentCallId(this) ?: ""
            val currentCallerName = VorynCallStateManager.getCallerName(this)
            val currentCallType = VorynCallStateManager.getCallType(this)

            if (isScreenSharing) {
                startOngoingNotification(currentCallId, currentCallerName, currentCallType)
            } else {
                if (currentCallId.isNotBlank()) {
                    startOngoingNotification(currentCallId, currentCallerName, currentCallType)
                } else {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                    } else {
                        @Suppress("DEPRECATION")
                        stopForeground(true)
                    }
                    isRunning = false
                    stopSelf()
                }
            }
            return START_NOT_STICKY
        }

        if (action == ACTION_STOP_CALL) {
            val multi = VorynCallStateManager.getMultiCallState(this)
            if (multi.heldCallId != null && multi.heldCallId != callId) {
                Log.d(TAG, "[ACTIVE_SERVICE] stop requested for callId=$callId, but held call ${multi.heldCallId} exists. Retaining service.")
                return START_NOT_STICKY
            }
            Log.d(TAG, "[ACTIVE_SERVICE] stop reason=$reason callId=$callId")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            isRunning = false
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
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
        val isLocked = km?.isKeyguardLocked ?: false
        val targetClass = if (callId.isNotBlank()) VorynCallActivity::class.java else MainActivity::class.java

        // Return to call intent
        val returnIntent = Intent(this, targetClass).apply {
            action = if (callId.isNotBlank()) "RETURN_TO_CALL" else "RETURN_TO_MEETING"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            if (callId.isNotBlank()) {
                putExtra("call_id", callId)
                putExtra("callId", callId)
                putExtra("call_type", callType)
                putExtra("caller_name", callerName)
            }
        }
        val returnPendingIntent = PendingIntent.getActivity(
            this,
            (callId.ifBlank { "voryn_screen_share" } + "_return").hashCode(),
            returnIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = if (isScreenSharing) {
            "VoRyn Screen Sharing"
        } else {
            "Voryn call in progress"
        }
        val effectiveCallerName = if (callerName.isNotBlank()) callerName else "VoRyn"
        val contentText = if (isScreenSharing) {
            if (callId.isNotBlank()) "$effectiveCallerName · Screen sharing active" else "Sharing screen in meeting"
        } else {
            "$effectiveCallerName · ${if (callType == "video") "Video call" else "Audio call"}"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(contentText)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(returnPendingIntent)
            .addAction(0, if (callId.isNotBlank()) "Return to call" else "Return to VoRyn", returnPendingIntent)

        if (callId.isNotBlank()) {
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
            builder.addAction(0, "End", endPendingIntent)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    val person = androidx.core.app.Person.Builder()
                        .setName(effectiveCallerName)
                        .setImportant(true)
                        .build()
                    val callStyle = NotificationCompat.CallStyle.forOngoingCall(
                        person,
                        endPendingIntent
                    )
                    builder.setStyle(callStyle)
                } catch (e: Exception) {
                    Log.w(TAG, "[ACTIVE_SERVICE] CallStyle.forOngoingCall fallback: ${e.message}")
                }
            }
        }

        val notification = builder.build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val hasMicPerm = ContextCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED

                var fgType = 0
                if (hasMicPerm) {
                    fgType = fgType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                if (isScreenSharing) {
                    fgType = fgType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                }
                if (fgType == 0) {
                    fgType = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                startForeground(NOTIFICATION_ID, notification, fgType)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "[ACTIVE_CALL_SERVICE] start callId=$callId isScreenSharing=$isScreenSharing")
            Log.d(TAG, "[ACTIVE_NOTIFICATION] posted callId=$callId")
            isRunning = true
        } catch (e: Exception) {
            Log.e(TAG, "[ACTIVE_SERVICE] startForeground error: ${e.message}")
        }
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }
}
