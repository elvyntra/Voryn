package com.voryn.app

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class VorynCallActivity : FlutterActivity() {
    private var initialCallLaunch: Map<String, String>? = null
    var bridge: VorynCallPlatformBridge? = null
        private set
    private var currentCallId: String? = null

    companion object {
        var activeInstance: VorynCallActivity? = null
            private set

        fun dismiss() {
            activeInstance?.let { activity ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    activity.finishAndRemoveTask()
                } else {
                    activity.finish()
                }
            }
        }
    }

    override fun getDartEntrypointFunctionName(): String = "callMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = this

        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val isLocked = km.isKeyguardLocked
        Log.d("VorynCall", "[CALL_ACTIVITY] onCreate keyguardLocked=$isLocked")

        // Immediately allow CallActivity over the keyguard and turn on the screen
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

        initialCallLaunch = extractCallLaunchData(intent)
        val callId = initialCallLaunch?.get("callId") ?: ""
        val actionId = initialCallLaunch?.get("actionId") ?: ""
        val action = intent?.action ?: ""
        currentCallId = callId.ifBlank { null }

        if (callId.isNotBlank()) {
            val cur = VorynCallStateManager.getCurrentState(this)
            val st = if (cur == VorynCallStateManager.CallState.ACTIVE) cur else VorynCallStateManager.CallState.ACCEPTING
            val originStr = intent?.getStringExtra("call_origin")
                ?: intent?.getStringExtra("origin")
                ?: initialCallLaunch?.get("origin")
            val origin = if (originStr == "IN_APP") {
                VorynCallHostManager.CallPresentationOrigin.IN_APP
            } else if (originStr == "EXTERNAL") {
                VorynCallHostManager.CallPresentationOrigin.EXTERNAL
            } else {
                VorynCallHostManager.getOrigin(callId)
            }
            VorynCallHostManager.claimCall(callId, VorynCallHostManager.HostType.LOCKED_CALL, st, origin)
        }

        if (action == "RETURN_TO_CALL") {
            val targetId = if (callId.isNotBlank()) callId else (currentCallId ?: "")
            val owner = VorynCallHostManager.getActiveHost()
            Log.d("VorynCall", "[ACTIVE_NOTIFICATION] tapped callId=$targetId")
            Log.d("VorynCall", "[ACTIVE_NOTIFICATION] callId=$targetId action=restore owner=$owner result=reused_existing_activity")
            Log.d("VorynCall", "[CALL_ACTIVITY] onNewIntent callId=$targetId decision=reuse_existing_active_call")
            VorynCallStateManager.setCallPresentationState(this, targetId, VorynCallStateManager.PresentationState.FULLSCREEN)
            val snapshot = VorynCallStateManager.getActiveCallSnapshot(this)
            VorynCallPlatformBridge.notifyActiveCallStateChanged(snapshot)
        }

        val acceptTimestamp = intent?.getLongExtra("accept_timestamp", 0L) ?: 0L
        if (acceptTimestamp > 0L) {
            val elapsed = SystemClock.elapsedRealtime() - acceptTimestamp
            Log.d("VorynCall", "[CALL_LATENCY] accept_intent_callactivity callId=$callId elapsed=${elapsed}ms")
        }

        IncomingCallRingtoneManager.stop("accept", if (callId.isNotBlank()) callId else null)
        if (callId.isNotBlank()) {
            IncomingCallNotificationManager.cancelIncomingCall(this, callId, "accept")
        }
        IncomingCallActivity.dismiss()

        Log.d("VorynCall", "[CALL_ACTIVITY] initialCallLaunch callId=$callId actionId=$actionId action=$action")
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val launchData = extractCallLaunchData(intent)
        val callId = launchData?.get("callId") ?: currentCallId ?: ""
        if (callId.isBlank()) return null
        val route = getInitialRoute()
        val engine = VorynCallEngineManager.getOrCreateEngine(this, callId, route)
        VorynCallEngineManager.onActivityAttached(this, callId)
        return engine
    }

    override fun onStart() {
        super.onStart()
        Log.d("VorynCall", "[CALL_ACTIVITY] onStart")
    }

    override fun onResume() {
        super.onResume()
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        Log.d("VorynCall", "[CALL_ACTIVITY] onResume")
        Log.d("VorynCall", "[CALL_ACTIVITY] keyguardLocked=${km.isKeyguardLocked}")
    }

    override fun onDestroy() {
        Log.d("VorynCall", "[CALL_ACTIVITY] onDestroy")
        if (activeInstance == this) {
            activeInstance = null
        }
        val callId = currentCallId
        val state = if (callId != null) VorynCallStateManager.getCurrentState(this) else VorynCallStateManager.CallState.NONE
        if (state == VorynCallStateManager.CallState.TERMINAL || state == VorynCallStateManager.CallState.NONE) {
            if (callId != null) {
                VorynCallHostManager.releaseCall(callId, VorynCallHostManager.HostType.LOCKED_CALL)
            }
            VorynProximityController.releaseAll("call_activity_destroy_terminal")
        } else {
            Log.d("VorynCall", "[CALL_ACTIVITY] onDestroy: call is $state, retaining host ownership, engine, and proximity state")
        }
        super.onDestroy()
        if (callId != null) {
            VorynCallEngineManager.onActivityDetached(this, callId)
        }
    }

    override fun getInitialRoute(): String {
        val launchData = extractCallLaunchData(intent)
        val callId = launchData?.get("callId") ?: ""
        val callType = launchData?.get("callType") ?: "audio"
        val route = if (callType == "video") {
            "/active-video-call/$callId"
        } else {
            "/active-audio-call/$callId"
        }
        Log.d("VorynCall", "[CALL_ROUTE] firstRoute=$route")
        return route
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridgeInstance = VorynCallPlatformBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            getInitialLaunchData = {
                val launch = initialCallLaunch
                initialCallLaunch = null
                Log.d("VorynBoot", "[VORYN_BOOT] CallActivity getInitialCallLaunch returned $launch")
                launch
            },
            onFinishCall = {
                Log.d("VorynCall", "[CALL_ACTIVITY] onFinishCall: releasing ownership and removing task")
                val callId = currentCallId
                if (callId != null) {
                    VorynCallStateManager.transition(this@VorynCallActivity, callId, VorynCallStateManager.CallState.TERMINAL)
                    VorynActiveCallService.stop(this@VorynCallActivity, callId, "terminal")
                    VorynCallEngineManager.requestTerminal(callId)
                    VorynCallHostManager.releaseCall(callId, VorynCallHostManager.HostType.LOCKED_CALL)
                }
                VorynProximityController.releaseAll("finish_call")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    finishAndRemoveTask()
                } else {
                    finish()
                }
            },
            onSetCallPresentationVisible = { enabled ->
                // VorynCallActivity is always setShowWhenLocked(true) by design
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    setShowWhenLocked(true)
                }
            }
        )
        bridge = bridgeInstance
        VorynProximityController.probe(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val launchData = extractCallLaunchData(intent)
        val action = intent.action ?: ""
        val callId = launchData?.get("callId") ?: ""
        Log.d("VorynCall", "[CALL_ACTIVITY] onNewIntent action=$action callId=$callId")

        if (action == "RETURN_TO_CALL" || launchData?.get("actionId") == "return_to_call") {
            val targetId = if (callId.isNotBlank()) callId else (currentCallId ?: "")
            val owner = VorynCallHostManager.getActiveHost()
            val state = VorynCallStateManager.getCurrentState(this)
            val activeId = VorynCallStateManager.getCurrentCallId(this)

            if (targetId.isNotBlank() && (targetId == activeId || activeId == null) &&
                VorynCallHostManager.hasActiveOwner(targetId) &&
                (state == VorynCallStateManager.CallState.ACCEPTING || state == VorynCallStateManager.CallState.ACTIVE)
            ) {
                Log.d("VorynCall", "[ACTIVE_NOTIFICATION] tapped callId=$targetId")
                Log.d("VorynCall", "[ACTIVE_NOTIFICATION] callId=$targetId action=restore owner=$owner result=reused_existing_activity")
                Log.d("VorynCall", "[CALL_ACTIVITY] onNewIntent callId=$targetId decision=reuse_existing_active_call")
                VorynCallStateManager.setCallPresentationState(this, targetId, VorynCallStateManager.PresentationState.FULLSCREEN)
                val snapshot = VorynCallStateManager.getActiveCallSnapshot(this)
                VorynCallPlatformBridge.notifyActiveCallStateChanged(snapshot)
            } else {
                Log.w("VorynCall", "[ACTIVE_NOTIFICATION] restore rejected or state invalid: targetId=$targetId activeId=$activeId state=$state owner=$owner")
            }
            return
        }

        if (callId.isNotBlank() && callId == currentCallId) {
            Log.d("VorynCall", "[CALL_ACTIVITY] duplicate intent for active callId=$callId, ignoring")
            return
        }

        if (currentCallId != null && callId.isNotBlank() && callId != currentCallId) {
            Log.w("VorynCall", "[CALL_ACTIVITY] incoming callId=$callId while active callId=$currentCallId, rejecting to protect session")
            return
        }

        if (launchData != null) {
            bridge?.methodChannel?.invokeMethod("onCallLaunchIntent", launchData)
        }
    }

    private fun extractCallLaunchData(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        val action = intent.action ?: ""
        val actionId = intent.getStringExtra("action_id") ?: intent.getStringExtra("action") ?: "accept"
        val payload = intent.getStringExtra("payload")
            ?: intent.getStringExtra("call_id")
            ?: intent.getStringExtra("callId")
            ?: ""
        val callType = intent.getStringExtra("call_type")
            ?: intent.getStringExtra("callType")
            ?: "audio"
        val origin = intent.getStringExtra("call_origin")
            ?: intent.getStringExtra("origin")
            ?: ""
        val acceptTimestamp = intent.getLongExtra("accept_timestamp", 0L)

        return mapOf(
            "callId" to payload,
            "actionId" to actionId,
            "action" to action,
            "callType" to callType,
            "origin" to origin,
            "acceptTimestamp" to acceptTimestamp.toString()
        )
    }
}
