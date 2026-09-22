package com.voryn.app

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    var bridge: VorynCallPlatformBridge? = null
        private set
    private var initialCallLaunch: Map<String, String>? = null

    companion object {
        var activeInstance: MainActivity? = null
            private set

        var isAppInForeground: Boolean = false
            private set

        fun notifyCallDeclined(callId: String) {
            VorynCallPlatformBridge.notifyCallDeclined(callId)
        }

        fun notifyIncomingCall(callId: String, callerName: String, callType: String) {
            VorynCallPlatformBridge.notifyIncomingCall(callId, callerName, callType)
        }

        fun notifyCallTerminal(callId: String, type: String) {
            VorynCallPlatformBridge.notifyCallTerminal(callId, type)
        }

        var messagesChannel: MethodChannel? = null
            private set
        var pendingThreadId: String? = null
            private set

        private val mainHandler = Handler(Looper.getMainLooper())

        fun notifyIncomingMessage(threadId: String, messageId: String, senderUid: String, body: String) {
            mainHandler.post {
                try {
                    messagesChannel?.invokeMethod(
                        "onIncomingMessage",
                        mapOf(
                            "threadId" to threadId,
                            "messageId" to messageId,
                            "senderUid" to senderUid,
                            "body" to body
                        )
                    )
                } catch (e: Exception) {
                    Log.e("VorynMsg", "[MESSAGE_FCM] notifyIncomingMessage error: ${e.message}")
                }
            }
        }

        fun showMainAppDuringCall(context: Context) {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (km.isKeyguardLocked) {
                Log.d("VorynCall", "[CALL_MINIMIZE] keyguard is locked, not revealing main app")
                return
            }

            val isReused = activeInstance != null
            Log.d("VorynCall", "[CALL_MINIMIZE] showMainApp")
            Log.d("VorynCall", "[CALL_MINIMIZE] existingMainActivity=$isReused")

            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            }
            context.startActivity(intent)
            Log.d("VorynCall", "[CALL_MINIMIZE] mainTaskBroughtToFront")
        }
    }

    private var hasActiveCallPresentation: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridgeInstance = VorynCallPlatformBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            getInitialLaunchData = {
                val launch = initialCallLaunch
                initialCallLaunch = null
                Log.d("VorynBoot", "[VORYN_BOOT] MainActivity getInitialCallLaunch returned $launch")
                launch
            },
            onFinishCall = {
                hasActiveCallPresentation = false
                applyShowWhenLocked(false)
                val callId = VorynCallStateManager.getCurrentCallId(this@MainActivity)
                if (callId != null) {
                    VorynCallStateManager.transition(this@MainActivity, callId, VorynCallStateManager.CallState.TERMINAL)
                    VorynActiveCallService.stop(this@MainActivity, callId, "finish_call")
                }
                val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                if (km.isKeyguardLocked) {
                    moveTaskToBack(true)
                }
            },
            onSetCallPresentationVisible = { enabled ->
                hasActiveCallPresentation = enabled
                applyShowWhenLocked(enabled)
            }
        )
        bridge = bridgeInstance
        VorynProximityController.probe(this)

        val msgChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.voryn.app/messages")
        msgChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "syncBackgroundAuth" -> {
                    val uid = call.argument<String>("userUid") ?: ""
                    val access = call.argument<String>("accessToken") ?: ""
                    val refresh = call.argument<String>("refreshToken") ?: ""
                    val expiresAt = call.argument<Number>("expiresAtMs")?.toLong() ?: 0L
                    val url = call.argument<String>("supabaseUrl") ?: ""
                    val key = call.argument<String>("anonKey") ?: ""
                    VorynBackgroundAuthStore.saveSession(this, uid, access, refresh, expiresAt, url, key)
                    result.success(true)
                }
                "clearBackgroundAuth" -> {
                    VorynBackgroundAuthStore.clear(this)
                    VorynMessageNotificationManager.cancelAllMessageNotifications(this)
                    result.success(true)
                }
                "getPendingMessageThread" -> {
                    val thread = pendingThreadId
                    pendingThreadId = null
                    result.success(thread)
                }
                "dismissMessageNotification" -> {
                    val threadId = call.argument<String>("threadId") ?: ""
                    if (threadId.isNotBlank()) {
                        VorynMessageNotificationManager.dismissThreadNotification(this, threadId)
                    }
                    result.success(true)
                }
                "removeMessageFromNotification" -> {
                    val threadId = call.argument<String>("threadId") ?: ""
                    val messageId = call.argument<String>("messageId") ?: ""
                    if (threadId.isNotBlank() && messageId.isNotBlank()) {
                        VorynMessageNotificationManager.removeMessageFromNotification(this, threadId, messageId)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        messagesChannel = msgChannel
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = this
        initialCallLaunch = extractCallLaunchData(intent)
        val callId = initialCallLaunch?.get("callId") ?: ""
        if (callId.isNotBlank() && VorynCallHostManager.isCallOwnedByLockedCall(callId)) {
            Log.d("VorynCall", "[HOST_OWNERSHIP] MainActivity suppressing initialCallLaunch for callId=$callId (owned by LOCKED_CALL)")
            initialCallLaunch = null
        }
        val action = intent?.action ?: ""
        val actionId = initialCallLaunch?.get("actionId") ?: ""
        val source = intent?.getStringExtra("source") ?: ""
        Log.d("VorynBoot", "[BOOT] MainActivity onCreate source=$source action=$action actionId=$actionId callId=$callId")
        Log.d("VorynCall", "[LOCKSCREEN] MainActivity started reason=$action")

        if (actionId == "accept" || action == "ACCEPT_CALL") {
            val acceptTimestamp = intent?.getLongExtra("accept_timestamp", 0L) ?: 0L
            if (acceptTimestamp > 0L) {
                val elapsed = SystemClock.elapsedRealtime() - acceptTimestamp
                Log.d("VorynCall", "[CALL_LATENCY] accept_intent_mainactivity callId=$callId elapsed=${elapsed}ms")
            }
            IncomingCallRingtoneManager.stop("accept", if (callId.isNotBlank()) callId else null)
            if (callId.isNotBlank()) {
                IncomingCallNotificationManager.cancelIncomingCall(this, callId, "accept")
            }
            IncomingCallActivity.dismiss()
        }

        applyShowWhenLocked(false)
        IncomingCallNotificationManager.ensureChannel(this)
        VorynMessageNotificationManager.createNotificationChannel(this)
        checkMessageDeepLink(intent)
    }

    override fun onResume() {
        super.onResume()
        Log.d("VorynMsg", "[MAIN_ACTIVITY] onResume")
        isAppInForeground = true
        if (!hasActiveCallPresentation) {
            applyShowWhenLocked(false)
        }

        val callState = VorynCallStateManager.getCurrentState(this)
        val activeCallId = VorynCallStateManager.getCurrentCallId(this)
        val presentation = VorynCallStateManager.getPresentationState(this)

        if ((callState == VorynCallStateManager.CallState.ACTIVE || callState == VorynCallStateManager.CallState.ACCEPTING) &&
            !activeCallId.isNullOrBlank() &&
            (VorynCallHostManager.isCallOwnedByLockedCall(activeCallId) || VorynCallActivity.activeInstance != null)
        ) {
            if (presentation == VorynCallStateManager.PresentationState.FULLSCREEN) {
                Log.d("VorynCall", "[CALL_RECOVERY] MainActivity state=$callState presentation=$presentation callId=$activeCallId -> foreground existing call host")
                val returnIntent = Intent(this, VorynCallActivity::class.java).apply {
                    action = "RETURN_TO_CALL"
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    putExtra("call_id", activeCallId)
                    putExtra("callId", activeCallId)
                }
                startActivity(returnIntent)
                return
            } else {
                Log.d("VorynCall", "[CALL_RECOVERY] MainActivity state=$callState presentation=$presentation callId=$activeCallId -> staying in MainActivity (minimized)")
                val snapshot = VorynCallStateManager.getActiveCallSnapshot(this)
                VorynCallPlatformBridge.notifyActiveCallStateChanged(snapshot)
            }
        }

        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!km.isKeyguardLocked) {
            val pending = IncomingCallNotificationManager.getPendingIncomingCall(this)
            val pendingState = pending?.get("state") as? String
            val pendingCallId = pending?.get("callId") as? String
            val callerName = pending?.get("callerName") as? String ?: "Voryn User"
            val callType = pending?.get("callType") as? String ?: "audio"

            val owner = VorynCallHostManager.getActiveHost()
            val hasActiveOwner = !pendingCallId.isNullOrBlank() && VorynCallHostManager.hasActiveOwner(pendingCallId)

            if (pendingCallId.isNullOrBlank() || pendingState != "RINGING") {
                if (!pendingCallId.isNullOrBlank()) {
                    Log.d(
                        "VorynCall",
                        "[INCOMING_RECOVERY] callId=$pendingCallId pendingState=$pendingState activeCallId=$activeCallId owner=$owner decision=suppress reason=not_ringing"
                    )
                }
            } else if (hasActiveOwner || pendingCallId == activeCallId || callState == VorynCallStateManager.CallState.ACTIVE || callState == VorynCallStateManager.CallState.ACCEPTING) {
                Log.d(
                    "VorynCall",
                    "[INCOMING_RECOVERY] callId=$pendingCallId pendingState=$pendingState activeCallId=$activeCallId owner=$owner decision=suppress reason=already_active"
                )
            } else {
                Log.d(
                    "VorynCall",
                    "[INCOMING_RECOVERY] callId=$pendingCallId pendingState=$pendingState activeCallId=$activeCallId owner=$owner decision=show reason=valid_ringing"
                )
                Log.d("VorynCall", "[INCOMING_HANDOFF] handing off pending callId=$pendingCallId to foreground Flutter")
                VorynCallPlatformBridge.notifyIncomingCall(pendingCallId, callerName, callType)
            }
        }
    }

    override fun onPause() {
        super.onPause()
        Log.d("VorynMsg", "[MAIN_ACTIVITY] onPause")
        isAppInForeground = false
        if (!hasActiveCallPresentation) {
            applyShowWhenLocked(false)
        }
    }

    override fun onStop() {
        super.onStop()
        Log.d("VorynMsg", "[MAIN_ACTIVITY] onStop")
    }

    override fun onDestroy() {
        Log.d("VorynMsg", "[MAIN_ACTIVITY] onDestroy")
        hasActiveCallPresentation = false
        applyShowWhenLocked(false)
        VorynProximityController.releaseAll("app_destroy")
        if (activeInstance == this) {
            activeInstance = null
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val launchData = extractCallLaunchData(intent)
        val action = intent.action ?: ""
        val callId = launchData?.get("callId") ?: ""
        val actionId = launchData?.get("actionId") ?: ""
        Log.d("VorynBoot", "[BOOT] onNewIntent action=$action actionId=$actionId callId=$callId")
        Log.d("VorynCall", "[LOCKSCREEN] MainActivity started reason=$action")

        if (callId.isNotBlank() && VorynCallHostManager.isCallOwnedByLockedCall(callId)) {
            Log.d("VorynCall", "[HOST_OWNERSHIP] MainActivity suppressing onNewIntent for callId=$callId (owned by LOCKED_CALL)")
            return
        }

        if (actionId == "accept" || action == "ACCEPT_CALL") {
            val acceptTimestamp = intent.getLongExtra("accept_timestamp", 0L)
            if (acceptTimestamp > 0L) {
                val elapsed = SystemClock.elapsedRealtime() - acceptTimestamp
                Log.d("VorynCall", "[CALL_LATENCY] accept_intent_mainactivity callId=$callId elapsed=${elapsed}ms")
            }
            IncomingCallRingtoneManager.stop("accept", if (callId.isNotBlank()) callId else null)
            if (callId.isNotBlank()) {
                IncomingCallNotificationManager.cancelIncomingCall(this, callId, "accept")
            }
            IncomingCallActivity.dismiss()
        }

        if (!hasActiveCallPresentation) {
            applyShowWhenLocked(false)
        }
        if (launchData != null) {
            bridge?.methodChannel?.invokeMethod("onCallLaunchIntent", launchData)
        }
        checkMessageDeepLink(intent)
    }

    private fun checkMessageDeepLink(intent: Intent?) {
        val dataUri = intent?.data ?: return
        if (dataUri.scheme == "voryn" && dataUri.host == "messages") {
            val pathSegments = dataUri.pathSegments
            val threadId = if (pathSegments.isNotEmpty()) pathSegments.last() else null
            Log.d("VorynMsg", "[MESSAGE_NAV] source=intent action=${intent.action} threadId=$threadId")
            if (!threadId.isNullOrBlank() && threadId != "inbox") {
                Log.d("VorynMsg", "[DEEP_LINK] message thread deep link: $threadId")
                VorynMessageNotificationManager.dismissThreadNotification(this, threadId)
                pendingThreadId = threadId
                mainHandler.post {
                    messagesChannel?.invokeMethod("onOpenThread", mapOf("threadId" to threadId))
                }
            } else {
                Log.d("VorynMsg", "[DEEP_LINK] message inbox deep link")
                mainHandler.post {
                    messagesChannel?.invokeMethod("onOpenInbox", emptyMap<String, Any>())
                }
            }
        }
    }

    private fun extractCallLaunchData(intent: Intent?): Map<String, String>? {
        if (intent == null) return null
        val action = intent.action ?: ""
        val actionId = intent.getStringExtra("action_id") ?: intent.getStringExtra("action") ?: ""
        var payload = intent.getStringExtra("payload")
            ?: intent.getStringExtra("call_id")
            ?: intent.getStringExtra("callId")
            ?: ""

        if (intent.data?.host == "messages") {
            return null
        }

        if (payload.isBlank()) {
            val dataUri = intent.data
            if (dataUri != null) {
                val lastSeg = dataUri.lastPathSegment
                if (!lastSeg.isNullOrBlank() && (dataUri.toString().contains("call") || (dataUri.scheme == "voryn" && dataUri.host != "messages"))) {
                    payload = lastSeg
                }
            }
        }

        val callType = intent.getStringExtra("call_type")
            ?: intent.getStringExtra("callType")
            ?: ""

        val acceptTimestamp = intent.getLongExtra("accept_timestamp", 0L)

        val isCallLaunch = payload.isNotBlank() || actionId == "accept" || actionId == "decline" ||
            action == "ACCEPT_CALL" || action == "SELECT_NOTIFICATION" || action == "SELECT_FOREGROUND_NOTIFICATION_ACTION"

        if (!isCallLaunch) return null

        return mapOf(
            "callId" to payload,
            "actionId" to actionId,
            "action" to action,
            "callType" to callType,
            "acceptTimestamp" to acceptTimestamp.toString()
        )
    }

    private fun applyShowWhenLocked(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
        } else {
            @Suppress("DEPRECATION")
            if (enabled) {
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                )
            } else {
                window.clearFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                )
            }
        }
    }
}
