package com.voryn.app

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView

class IncomingCallActivity : Activity() {

    private var callId: String = ""
    private var callerName: String = "Voryn User"
    private var callType: String = "audio"

    companion object {
        private var activeInstance: IncomingCallActivity? = null

        fun dismiss() {
            activeInstance?.runOnUiThread {
                activeInstance?.finish()
                activeInstance = null
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = this

        // Lock screen display flags
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        setContentView(R.layout.activity_incoming_call)

        extractExtras(intent)

        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        Log.d("VorynCall", "[NATIVE_CALL] IncomingCallActivity onCreate callId=$callId")
        Log.d("VorynCall", "[NATIVE_CALL] keyguardLocked=${km.isKeyguardLocked}")
        Log.d("VorynCall", "[NATIVE_CALL] action=incoming")

        bindViews()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractExtras(intent)
        Log.d("VorynCall", "[NATIVE_CALL] onNewIntent callId=$callId")
        bindViews()
    }

    override fun onResume() {
        super.onResume()
        Log.d("VorynCall", "[NATIVE_CALL] onResume")
    }

    private fun extractExtras(intent: Intent?) {
        if (intent == null) return
        callId = intent.getStringExtra("call_id")
            ?: intent.getStringExtra("callId")
            ?: intent.getStringExtra("payload")
            ?: ""
        callerName = intent.getStringExtra("caller_name")
            ?: intent.getStringExtra("callerName")
            ?: "Voryn User"
        callType = intent.getStringExtra("call_type")
            ?: intent.getStringExtra("callType")
            ?: "audio"
    }

    private fun bindViews() {
        val tvCallerName = findViewById<TextView>(R.id.tv_caller_name)
        val tvCallType = findViewById<TextView>(R.id.tv_call_type)
        val tvAvatarInitials = findViewById<TextView>(R.id.tv_avatar_initials)
        val btnDecline = findViewById<FrameLayout>(R.id.btn_decline)
        val btnAccept = findViewById<FrameLayout>(R.id.btn_accept)

        tvCallerName.text = callerName.ifBlank { "Voryn User" }
        tvCallType.text = if (callType == "video") "Incoming video call…" else "Incoming audio call…"
        tvAvatarInitials.text = computeInitials(callerName)

        btnDecline.setOnClickListener {
            handleDecline()
        }

        btnAccept.setOnClickListener {
            handleAccept()
        }
    }

    override fun onDestroy() {
        Log.d("VorynCall", "[NATIVE_CALL] onDestroy")
        if (activeInstance == this) {
            activeInstance = null
        }
        IncomingCallRingtoneManager.stop("activity_destroy", if (callId.isNotBlank()) callId else null)
        super.onDestroy()
    }

    private fun handleDecline() {
        Log.d("VorynCall", "[NATIVE_CALL] decline")
        IncomingCallNotificationManager.clearPendingIncomingCall(this, callId)
        IncomingCallRingtoneManager.stop("decline", if (callId.isNotBlank()) callId else null)
        cancelCallNotification()

        // Notify action receiver to record decline without starting MainActivity
        val declineBroadcast = Intent(this, IncomingCallActionReceiver::class.java).apply {
            action = "com.voryn.app.ACTION_DECLINE_CALL"
            putExtra("call_id", callId)
        }
        sendBroadcast(declineBroadcast)

        finish()
    }

    private fun handleAccept() {
        Log.d("VorynCall", "[NATIVE_CALL] accept")
        val acceptTimestamp = android.os.SystemClock.elapsedRealtime()
        Log.d("VorynCall", "[CALL_LATENCY] accept_tap_native callId=$callId elapsed=0ms")
        IncomingCallNotificationManager.setPendingCallAccepting(this, callId)
        IncomingCallRingtoneManager.stop("accept", if (callId.isNotBlank()) callId else null)
        cancelCallNotification()

        val acceptIntent = Intent(this, MainActivity::class.java).apply {
            action = "ACCEPT_CALL"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("action_id", "accept")
            putExtra("action", "accept")
            putExtra("call_id", callId)
            putExtra("callId", callId)
            putExtra("call_type", callType)
            putExtra("callType", callType)
            putExtra("accept_timestamp", acceptTimestamp)
        }
        startActivity(acceptIntent)
        finish()
    }

    private fun cancelCallNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (callId.isNotBlank()) {
                nm.cancel(callId.hashCode())
            }
        } catch (_: Exception) {}
    }

    private fun computeInitials(name: String): String {
        val parts = name.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
        return when {
            parts.isEmpty() -> "VU"
            parts.size == 1 -> parts[0].take(2).uppercase()
            else -> (parts[0].take(1) + parts[1].take(1)).uppercase()
        }
    }
}
