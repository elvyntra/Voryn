package com.voryn.app

import android.app.KeyguardManager
import android.content.Context
import android.os.PowerManager
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

                // Check if user is already in an active or held call
                if (VorynCallStateManager.hasActiveOrHeldCall(this)) {
                    val multiState = VorynCallStateManager.getMultiCallState(this)
                    if (multiState.activeCallId == callId || multiState.heldCallId == callId) {
                        Log.d("VorynCall", "[FCM_NATIVE] duplicate incoming push for current callId=$callId ignored")
                        return
                    }
                    if (multiState.activeCallId != null && multiState.heldCallId != null) {
                        Log.w("VorynCall", "[FCM_NATIVE] 3rd call arrived while active (${multiState.activeCallId}) and held (${multiState.heldCallId}) calls exist: capacity full, ignoring callId=$callId")
                        return
                    }

                    val callType = data["call_type"] ?: data["callType"] ?: "audio"
                    val callerName = data["caller_name"] ?: data["callerName"] ?: "Voryn User"

                    Log.d("VorynCall", "[FCM_NATIVE] incoming call waiting: callId=$callId activeCallId=${multiState.activeCallId}")
                    VorynCallStateManager.recordWaitingCall(this, callId, callType, callerName)
                    IncomingCallRingtoneManager.playCallWaitingTone(this)
                    IncomingCallNotificationManager.showWaitingCall(this, callId, callerName, callType)
                    VorynCallPlatformBridge.notifyCallWaiting(callId, callerName, callType)
                    return
                }

                val existingPending = IncomingCallNotificationManager.getPendingIncomingCall(this)
                val existingCallId = existingPending?.get("callId") as? String
                val existingState = existingPending?.get("state") as? String
                if (existingCallId == callId && (existingState == "accepting" || existingState == "pending_incoming")) {
                    Log.d("VorynCall", "[FCM_NATIVE] duplicate incoming_call ignored callId=$callId state=$existingState")
                    return
                }

                val callType = data["call_type"] ?: data["callType"] ?: "audio"
                val callerName = data["caller_name"] ?: data["callerName"] ?: "Voryn User"

                val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                val keyguardLocked = km.isKeyguardLocked
                val screenInteractive = pm.isInteractive
                val appForeground = MainActivity.isAppInForeground

                val presentation = when {
                    keyguardLocked || !screenInteractive -> "NATIVE_LOCKSCREEN"
                    appForeground -> "FLUTTER_FOREGROUND"
                    else -> "NOTIFICATION"
                }

                Log.d(
                    "VorynCall",
                    "[INCOMING_PRESENTATION] keyguardLocked=$keyguardLocked screenInteractive=$screenInteractive " +
                        "appForeground=$appForeground presentation=$presentation"
                )

                when (presentation) {
                    "NATIVE_LOCKSCREEN" -> {
                        IncomingCallNotificationManager.showIncomingCall(
                            this,
                            callId,
                            callerName,
                            callType,
                            IncomingCallNotificationManager.IncomingNotificationMode.FULL_SCREEN_CALL_STYLE
                        )
                    }
                    "FLUTTER_FOREGROUND" -> {
                        IncomingCallNotificationManager.showIncomingCall(
                            this,
                            callId,
                            callerName,
                            callType,
                            IncomingCallNotificationManager.IncomingNotificationMode.STANDARD_HEADS_UP
                        )
                        MainActivity.notifyIncomingCall(callId, callerName, callType)
                    }
                    "NOTIFICATION" -> {
                        IncomingCallNotificationManager.showIncomingCall(
                            this,
                            callId,
                            callerName,
                            callType,
                            IncomingCallNotificationManager.IncomingNotificationMode.STANDARD_HEADS_UP
                        )
                    }
                }
            }
            "cancel_call", "call_cancelled", "call_ended", "call_completed", "call_declined", "call_missed" -> {
                if (callId.isBlank()) return
                Log.d("VorynCall", "[FCM_NATIVE] terminal push received type=$type callId=$callId")
                val multiState = VorynCallStateManager.getMultiCallState(this)
                if (multiState.waitingCallId == callId) {
                    Log.d("VorynCall", "[FCM_NATIVE] waiting call cancelled callId=$callId")
                    VorynCallStateManager.clearWaitingCall(this, callId)
                    IncomingCallNotificationManager.cancelWaitingCallNotification(this, callId)
                    VorynCallPlatformBridge.notifyCallWaitingCancelled(callId)
                    return
                }

                IncomingCallNotificationManager.cancelIncomingCall(this, callId, "remote_terminal")
                IncomingCallActivity.dismiss()

                VorynCallPlatformBridge.notifyCallTerminal(callId, type)
            }
            "call_message" -> {
                val messageId = data["message_id"] ?: data["id"] ?: ""
                val threadId = data["thread_id"] ?: ""
                val senderUid = data["sender_uid"] ?: ""
                val senderName = data["sender_name"] ?: "Voryn User"
                val body = data["body"] ?: ""
                val remindToCall = data["remind_to_call"] == "true"
                val version = data["message_version"]?.toLongOrNull() ?: 1L
                val timestamp = System.currentTimeMillis()

                val appState = if (MainActivity.isAppInForeground) "FOREGROUND" else "BACKGROUND_OR_CLOSED"
                Log.d("VorynMsg", "[MESSAGE_FCM] phase=enter type=call_message messageId=$messageId threadId=$threadId version=$version appState=$appState")

                if (threadId.isNotBlank() && body.isNotBlank()) {
                    Log.d("VorynMsg", "[MESSAGE_FCM] phase=before_notification")
                    VorynMessageNotificationManager.showMessageNotification(
                        this,
                        messageId,
                        threadId,
                        senderUid,
                        senderName,
                        body,
                        remindToCall,
                        timestamp,
                        version
                    )
                    Log.d("VorynMsg", "[MESSAGE_FCM] phase=after_notification")

                    Log.d("VorynMsg", "[MESSAGE_FCM] phase=before_delegate")
                    MainActivity.notifyIncomingMessage(threadId, messageId, senderUid, body)
                    Log.d("VorynMsg", "[MESSAGE_FCM] phase=complete")
                }
                return
            }
            "call_message_edited" -> {
                val messageId = data["message_id"] ?: data["id"] ?: ""
                val threadId = data["thread_id"] ?: ""
                val body = data["body"] ?: ""
                val remindToCall = data["remind_to_call"] == "true"
                val version = data["message_version"]?.toLongOrNull() ?: 1L

                Log.d("VorynMsg", "[MESSAGE_FCM] phase=enter type=call_message_edited messageId=$messageId threadId=$threadId version=$version")

                if (threadId.isNotBlank() && messageId.isNotBlank() && body.isNotBlank()) {
                    VorynMessageNotificationManager.updateMessageNotification(
                        this,
                        messageId,
                        threadId,
                        body,
                        remindToCall,
                        version
                    )
                }
                return
            }
            "call_message_deleted" -> {
                val messageId = data["message_id"] ?: data["id"] ?: ""
                val threadId = data["thread_id"] ?: ""
                val version = data["message_version"]?.toLongOrNull() ?: 1L

                Log.d("VorynMsg", "[MESSAGE_FCM] phase=enter type=call_message_deleted messageId=$messageId threadId=$threadId version=$version")

                if (threadId.isNotBlank() && messageId.isNotBlank()) {
                    VorynMessageNotificationManager.deleteMessageNotification(
                        this,
                        messageId,
                        threadId,
                        version
                    )
                }
                return
            }
            else -> {
                super.onMessageReceived(remoteMessage)
            }
        }
    }
}
