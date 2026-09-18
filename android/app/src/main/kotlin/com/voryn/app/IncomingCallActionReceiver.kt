package com.voryn.app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class IncomingCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val callId = intent.getStringExtra("call_id") ?: ""
        Log.d("VorynCall", "[NATIVE_CALL] IncomingCallActionReceiver action=$action callId=$callId")

        if (action == "com.voryn.app.ACTION_DECLINE_CALL" || action == "decline") {
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
