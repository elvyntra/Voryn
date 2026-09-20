package com.voryn.app

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class VorynCallPlatformBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val getInitialLaunchData: () -> Map<String, String>?,
    private val onFinishCall: () -> Unit,
    private val onSetCallPresentationVisible: ((Boolean) -> Unit)? = null
) {
    companion object {
        private const val CHANNEL_NAME = "com.voryn.app/lock_screen"
        private const val TAG = "VorynCall"

        fun notifyCallDeclined(callId: String) {
            MainActivity.activeInstance?.bridge?.methodChannel?.invokeMethod("onCallDeclined", mapOf("callId" to callId))
            VorynCallActivity.activeInstance?.bridge?.methodChannel?.invokeMethod("onCallDeclined", mapOf("callId" to callId))
        }

        fun notifyIncomingCall(callId: String, callerName: String, callType: String) {
            // Incoming ringing alerts in foreground only target MainActivity
            MainActivity.activeInstance?.bridge?.methodChannel?.invokeMethod(
                "onIncomingCall",
                mapOf(
                    "callId" to callId,
                    "callerName" to callerName,
                    "callType" to callType
                )
            )
        }

        fun notifyCallTerminal(callId: String, type: String) {
            MainActivity.activeInstance?.let { act ->
                VorynCallStateManager.transition(act, callId, VorynCallStateManager.CallState.TERMINAL)
                VorynActiveCallService.stop(act, callId, type)
            }
            VorynCallActivity.activeInstance?.let { act ->
                VorynCallStateManager.transition(act, callId, VorynCallStateManager.CallState.TERMINAL)
                VorynActiveCallService.stop(act, callId, type)
            }
            VorynCallEngineManager.destroyEngine(callId)
            MainActivity.activeInstance?.bridge?.methodChannel?.invokeMethod(
                "onCallTerminal",
                mapOf(
                    "callId" to callId,
                    "type" to type
                )
            )
            VorynCallActivity.activeInstance?.bridge?.methodChannel?.invokeMethod(
                "onCallTerminal",
                mapOf(
                    "callId" to callId,
                    "type" to type
                )
            )
        }
    }

    val methodChannel: MethodChannel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        methodChannel.setMethodCallHandler { call, result ->
            val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            when (call.method) {
                "getElapsedRealtimeMs" -> {
                    result.success(SystemClock.elapsedRealtime())
                }
                "getPendingIncomingCall" -> {
                    val pending = IncomingCallNotificationManager.getPendingIncomingCall(activity)
                    result.success(pending)
                }
                "clearPendingIncomingCall" -> {
                    val callId = call.argument<String>("callId")
                    IncomingCallNotificationManager.clearPendingIncomingCall(activity, callId)
                    result.success(true)
                }
                "canUseFullScreenIntent" -> {
                    val canUse = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        nm.canUseFullScreenIntent()
                    } else {
                        true
                    }
                    result.success(canUse)
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                            data = Uri.parse("package:${activity.packageName}")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        activity.startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "isKeyguardLocked" -> {
                    result.success(km.isKeyguardLocked)
                }
                "getInitialCallLaunch" -> {
                    val launch = getInitialLaunchData()
                    Log.d("VorynBoot", "[VORYN_BOOT] getInitialCallLaunch returned $launch")
                    result.success(launch)
                }
                "isCallOwnedByOtherHost" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val isOwned = if (activity is MainActivity) {
                        VorynCallHostManager.isCallOwnedByLockedCall(callId) ||
                            (VorynCallHostManager.isAnyCallOwnedByLockedCall() && VorynCallHostManager.getActiveCallId() != callId)
                    } else {
                        false
                    }
                    if (isOwned) {
                        Log.d(TAG, "[HOST_OWNERSHIP] callId=$callId is owned by LOCKED_CALL, suppressing MainActivity action")
                    }
                    result.success(isOwned)
                }
                "isProximitySupported" -> {
                    result.success(VorynProximityController.isSupported())
                }
                "updateProximityState" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val connected = call.argument<Boolean>("connected") ?: false
                    val mediaMode = call.argument<String>("mediaMode") ?: "audio"
                    val held = call.argument<Boolean>("held") ?: false
                    val ending = call.argument<Boolean>("ending") ?: false
                    VorynProximityController.updateCallState(
                        activity,
                        callId,
                        connected,
                        mediaMode,
                        held,
                        ending
                    )
                    result.success(true)
                }
                "markCallActive" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val callerName = call.argument<String>("callerName") ?: "Voryn User"
                    val callType = call.argument<String>("callType") ?: "audio"
                    if (callId.isNotBlank()) {
                        val host = if (activity is VorynCallActivity) "LOCKED_CALL" else "MAIN"
                        VorynCallStateManager.markCallActive(activity, callId, callerName, callType, host)
                        VorynActiveCallService.start(activity, callId, callerName, callType)
                    }
                    result.success(true)
                }
                "setCallPresentationVisible" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        Log.d(TAG, "[LOCKSCREEN] enabling active-call lockscreen visibility")
                    } else {
                        Log.d(TAG, "[LOCKSCREEN] disabling active-call lockscreen visibility")
                    }
                    onSetCallPresentationVisible?.invoke(enabled)
                    result.success(true)
                }
                "moveCallTaskBehindKeyguard" -> {
                    Log.d(TAG, "[LOCKSCREEN] moveCallTaskBehindKeyguard invoked")
                    onFinishCall()
                    result.success(true)
                }
                "showNativeIncomingCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val callerName = call.argument<String>("callerName") ?: "Voryn User"
                    val callType = call.argument<String>("callType") ?: "audio"
                    IncomingCallNotificationManager.showIncomingCall(activity, callId, callerName, callType)
                    result.success(true)
                }
                "cancelNativeIncomingCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val reason = call.argument<String>("reason") ?: "remote_terminal"
                    IncomingCallRingtoneManager.stop(reason, if (callId.isNotBlank()) callId else null)
                    if (callId.isNotBlank()) {
                        IncomingCallNotificationManager.cancelIncomingCall(activity, callId, reason)
                        if (reason != "accept") {
                            VorynCallStateManager.transition(activity, callId, VorynCallStateManager.CallState.TERMINAL)
                            VorynActiveCallService.stop(activity, callId, reason)
                            VorynCallEngineManager.destroyEngine(callId)
                        }
                    }
                    IncomingCallActivity.dismiss()
                    result.success(true)
                }
                "stopRingtone" -> {
                    val reason = call.argument<String>("reason") ?: "remote_terminal"
                    val callId = call.argument<String>("callId")
                    IncomingCallRingtoneManager.stop(reason, if (callId.isNullOrBlank()) null else callId)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
