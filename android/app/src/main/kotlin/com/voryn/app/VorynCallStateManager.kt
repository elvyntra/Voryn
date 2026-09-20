package com.voryn.app

import android.content.Context
import android.util.Log

object VorynCallStateManager {
    private const val TAG = "VorynCall"
    private const val PREFS_NAME = "voryn_call_state_v1"

    private const val KEY_CALL_ID = "call_id"
    private const val KEY_CALL_STATE = "call_state"
    private const val KEY_CALL_TYPE = "call_type"
    private const val KEY_CALLER_NAME = "caller_name"
    private const val KEY_RECEIVED_AT = "received_at"
    private const val KEY_STARTED_AT = "started_at"
    private const val KEY_HOST = "host"

    enum class CallState {
        NONE,
        RINGING,
        ACCEPTING,
        ACTIVE,
        ENDING,
        TERMINAL
    }

    @Volatile
    private var inMemoryState: CallState = CallState.NONE

    @Volatile
    private var inMemoryCallId: String? = null

    @Synchronized
    fun getCurrentState(context: Context): CallState {
        if (inMemoryState != CallState.NONE) return inMemoryState
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val stateStr = prefs.getString(KEY_CALL_STATE, null) ?: return CallState.NONE
        inMemoryState = try {
            CallState.valueOf(stateStr)
        } catch (_: Exception) {
            CallState.NONE
        }
        return inMemoryState
    }

    @Synchronized
    fun getCurrentCallId(context: Context): String? {
        if (!inMemoryCallId.isNullOrBlank()) return inMemoryCallId
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        inMemoryCallId = prefs.getString(KEY_CALL_ID, null)
        return inMemoryCallId
    }

    @Synchronized
    fun recordRingingCall(
        context: Context,
        callId: String,
        callType: String,
        callerName: String
    ) {
        val current = getCurrentState(context)
        val activeId = getCurrentCallId(context)
        if (activeId == callId && (current == CallState.ACCEPTING || current == CallState.ACTIVE)) {
            Log.d(TAG, "[CALL_STATE] duplicate incoming ignored callId=$callId state=$current")
            return
        }

        inMemoryState = CallState.RINGING
        inMemoryCallId = callId

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_CALL_ID, callId)
            .putString(KEY_CALL_STATE, CallState.RINGING.name)
            .putString(KEY_CALL_TYPE, callType)
            .putString(KEY_CALLER_NAME, callerName)
            .putLong(KEY_RECEIVED_AT, System.currentTimeMillis())
            .apply()

        Log.d(TAG, "[CALL_STATE] RINGING callId=$callId")
    }

    @Synchronized
    fun setPendingCallAccepting(context: Context, callId: String): Boolean {
        val current = getCurrentState(context)
        val activeId = getCurrentCallId(context)
        if (activeId == callId && (current == CallState.ACCEPTING || current == CallState.ACTIVE || current == CallState.ENDING || current == CallState.TERMINAL)) {
            Log.d(TAG, "[CALL_STATE] duplicate accept ignored callId=$callId state=$current")
            return false
        }

        inMemoryState = CallState.ACCEPTING
        inMemoryCallId = callId

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_CALL_ID, callId)
            .putString(KEY_CALL_STATE, CallState.ACCEPTING.name)
            .apply()

        Log.d(TAG, "[CALL_STATE] ACCEPTING callId=$callId")
        return true
    }

    @Synchronized
    fun markCallActive(
        context: Context,
        callId: String,
        callerName: String = "Voryn User",
        callType: String = "audio",
        host: String = "LOCKED_CALL"
    ) {
        inMemoryState = CallState.ACTIVE
        inMemoryCallId = callId

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_CALL_ID, callId)
            .putString(KEY_CALL_STATE, CallState.ACTIVE.name)
            .putString(KEY_CALLER_NAME, callerName)
            .putString(KEY_CALL_TYPE, callType)
            .putString(KEY_HOST, host)
            .putLong(KEY_STARTED_AT, System.currentTimeMillis())
            .apply()

        Log.d(TAG, "[CALL_STATE] ACTIVE callId=$callId")
    }

    @Synchronized
    fun transition(context: Context, callId: String, newState: CallState) {
        val oldState = inMemoryState
        inMemoryState = newState
        if (newState == CallState.TERMINAL || newState == CallState.NONE) {
            inMemoryCallId = null
        } else {
            inMemoryCallId = callId
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (newState == CallState.TERMINAL || newState == CallState.NONE) {
            prefs.edit().clear().apply()
        } else {
            prefs.edit()
                .putString(KEY_CALL_ID, callId)
                .putString(KEY_CALL_STATE, newState.name)
                .apply()
        }

        Log.d(TAG, "[CALL_STATE] $newState callId=$callId")
    }

    @Synchronized
    fun getPendingIncomingCall(context: Context): Map<String, Any>? {
        val state = getCurrentState(context)
        // MUST return only when strictly RINGING
        if (state != CallState.RINGING) {
            return null
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val callId = prefs.getString(KEY_CALL_ID, null) ?: return null
        return mapOf(
            "callId" to callId,
            "callType" to (prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"),
            "callerName" to (prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"),
            "receivedAt" to prefs.getLong(KEY_RECEIVED_AT, 0L),
            "state" to CallState.RINGING.name
        )
    }

    @Synchronized
    fun getActiveCall(context: Context): Map<String, Any>? {
        val state = getCurrentState(context)
        if (state != CallState.ACTIVE && state != CallState.ACCEPTING) {
            return null
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val callId = prefs.getString(KEY_CALL_ID, null) ?: return null
        return mapOf(
            "callId" to callId,
            "callType" to (prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"),
            "callerName" to (prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"),
            "host" to (prefs.getString(KEY_HOST, "LOCKED_CALL") ?: "LOCKED_CALL"),
            "startedAt" to prefs.getLong(KEY_STARTED_AT, 0L),
            "state" to state.name
        )
    }

    @Synchronized
    fun clear(context: Context, callId: String? = null) {
        val currentId = getCurrentCallId(context)
        if (callId == null || currentId == callId) {
            val state = getCurrentState(context)
            if (state == CallState.ACCEPTING || state == CallState.ACTIVE) {
                Log.d(TAG, "[CALL_STATE] clear() ignored because callId=$callId is $state")
                return
            }
            transition(context, callId ?: currentId ?: "", CallState.TERMINAL)
        }
    }
}
