package com.voryn.app

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class VorynFirebaseMessagingService : FlutterFirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("VorynCall", "[FCM_NATIVE] onNewToken tokenPrefix=${token.take(8)}")
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data
        val type = data["type"] ?: ""
        val callId = data["call_id"] ?: data["callId"] ?: ""
        val isAppInForeground = MainActivity.isAppInForeground

        Log.d("VorynCall", "[FCM_NATIVE] received callId=$callId appProcessCold=${!isAppInForeground} type=$type")

        when (type) {
            "incoming_call" -> {
                if (callId.isBlank()) return
                val existingPending = IncomingCallNotificationManager.getPendingIncomingCall(this)
                val existingCallId = existingPending?.get("callId") as? String
                val existingState = existingPending?.get("state") as? String
                if (existingCallId == callId && (existingState == "accepting" || existingState == "pending_incoming")) {
                    Log.d("VorynCall", "[FCM_NATIVE] duplicate incoming_call ignored callId=$callId state=$existingState")
                    return
                }

                val callType = data["call_type"] ?: data["callType"] ?: "audio"
                val callerName = data["caller_name"] ?: data["callerName"] ?: "Voryn User"

                IncomingCallNotificationManager.recordPendingIncomingCall(this, callId, callType, callerName)
                IncomingCallNotificationManager.showIncomingCall(this, callId, callerName, callType)

                val km = getSystemService(android.content.Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
                val isKeyguardLocked = km?.isKeyguardLocked ?: false
                if (isAppInForeground && !isKeyguardLocked) {
                    MainActivity.notifyIncomingCall(callId, callerName, callType)
                }
            }
            "cancel_call", "call_cancelled", "call_ended", "call_completed", "call_declined", "call_missed" -> {
                if (callId.isBlank()) return
                Log.d("VorynCall", "[FCM_NATIVE] terminal push received type=$type callId=$callId")
                IncomingCallNotificationManager.cancelIncomingCall(this, callId, "remote_terminal")
                IncomingCallActivity.dismiss()

                if (isAppInForeground) {
                    MainActivity.notifyCallTerminal(callId, type)
                }
            }
            else -> {
                super.onMessageReceived(remoteMessage)
            }
        }
    }
}
