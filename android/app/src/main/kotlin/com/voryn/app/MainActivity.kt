package com.voryn.app

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val lockScreenChannelName = "com.voryn.app/lock_screen"
    private var methodChannel: MethodChannel? = null
    private var initialCallLaunch: Map<String, String>? = null

    companion object {
        private var activeInstance: MainActivity? = null

        var isAppInForeground: Boolean = false
            private set

        fun notifyCallDeclined(callId: String) {
            activeInstance?.runOnUiThread {
                activeInstance?.methodChannel?.invokeMethod("onCallDeclined", mapOf("callId" to callId))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, lockScreenChannelName)
        methodChannel?.setMethodCallHandler { call, result ->
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            when (call.method) {
                "getElapsedRealtimeMs" -> {
                    result.success(SystemClock.elapsedRealtime())
                }
                "getPendingIncomingCall" -> {
                    val pending = IncomingCallNotificationManager.getPendingIncomingCall(this@MainActivity)
                    result.success(pending)
                }
                "clearPendingIncomingCall" -> {
                    val callId = call.argument<String>("callId")
                    IncomingCallNotificationManager.clearPendingIncomingCall(this@MainActivity, callId)
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
                            data = Uri.parse("package:$packageName")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "isKeyguardLocked" -> {
                    result.success(km.isKeyguardLocked)
                }
                "getInitialCallLaunch" -> {
                    val launch = initialCallLaunch
                    initialCallLaunch = null
                    Log.d("VorynBoot", "[VORYN_BOOT] getInitialCallLaunch returned $launch")
                    result.success(launch)
                }
                "setCallPresentationVisible" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    applyShowWhenLocked(enabled)
                    result.success(true)
                }
                "moveCallTaskBehindKeyguard" -> {
                    applyShowWhenLocked(false)
                    if (km.isKeyguardLocked) {
                        moveTaskToBack(true)
                    }
                    result.success(true)
                }
                "showNativeIncomingCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val callerName = call.argument<String>("callerName") ?: "Voryn User"
                    val callType = call.argument<String>("callType") ?: "audio"
                    IncomingCallNotificationManager.showIncomingCall(this@MainActivity, callId, callerName, callType)
                    result.success(true)
                }
                "cancelNativeIncomingCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    val reason = call.argument<String>("reason") ?: "remote_terminal"
                    IncomingCallRingtoneManager.stop(reason, if (callId.isNotBlank()) callId else null)
                    if (callId.isNotBlank()) {
                        IncomingCallNotificationManager.cancelIncomingCall(this@MainActivity, callId, reason)
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = this
        initialCallLaunch = extractCallLaunchData(intent)
        val action = intent?.action ?: ""
        val callId = initialCallLaunch?.get("callId") ?: ""
        val actionId = initialCallLaunch?.get("actionId") ?: ""
        val source = if (actionId == "accept") "accepted_call" else "launcher"
        Log.d("VorynBoot", "[BOOT] MainActivity onCreate source=$source action=$action actionId=$actionId callId=$callId")

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

        updateLockScreenCallPresentation(intent)
        IncomingCallNotificationManager.ensureChannel(this)
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
    }

    override fun onDestroy() {
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

        updateLockScreenCallPresentation(intent)
        if (launchData != null) {
            methodChannel?.invokeMethod("onCallLaunchIntent", launchData)
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

        if (payload.isBlank()) {
            val dataUri = intent.data
            if (dataUri != null) {
                val lastSeg = dataUri.lastPathSegment
                if (!lastSeg.isNullOrBlank() && (dataUri.toString().contains("call") || dataUri.scheme == "voryn")) {
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

    private fun updateLockScreenCallPresentation(intent: Intent?) {
        val actionId = intent?.getStringExtra("action_id") ?: intent?.getStringExtra("action")
        val isAcceptedCall = actionId == "accept" || intent?.action == "ACCEPT_CALL"
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

        if (isAcceptedCall) {
            applyShowWhenLocked(true)
        } else {
            applyShowWhenLocked(false)
            if (km.isKeyguardLocked && actionId == "decline") {
                moveTaskToBack(true)
            }
        }
    }
}
