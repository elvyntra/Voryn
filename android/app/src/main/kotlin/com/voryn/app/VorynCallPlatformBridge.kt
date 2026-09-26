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

        private fun getTargetBridge(): VorynCallPlatformBridge? {
            return VorynCallActivity.activeInstance?.bridge ?: MainActivity.activeInstance?.bridge
        }

        fun notifyCallDeclined(callId: String) {
            mainHandler.post {
                getTargetBridge()?.methodChannel?.invokeMethod("onCallDeclined", mapOf("callId" to callId))
            }
        }

        fun notifyIncomingCall(callId: String, callerName: String, callType: String) {
            mainHandler.post {
                getTargetBridge()?.methodChannel?.invokeMethod(
                    "onIncomingCall",
                    mapOf(
                        "callId" to callId,
                        "callerName" to callerName,
                        "callType" to callType
                    )
                )
            }
        }

        fun notifyCallWaiting(callId: String, callerName: String, callType: String) {
            mainHandler.post {
                val bridge = getTargetBridge()
                Log.d(TAG, "[CALL_WAITING] dispatch to bridge: $bridge callId=$callId")
                bridge?.methodChannel?.invokeMethod(
                    "onCallWaiting",
                    mapOf(
                        "callId" to callId,
                        "callerName" to callerName,
                        "callType" to callType
                    )
                )
            }
        }

        fun notifyCallWaitingCancelled(callId: String) {
            mainHandler.post {
                val bridge = getTargetBridge()
                Log.d(TAG, "[CALL_WAITING] dispatch cancellation to bridge: $bridge callId=$callId")
                bridge?.methodChannel?.invokeMethod(
                    "onCallWaitingCancelled",
                    mapOf("callId" to callId)
                )
            }
        }

        fun notifyActiveCallStateChanged(snapshot: Map<String, Any>?) {
            mainHandler.post {
                getTargetBridge()?.methodChannel?.invokeMethod(
                    "onActiveCallStateChanged",
                    snapshot
                )
            }
        }

        fun notifyCallTerminal(callId: String, type: String) {
            mainHandler.post {
                val actContext = VorynCallActivity.activeInstance ?: MainActivity.activeInstance
                val multi = actContext?.let { VorynCallStateManager.getMultiCallState(it) }

                MainActivity.activeInstance?.let { act ->
                    VorynCallStateManager.transition(act, callId, VorynCallStateManager.CallState.TERMINAL)
                    if (multi == null || multi.heldCallId == null || multi.heldCallId == callId) {
                        VorynActiveCallService.stop(act, callId, type)
                    }
                }
                VorynCallActivity.activeInstance?.let { act ->
                    VorynCallStateManager.transition(act, callId, VorynCallStateManager.CallState.TERMINAL)
                    if (multi == null || multi.heldCallId == null || multi.heldCallId == callId) {
                        VorynActiveCallService.stop(act, callId, type)
                    }
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
                if (multi == null || multi.heldCallId == null || multi.heldCallId == callId) {
                    MainActivity.activeInstance?.bridge?.methodChannel?.invokeMethod(
                        "onActiveCallStateChanged",
                        null
                    )
                }
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
                        VorynCallHostManager.hasActiveOwner(callId) ||
                            VorynCallHostManager.isCallOwnedByLockedCall(callId) ||
                            (VorynCallHostManager.isAnyCallOwnedByLockedCall() && VorynCallHostManager.getActiveCallId() != callId) ||
                            (VorynCallStateManager.getCurrentCallId(activity) == callId &&
                                (VorynCallStateManager.getCurrentState(activity) == VorynCallStateManager.CallState.ACTIVE ||
                                 VorynCallStateManager.getCurrentState(activity) == VorynCallStateManager.CallState.ACCEPTING))
                    } else {
                        false
                    }
                    if (isOwned) {
                        Log.d(TAG, "[HOST_OWNERSHIP] callId=$callId is owned by active call, suppressing MainActivity action")
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
                    val originArg = call.argument<String>("origin")
                    if (callId.isNotBlank()) {
                        val host = if (activity is VorynCallActivity) "LOCKED_CALL" else "MAIN"
                        val nativeOrigin = VorynCallHostManager.getOrigin(callId)
                        val origin = when {
                            originArg == "IN_APP" -> VorynCallHostManager.CallPresentationOrigin.IN_APP
                            originArg == "EXTERNAL" -> VorynCallHostManager.CallPresentationOrigin.EXTERNAL
                            activity is MainActivity -> {
                                if (VorynCallHostManager.getActiveCallId() == callId && nativeOrigin == VorynCallHostManager.CallPresentationOrigin.EXTERNAL) {
                                    nativeOrigin
                                } else {
                                    VorynCallHostManager.CallPresentationOrigin.IN_APP
                                }
                            }
                            else -> nativeOrigin
                        }
                        VorynCallHostManager.setOrigin(callId, origin)
                        VorynCallStateManager.markCallActive(activity, callId, callerName, callType, host, origin)
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
                    val owner = VorynCallHostManager.getActiveHost()
                    val origin = VorynCallStateManager.getCallOrigin(activity)
                    Log.d(TAG, "[CALL_MINIMIZE] state=$state presentation=MINIMIZED callId=$callId owner=$owner origin=$origin")
                    if (callId.isNotBlank()) {
                        VorynCallStateManager.setCallPresentationState(activity, callId, VorynCallStateManager.PresentationState.MINIMIZED)
                        val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                        notifyActiveCallStateChanged(snapshot)
                        val callerName = VorynCallStateManager.getCallerName(activity)
                        val callType = VorynCallStateManager.getCallType(activity)
                        VorynActiveCallService.start(activity, callId, callerName, callType)
                    }
                    when {
                        owner == VorynCallHostManager.HostType.MAIN && origin == VorynCallHostManager.CallPresentationOrigin.IN_APP -> {
                            Log.d(TAG, "[CALL_PRESENTATION] callId=$callId owner=MAIN origin=IN_APP action=minimize target=VORYN_SHELL")
                            // In-app inside MainActivity: do NOT move task to back
                        }
                        owner == VorynCallHostManager.HostType.LOCKED_CALL && origin == VorynCallHostManager.CallPresentationOrigin.EXTERNAL -> {
                            Log.d(TAG, "[CALL_PRESENTATION] callId=$callId owner=LOCKED_CALL origin=EXTERNAL action=minimize target=SYSTEM")
                            activity.moveTaskToBack(true)
                            Log.d(TAG, "[CALL_ACTIVITY] moveTaskToBack result=true")
                        }
                        owner == VorynCallHostManager.HostType.LOCKED_CALL && origin == VorynCallHostManager.CallPresentationOrigin.IN_APP -> {
                            Log.d(TAG, "[CALL_PRESENTATION] callId=$callId owner=LOCKED_CALL origin=IN_APP action=minimize target=VORYN_SHELL")
                            MainActivity.showMainAppDuringCall(activity)
                            activity.moveTaskToBack(true)
                            Log.d(TAG, "[CALL_ACTIVITY] moveTaskToBack result=true")
                        }
                        else -> {
                            Log.w(TAG, "[CALL_PRESENTATION] unexpected combination: callId=$callId owner=$owner origin=$origin action=minimize")
                            if (activity is VorynCallActivity) {
                                activity.moveTaskToBack(true)
                                Log.d(TAG, "[CALL_ACTIVITY] moveTaskToBack result=true")
                            }
                        }
                    }
                    result.success(true)
                }
                "returnToActiveCall" -> {
                    val callId = call.argument<String>("callId") ?: VorynCallStateManager.getCurrentCallId(activity) ?: ""
                    val owner = VorynCallHostManager.getActiveHost()
                    Log.d(TAG, "[MINI_CALL] callId=$callId owner=$owner action=restore_existing_call_activity")
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
                    val originArg = call.argument<String>("origin")
                    val existingOrigin = VorynCallHostManager.getOrigin(callId)
                    val origin = when {
                        VorynCallHostManager.getActiveCallId() == callId && existingOrigin == VorynCallHostManager.CallPresentationOrigin.EXTERNAL -> existingOrigin
                        originArg == "IN_APP" -> VorynCallHostManager.CallPresentationOrigin.IN_APP
                        originArg == "EXTERNAL" -> VorynCallHostManager.CallPresentationOrigin.EXTERNAL
                        activity is MainActivity -> VorynCallHostManager.CallPresentationOrigin.IN_APP
                        else -> VorynCallHostManager.CallPresentationOrigin.EXTERNAL
                    }
                    Log.d(TAG, "[FOREGROUND_ACCEPT] acceptIncomingCall callId=$callId callType=$callType origin=$origin")
                    val ok = IncomingCallNotificationManager.setPendingCallAccepting(activity, callId)
                    if (ok) {
                        IncomingCallRingtoneManager.stop("accept", callId)
                        IncomingCallNotificationManager.cancelIncomingCall(activity, callId, "accept")
                        VorynCallHostManager.claimCall(callId, VorynCallHostManager.HostType.LOCKED_CALL, VorynCallStateManager.CallState.ACCEPTING, origin)
                        VorynActiveCallService.start(activity, callId, callerName, callType)
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
                            putExtra("callerName", callerName)
                            putExtra("call_origin", origin.name)
                            putExtra("origin", origin.name)
                        }
                        activity.startActivity(acceptIntent)
                    } else {
                        Log.d(TAG, "[FOREGROUND_ACCEPT] accept ignored (already accepted or invalid) callId=$callId")
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
                "markCallHeldAndAccepted" -> {
                    val heldCallId = call.argument<String>("heldCallId") ?: ""
                    val activeCallId = call.argument<String>("activeCallId") ?: ""
                    val callerName = call.argument<String>("callerName") ?: "Voryn User"
                    val callType = call.argument<String>("callType") ?: "audio"
                    if (heldCallId.isNotBlank() && activeCallId.isNotBlank()) {
                        VorynCallStateManager.holdActiveAndAcceptWaiting(activity, heldCallId, activeCallId, callerName, callType)
                        IncomingCallNotificationManager.cancelWaitingCallNotification(activity, activeCallId)
                        VorynActiveCallService.start(activity, activeCallId, callerName, callType)
                        val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                        notifyActiveCallStateChanged(snapshot)
                    }
                    result.success(true)
                }
                "markCallSwapped" -> {
                    val activeCallId = call.argument<String>("activeCallId") ?: ""
                    val heldCallId = call.argument<String>("heldCallId") ?: ""
                    if (activeCallId.isNotBlank() && heldCallId.isNotBlank()) {
                        VorynCallStateManager.switchCalls(activity, activeCallId, heldCallId)
                        val callerName = VorynCallStateManager.getCallerName(activity)
                        val callType = VorynCallStateManager.getCallType(activity)
                        VorynActiveCallService.start(activity, activeCallId, callerName, callType)
                        val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                        notifyActiveCallStateChanged(snapshot)
                    }
                    result.success(true)
                }
                "resumeHeldCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    if (callId.isNotBlank()) {
                        VorynCallStateManager.resumeHeldCall(activity, callId)
                        val callerName = VorynCallStateManager.getCallerName(activity)
                        val callType = VorynCallStateManager.getCallType(activity)
                        VorynActiveCallService.start(activity, callId, callerName, callType)
                        val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                        notifyActiveCallStateChanged(snapshot)
                    }
                    result.success(true)
                }
                "clearHeldCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    if (callId.isNotBlank()) {
                        VorynCallStateManager.clearHeldCall(activity, callId)
                        val snapshot = VorynCallStateManager.getActiveCallSnapshot(activity)
                        notifyActiveCallStateChanged(snapshot)
                    }
                    result.success(true)
                }
                "clearWaitingCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    if (callId.isNotBlank()) {
                        VorynCallStateManager.clearWaitingCall(activity, callId)
                        IncomingCallNotificationManager.cancelWaitingCallNotification(activity, callId)
                    }
                    result.success(true)
                }
                "getMultiCallState" -> {
                    val s = VorynCallStateManager.getMultiCallState(activity)
                    result.success(
                        mapOf(
                            "activeCallId" to (s.activeCallId ?: ""),
                            "heldCallId" to (s.heldCallId ?: ""),
                            "waitingCallId" to (s.waitingCallId ?: ""),
                            "activeCallState" to s.activeCallState.name
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}
