package com.voryn.app

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log

class IncomingCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val callId = intent.getStringExtra("call_id") ?: intent.getStringExtra("callId") ?: ""
        Log.d("VorynCall", "[NATIVE_CALL] IncomingCallActionReceiver action=$action callId=$callId")

        if (action == "com.voryn.app.ACTION_ACCEPT_CALL") {
            val acceptTapTime = SystemClock.elapsedRealtime()
            Log.d("VorynCall", "[LOCK_ACCEPT] accept_tap callId=$callId")
            Log.d("VorynCall", "[CALL_LATENCY] accept_tap_native callId=$callId elapsed=0ms")

            val ok = IncomingCallNotificationManager.setPendingCallAccepting(context, callId)
            if (!ok) {
                return
            }
            IncomingCallRingtoneManager.stop("accept", if (callId.isNotBlank()) callId else null)
            IncomingCallActivity.dismiss()

            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (callId.isNotBlank()) {
                    nm.cancel(callId.hashCode())
                }
            } catch (_: Exception) {}

            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val isLocked = km.isKeyguardLocked
            Log.d("VorynCall", "[LOCK_ACCEPT] keyguardLocked=$isLocked")

            VorynCallHostManager.claimCall(
                callId,
                VorynCallHostManager.HostType.LOCKED_CALL,
                VorynCallStateManager.CallState.ACCEPTING,
                VorynCallHostManager.CallPresentationOrigin.EXTERNAL
            )
            Log.d("VorynCall", "[ACCEPT] CallActivity launch callId=$callId keyguardLocked=$isLocked")

            val targetClass = VorynCallActivity::class.java

            val callType = intent.getStringExtra("call_type") ?: intent.getStringExtra("callType") ?: "audio"
            val callerName = intent.getStringExtra("caller_name") ?: intent.getStringExtra("callerName") ?: "Voryn User"

            val acceptIntent = Intent(context, targetClass).apply {
                setAction("ACCEPT_CALL")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("action_id", "accept")
                putExtra("action", "accept")
                putExtra("call_id", callId)
                putExtra("callId", callId)
                putExtra("call_type", callType)
                putExtra("callType", callType)
                putExtra("caller_name", callerName)
                putExtra("callerName", callerName)
                putExtra("call_origin", "EXTERNAL")
                putExtra("origin", "EXTERNAL")
                putExtra("accept_timestamp", acceptTapTime)
            }
            context.startActivity(acceptIntent)
        } else if (action == "com.voryn.app.ACTION_END_ACTIVE_CALL") {
            Log.d("VorynCall", "[ACTIVE_SERVICE] End tapped from notification callId=$callId")
            VorynCallPlatformBridge.notifyCallTerminal(callId, "local_end")
            VorynActiveCallService.stop(context, callId, "local_end")
            VorynCallStateManager.transition(context, callId, VorynCallStateManager.CallState.TERMINAL)
            VorynCallActivity.dismiss()
        } else if (action == "com.voryn.app.ACTION_DECLINE_CALL" || action == "decline") {
            IncomingCallNotificationManager.clearPendingIncomingCall(context, callId)
            IncomingCallRingtoneManager.stop("decline", if (callId.isNotBlank()) callId else null)
            IncomingCallActivity.dismiss()

            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (callId.isNotBlank()) {
                    nm.cancel(callId.hashCode())
                }
            } catch (_: Exception) {}

            // Save to SharedPreferences so Flutter handles backend decline if needed
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putString("flutter.voryn.pending_call_decline", callId).apply()
            } catch (_: Exception) {}

            MainActivity.notifyCallDeclined(callId)
        }
    }
}
