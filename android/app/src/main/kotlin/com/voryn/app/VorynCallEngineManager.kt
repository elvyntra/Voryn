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

    @Synchronized
    fun getOrCreateEngine(context: Context, callId: String, initialRoute: String): FlutterEngine {
        val existing = cachedEngine
        if (existing != null && cachedCallId == callId) {
            Log.d(TAG, "[CALL_ENGINE] reattach activity callId=$callId")
            return existing
        }

        if (existing != null) {
            Log.d(TAG, "[CALL_ENGINE] destroy previous engine callId=$cachedCallId before creating callId=$callId")
            destroyEngine(cachedCallId ?: "")
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
        return engine
    }

    @Synchronized
    fun getEngine(callId: String): FlutterEngine? {
        return if (cachedCallId == callId) cachedEngine else null
    }

    @Synchronized
    fun destroyEngine(callId: String) {
        if (cachedCallId == callId || callId.isBlank()) {
            Log.d(TAG, "[CALL_ENGINE] destroy reason=terminal callId=$callId")
            try {
                cachedEngine?.destroy()
            } catch (e: Exception) {
                Log.w(TAG, "[CALL_ENGINE] error destroying engine: ${e.message}")
            }
            cachedEngine = null
            cachedCallId = null
        }
    }
}
