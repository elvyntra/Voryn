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
    private const val KEY_HOST = "host"
    private const val KEY_RECEIVED_AT = "received_at"
    private const val KEY_STARTED_AT = "started_at"
    private const val KEY_PRESENTATION_STATE = "presentation_state"
    private const val KEY_CALL_ORIGIN = "call_origin"

    enum class CallState {
        NONE,
        RINGING,
        ACCEPTING,
        ACTIVE,
        ENDING,
        TERMINAL
    }

    enum class PresentationState {
        FULLSCREEN,
        MINIMIZED
    }

    @Volatile
    private var inMemoryState: CallState = CallState.NONE

    @Volatile
    private var inMemoryPresentation: PresentationState = PresentationState.FULLSCREEN

    @Volatile
    private var inMemoryOrigin: VorynCallHostManager.CallPresentationOrigin? = null

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
            Log.d(TAG, "[CALL_ACCEPT] callId=$callId oldState=$current result=ignored_already_accepted")
            return false
        }

        val oldState = current
        inMemoryState = CallState.ACCEPTING
        inMemoryCallId = callId

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_CALL_ID, callId)
            .putString(KEY_CALL_STATE, CallState.ACCEPTING.name)
            .apply()

        VorynCallHostManager.updateState(callId, CallState.ACCEPTING)
        Log.d(TAG, "[CALL_ACCEPT] callId=$callId oldState=$oldState newState=ACCEPTING result=accepted")
        Log.d(TAG, "[CALL_STATE] ACCEPTING callId=$callId")
        return true
    }

    @Synchronized
    fun markCallActive(
        context: Context,
        callId: String,
        callerName: String = "Voryn User",
        callType: String = "audio",
        host: String = "LOCKED_CALL",
        origin: VorynCallHostManager.CallPresentationOrigin? = null
    ) {
        inMemoryState = CallState.ACTIVE
        inMemoryPresentation = PresentationState.FULLSCREEN
        inMemoryCallId = callId

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existingOriginStr = prefs.getString(KEY_CALL_ORIGIN, null)
        val hostOrigin = VorynCallHostManager.getOrigin(callId)
        val resolvedOrigin = when {
            inMemoryOrigin != null -> inMemoryOrigin!!
            existingOriginStr != null -> {
                try {
                    VorynCallHostManager.CallPresentationOrigin.valueOf(existingOriginStr)
                } catch (_: Exception) {
                    hostOrigin
                }
            }
            hostOrigin == VorynCallHostManager.CallPresentationOrigin.EXTERNAL -> hostOrigin
            else -> origin ?: hostOrigin
        }
        inMemoryOrigin = resolvedOrigin

        val editor = prefs.edit()
            .putString(KEY_CALL_ID, callId)
            .putString(KEY_CALL_STATE, CallState.ACTIVE.name)
            .putString(KEY_PRESENTATION_STATE, PresentationState.FULLSCREEN.name)
            .putString(KEY_CALLER_NAME, callerName)
            .putString(KEY_CALL_TYPE, callType)
            .putString(KEY_HOST, host)
            .putLong(KEY_STARTED_AT, System.currentTimeMillis())

        if (existingOriginStr == null) {
            editor.putString(KEY_CALL_ORIGIN, resolvedOrigin.name)
        }
        editor.apply()

        VorynCallHostManager.updateState(callId, CallState.ACTIVE)
        Log.d(TAG, "[CALL_STATE] ACTIVE callId=$callId origin=$resolvedOrigin")
    }

    @Synchronized
    fun getCallOrigin(context: Context): VorynCallHostManager.CallPresentationOrigin {
        if (inMemoryOrigin != null) return inMemoryOrigin!!
        val hostOrigin = VorynCallHostManager.getOrigin()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val origStr = prefs.getString(KEY_CALL_ORIGIN, null)
        if (origStr != null) {
            inMemoryOrigin = try {
                VorynCallHostManager.CallPresentationOrigin.valueOf(origStr)
            } catch (_: Exception) {
                hostOrigin
            }
            return inMemoryOrigin!!
        }
        return hostOrigin
    }

    @Synchronized
    fun getCallerName(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"
    }

    @Synchronized
    fun getCallType(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"
    }

    @Synchronized
    fun setCallPresentationState(context: Context, callId: String, presentation: PresentationState) {
        inMemoryPresentation = presentation
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_PRESENTATION_STATE, presentation.name)
            .apply()
        Log.d(TAG, "[CALL_PRESENTATION] $presentation callId=$callId")
    }

    @Synchronized
    fun getPresentationState(context: Context): PresentationState {
        if (inMemoryPresentation != PresentationState.FULLSCREEN) return inMemoryPresentation
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val presStr = prefs.getString(KEY_PRESENTATION_STATE, null) ?: return PresentationState.FULLSCREEN
        inMemoryPresentation = try {
            PresentationState.valueOf(presStr)
        } catch (_: Exception) {
            PresentationState.FULLSCREEN
        }
        return inMemoryPresentation
    }

    @Synchronized
    fun getActiveCallSnapshot(context: Context): Map<String, Any>? {
        val state = getCurrentState(context)
        if (state != CallState.ACTIVE && state != CallState.ACCEPTING) {
            return null
        }
        val callId = getCurrentCallId(context) ?: return null
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val presentation = getPresentationState(context)
        val origin = getCallOrigin(context)
        val host = prefs.getString(KEY_HOST, null) ?: VorynCallHostManager.getActiveHost().name
        return mapOf(
            "callId" to callId,
            "state" to state.name,
            "presentation" to presentation.name,
            "origin" to origin.name,
            "host" to host,
            "callType" to (prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"),
            "displayName" to (prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"),
            "startedAt" to prefs.getLong(KEY_STARTED_AT, 0L)
        )
    }

    @Synchronized
    fun transition(context: Context, callId: String, newState: CallState) {
        val oldState = inMemoryState
        inMemoryState = newState
        if (newState == CallState.TERMINAL || newState == CallState.NONE) {
            inMemoryCallId = null
            inMemoryPresentation = PresentationState.FULLSCREEN
            inMemoryOrigin = null
            VorynCallHostManager.releaseCall(callId, VorynCallHostManager.getActiveHost())
        } else {
            inMemoryCallId = callId
            VorynCallHostManager.updateState(callId, newState)
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
        val receivedAt = prefs.getLong(KEY_RECEIVED_AT, 0L)
        val now = System.currentTimeMillis()
        if (receivedAt > 0L && (now - receivedAt) > 60000L) {
            return null
        }

        return mapOf(
            "callId" to callId,
            "callType" to (prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"),
            "callerName" to (prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"),
            "receivedAt" to receivedAt,
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
            inMemoryPresentation = PresentationState.FULLSCREEN
            transition(context, callId ?: currentId ?: "", CallState.TERMINAL)
        }
    }
}
