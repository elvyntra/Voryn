package com.voryn.app

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
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
        private val mainHandler = Handler(Looper.getMainLooper())

        fun notifyCallDeclined(callId: String) {
            mainHandler.post {
                MainActivity.activeInstance?.bridge?.methodChannel?.invokeMethod("onCallDeclined", mapOf("callId" to callId))
                VorynCallActivity.activeInstance?.bridge?.methodChannel?.invokeMethod("onCallDeclined", mapOf("callId" to callId))
            }
        }

        fun notifyIncomingCall(callId: String, callerName: String, callType: String) {
            mainHandler.post {
                MainActivity.activeInstance?.bridge?.methodChannel?.invokeMethod(
                    "onIncomingCall",
                    mapOf(
                        "callId" to callId,
                        "callerName" to callerName,
                        "callType" to callType
                    )
                )
            }
        }

        fun notifyActiveCallStateChanged(snapshot: Map<String, Any>?) {
            mainHandler.post {
                MainActivity.activeInstance?.bridge?.methodChannel?.invokeMethod(
                    "onActiveCallStateChanged",
                    snapshot
                )
            }
        }

        fun notifyCallTerminal(callId: String, type: String) {
            mainHandler.post {
                MainActivity.activeInstance?.let { act ->
                    VorynCallStateManager.transition(act, callId, VorynCallStateManager.CallState.TERMINAL)
                    VorynActiveCallService.stop(act, callId, type)
                }
                VorynCallActivity.activeInstance?.let { act ->
                    VorynCallStateManager.transition(act, callId, VorynCallStateManager.CallState.TERMINAL)
                    VorynActiveCallService.stop(act, callId, type)
                }
                VorynCallEngineManager.requestTerminal(callId)
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
                MainActivity.activeInstance?.bridge?.methodChannel?.invokeMethod(
                    "onActiveCallStateChanged",
                    null
                )
            }
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
                        val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                        notifyActiveCallStateChanged(snapshot)
                    }
                    result.success(true)
                }
                "markDartTeardownComplete" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    if (callId.isNotBlank()) {
                        VorynCallEngineManager.markDartTeardownComplete(callId)
                    }
                    result.success(true)
                }
                "minimizeActiveCall" -> {
                    val callId = VorynCallStateManager.getCurrentCallId(activity) ?: ""
                    val state = VorynCallStateManager.getCurrentState(activity)
                    Log.d(TAG, "[CALL_MINIMIZE] state=$state presentation=MINIMIZED callId=$callId")
                    if (callId.isNotBlank()) {
                        VorynCallStateManager.setCallPresentationState(activity, callId, VorynCallStateManager.PresentationState.MINIMIZED)
                        val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                        notifyActiveCallStateChanged(snapshot)
                    }
                    MainActivity.showMainAppDuringCall(activity)
                    activity.moveTaskToBack(true)
                    result.success(true)
                }
                "returnToActiveCall" -> {
                    val callId = call.argument<String>("callId") ?: VorynCallStateManager.getCurrentCallId(activity) ?: ""
                    val currentPres = VorynCallStateManager.getPresentationState(activity)
                    if (currentPres == VorynCallStateManager.PresentationState.FULLSCREEN) {
                        Log.d(TAG, "[CALL_RESTORE] already fullscreen, ignoring duplicate returnToActiveCall callId=$callId")
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    Log.d(TAG, "[CALL_RESTORE] returnToActiveCall callId=$callId")
                    if (callId.isNotBlank()) {
                        VorynCallStateManager.setCallPresentationState(activity, callId, VorynCallStateManager.PresentationState.FULLSCREEN)
                        val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                        notifyActiveCallStateChanged(snapshot)

                        val returnIntent = Intent(activity, VorynCallActivity::class.java).apply {
                            action = "RETURN_TO_CALL"
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                            putExtra("call_id", callId)
                            putExtra("callId", callId)
                        }
                        activity.startActivity(returnIntent)
                    }
                    result.success(true)
                }
                "getActiveCallSnapshot" -> {
                    val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                    result.success(snapshot)
                }
                "acceptIncomingCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val callType = call.argument<String>("callType") ?: "audio"
                    val callerName = call.argument<String>("callerName") ?: "Voryn User"
                    Log.d(TAG, "[FOREGROUND_ACCEPT] acceptIncomingCall callId=$callId callType=$callType")
                    val ok = IncomingCallNotificationManager.setPendingCallAccepting(activity, callId)
                    if (ok) {
                        IncomingCallRingtoneManager.stop("accept", callId)
                        IncomingCallNotificationManager.cancelIncomingCall(activity, callId, "accept")
                        VorynCallHostManager.claimCall(callId, VorynCallHostManager.HostType.LOCKED_CALL)
                        val acceptIntent = Intent(activity, VorynCallActivity::class.java).apply {
                            action = "ACCEPT_CALL"
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            putExtra("action_id", "accept")
                            putExtra("action", "accept")
                            putExtra("call_id", callId)
                            putExtra("callId", callId)
                            putExtra("call_type", callType)
                            putExtra("callType", callType)
                            putExtra("caller_name", callerName)
                        }
                        activity.startActivity(acceptIntent)
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
                    result.success(true)
                    onFinishCall()
                }
                "showNativeIncomingCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val callerName = call.argument<String>("callerName") ?: "Voryn User"
                    val callType = call.argument<String>("callType") ?: "audio"
                    val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    val mode = if (km.isKeyguardLocked) {
                        IncomingCallNotificationManager.IncomingNotificationMode.FULL_SCREEN_CALL_STYLE
                    } else {
                        IncomingCallNotificationManager.IncomingNotificationMode.STANDARD_HEADS_UP
                    }
                    IncomingCallNotificationManager.showIncomingCall(activity, callId, callerName, callType, mode)
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
                            VorynCallEngineManager.requestTerminal(callId)
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
