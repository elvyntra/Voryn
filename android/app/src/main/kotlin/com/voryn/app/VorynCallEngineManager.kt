package com.voryn.app

import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

object VorynCallEngineManager {
    private const val TAG = "VorynCall"

    @Volatile
    private var cachedEngine: FlutterEngine? = null

    @Volatile
    private var cachedCallId: String? = null

    @Volatile
    private var attachedActivity: VorynCallActivity? = null

    @Volatile
    private var terminalRequested: Boolean = false

    @Volatile
    private var dartTeardownComplete: Boolean = false

    @Synchronized
    fun getOrCreateEngine(context: Context, callId: String, initialRoute: String): FlutterEngine {
        val existing = cachedEngine
        if (existing != null && cachedCallId == callId) {
            return existing
        }

        if (existing != null) {
            Log.d(TAG, "[CALL_ENGINE] destroy previous engine callId=$cachedCallId before creating callId=$callId")
            forceDestroyEngine()
        }

        Log.d(TAG, "[CALL_ENGINE] create callId=$callId")
        val engine = FlutterEngine(context.applicationContext)
        if (initialRoute.isNotBlank()) {
            engine.navigationChannel.setInitialRoute(initialRoute)
        }

        val appBundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        val entrypoint = DartExecutor.DartEntrypoint(appBundlePath, "callMain")
        engine.dartExecutor.executeDartEntrypoint(entrypoint)

        cachedEngine = engine
        cachedCallId = callId
        terminalRequested = false
        dartTeardownComplete = false
        return engine
    }

    @Synchronized
    fun getEngine(callId: String): FlutterEngine? {
        return if (cachedCallId == callId) cachedEngine else null
    }

    @Synchronized
    fun onActivityAttached(activity: VorynCallActivity, callId: String) {
        val actId = Integer.toHexString(activity.hashCode())
        Log.d(TAG, "[CALL_ENGINE] attach activity=$actId callId=$callId")
        attachedActivity = activity
    }

    @Synchronized
    fun onActivityDetached(activity: VorynCallActivity, callId: String) {
        val actId = Integer.toHexString(activity.hashCode())
        Log.d(TAG, "[CALL_ENGINE] activity detached activity=$actId callId=$callId")
        if (attachedActivity == activity) {
            attachedActivity = null
        }
        checkSafeDestroy(callId)
    }

    @Synchronized
    fun requestTerminal(callId: String) {
        Log.d(TAG, "[CALL_ENGINE] terminal requested callId=$callId")
        terminalRequested = true
        checkSafeDestroy(callId)
    }

    @Synchronized
    fun markDartTeardownComplete(callId: String) {
        Log.d(TAG, "[CALL_ENGINE] dart teardown complete callId=$callId")
        dartTeardownComplete = true
        checkSafeDestroy(callId)
    }

    @Synchronized
    private fun checkSafeDestroy(callId: String) {
        if (terminalRequested && dartTeardownComplete && attachedActivity == null) {
            Log.d(TAG, "[CALL_ENGINE] safe destroy callId=$callId")
            forceDestroyEngine()
        } else {
            Log.d(
                TAG,
                "[CALL_ENGINE] destroy pending: terminalRequested=$terminalRequested " +
                    "dartTeardownComplete=$dartTeardownComplete attachedActivity=${attachedActivity != null}"
            )
        }
    }

    @Synchronized
    fun forceDestroyEngine() {
        try {
            cachedEngine?.destroy()
        } catch (e: Exception) {
            Log.w(TAG, "[CALL_ENGINE] error destroying engine: ${e.message}")
        } finally {
            cachedEngine = null
            cachedCallId = null
            terminalRequested = false
            dartTeardownComplete = false
            attachedActivity = null
        }
    }
}
