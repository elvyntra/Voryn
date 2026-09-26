package com.voryn.app

import android.content.Context
import android.util.Log

object VorynCallStateManager {
    private const val TAG = "VorynCall"
    private const val PREFS_NAME = "voryn_call_state_v1"

    private const val KEY_ACTIVE_CALL_ID = "active_call_id"
    private const val KEY_HELD_CALL_ID = "held_call_id"
    private const val KEY_WAITING_CALL_ID = "waiting_call_id"

    private const val KEY_CALL_ID = "call_id" // legacy mirror of active call
    private const val KEY_CALL_STATE = "call_state"
    private const val KEY_CALL_TYPE = "call_type"
    private const val KEY_CALLER_NAME = "caller_name"
    private const val KEY_HOST = "host"
    private const val KEY_RECEIVED_AT = "received_at"
    private const val KEY_STARTED_AT = "started_at"
    private const val KEY_PRESENTATION_STATE = "presentation_state"
    private const val KEY_CALL_ORIGIN = "call_origin"

    private const val KEY_HELD_CALLER_NAME = "held_caller_name"
    private const val KEY_HELD_CALL_TYPE = "held_call_type"
    private const val KEY_WAITING_CALLER_NAME = "waiting_caller_name"
    private const val KEY_WAITING_CALL_TYPE = "waiting_call_type"
    private const val KEY_WAITING_RECEIVED_AT = "waiting_received_at"

    enum class CallState {
        NONE,
        RINGING,
        ACCEPTING,
        ACTIVE,
        HELD,
        ENDING,
        TERMINAL
    }

    enum class PresentationState {
        FULLSCREEN,
        MINIMIZED
    }

    data class MultiCallState(
        val activeCallId: String? = null,
        val heldCallId: String? = null,
        val waitingCallId: String? = null,
        val activeCallState: CallState = CallState.NONE
    )

    @Volatile
    private var inMemoryState: CallState = CallState.NONE

    @Volatile
    private var inMemoryPresentation: PresentationState = PresentationState.FULLSCREEN

    @Volatile
    private var inMemoryOrigin: VorynCallHostManager.CallPresentationOrigin? = null

    @Volatile
    private var inMemoryMultiCallState = MultiCallState()

    @Synchronized
    fun getMultiCallState(context: Context): MultiCallState {
        if (inMemoryMultiCallState.activeCallId != null || inMemoryMultiCallState.heldCallId != null || inMemoryMultiCallState.waitingCallId != null) {
            return inMemoryMultiCallState
        }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val activeId = prefs.getString(KEY_ACTIVE_CALL_ID, null) ?: prefs.getString(KEY_CALL_ID, null)
        val heldId = prefs.getString(KEY_HELD_CALL_ID, null)
        val waitingId = prefs.getString(KEY_WAITING_CALL_ID, null)
        val stateStr = prefs.getString(KEY_CALL_STATE, null)
        val st = if (stateStr != null) {
            try { CallState.valueOf(stateStr) } catch (_: Exception) { CallState.NONE }
        } else CallState.NONE

        inMemoryMultiCallState = MultiCallState(
            activeCallId = activeId,
            heldCallId = heldId,
            waitingCallId = waitingId,
            activeCallState = st
        )
        return inMemoryMultiCallState
    }

    @Synchronized
    fun hasActiveOrHeldCall(context: Context): Boolean {
        val s = getMultiCallState(context)
        return (s.activeCallId != null && (s.activeCallState == CallState.ACTIVE || s.activeCallState == CallState.ACCEPTING)) ||
            (s.heldCallId != null)
    }

    @Synchronized
    fun getCurrentState(context: Context): CallState {
        val s = getMultiCallState(context)
        return s.activeCallState
    }

    @Synchronized
    fun getCurrentCallId(context: Context): String? {
        val s = getMultiCallState(context)
        return s.activeCallId
    }

    @Synchronized
    fun recordRingingCall(
        context: Context,
        callId: String,
        callType: String,
        callerName: String
    ) {
        val s = getMultiCallState(context)
        if (s.activeCallId == callId && (s.activeCallState == CallState.ACCEPTING || s.activeCallState == CallState.ACTIVE)) {
            Log.d(TAG, "[CALL_STATE] duplicate incoming ignored callId=$callId state=${s.activeCallState}")
            return
        }

        // If an active call exists, record as waiting call instead of clobbering active call
        if (hasActiveOrHeldCall(context)) {
            recordWaitingCall(context, callId, callType, callerName)
            return
        }

        inMemoryMultiCallState = inMemoryMultiCallState.copy(
            activeCallId = callId,
            activeCallState = CallState.RINGING
        )
        inMemoryState = CallState.RINGING

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_CALL_ID, callId)
            .putString(KEY_ACTIVE_CALL_ID, callId)
            .putString(KEY_CALL_STATE, CallState.RINGING.name)
            .putString(KEY_CALL_TYPE, callType)
            .putString(KEY_CALLER_NAME, callerName)
            .putLong(KEY_RECEIVED_AT, System.currentTimeMillis())
            .apply()

        Log.d(TAG, "[CALL_STATE] RINGING activeCallId=$callId")
    }

    @Synchronized
    fun recordWaitingCall(
        context: Context,
        callId: String,
        callType: String,
        callerName: String
    ) {
        val s = getMultiCallState(context)
        // Capacity check: Max 2 calls (1 active + 1 waiting/held)
        if (s.activeCallId != null && s.heldCallId != null) {
            Log.w(TAG, "[CALL_WAITING] rejected 3rd incoming call $callId: capacity full")
            return
        }

        inMemoryMultiCallState = inMemoryMultiCallState.copy(waitingCallId = callId)

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_WAITING_CALL_ID, callId)
            .putString(KEY_WAITING_CALL_TYPE, callType)
            .putString(KEY_WAITING_CALLER_NAME, callerName)
            .putLong(KEY_WAITING_RECEIVED_AT, System.currentTimeMillis())
            .apply()

        Log.d(TAG, "[CALL_STATE] WAITING callId=$callId activeCallId=${s.activeCallId} heldCallId=${s.heldCallId}")
    }

    @Synchronized
    fun holdActiveAndAcceptWaiting(
        context: Context,
        heldCallId: String,
        activeCallId: String,
        callerName: String? = null,
        callType: String? = null
    ) {
        val current = getMultiCallState(context)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val oldActiveName = prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"
        val oldActiveType = prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"

        inMemoryMultiCallState = MultiCallState(
            activeCallId = activeCallId,
            heldCallId = heldCallId,
            waitingCallId = null,
            activeCallState = CallState.ACTIVE
        )
        inMemoryState = CallState.ACTIVE

        prefs.edit()
            .putString(KEY_ACTIVE_CALL_ID, activeCallId)
            .putString(KEY_CALL_ID, activeCallId)
            .putString(KEY_CALL_STATE, CallState.ACTIVE.name)
            .putString(KEY_CALLER_NAME, callerName ?: "Voryn User")
            .putString(KEY_CALL_TYPE, callType ?: "audio")
            .putString(KEY_HELD_CALL_ID, heldCallId)
            .putString(KEY_HELD_CALLER_NAME, oldActiveName)
            .putString(KEY_HELD_CALL_TYPE, oldActiveType)
            .remove(KEY_WAITING_CALL_ID)
            .remove(KEY_WAITING_CALLER_NAME)
            .remove(KEY_WAITING_CALL_TYPE)
            .remove(KEY_WAITING_RECEIVED_AT)
            .apply()

        VorynCallHostManager.updateState(heldCallId, CallState.HELD)
        VorynCallHostManager.updateState(activeCallId, CallState.ACTIVE)
        Log.d(TAG, "[CALL_STATE] holdActiveAndAcceptWaiting active=$activeCallId held=$heldCallId")
    }

    @Synchronized
    fun switchCalls(
        context: Context,
        newActiveCallId: String,
        newHeldCallId: String
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val activeName = prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"
        val activeType = prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"
        val heldName = prefs.getString(KEY_HELD_CALLER_NAME, "Voryn User") ?: "Voryn User"
        val heldType = prefs.getString(KEY_HELD_CALL_TYPE, "audio") ?: "audio"

        inMemoryMultiCallState = inMemoryMultiCallState.copy(
            activeCallId = newActiveCallId,
            heldCallId = newHeldCallId,
            activeCallState = CallState.ACTIVE
        )
        inMemoryState = CallState.ACTIVE

        prefs.edit()
            .putString(KEY_ACTIVE_CALL_ID, newActiveCallId)
            .putString(KEY_CALL_ID, newActiveCallId)
            .putString(KEY_CALLER_NAME, heldName)
            .putString(KEY_CALL_TYPE, heldType)
            .putString(KEY_HELD_CALL_ID, newHeldCallId)
            .putString(KEY_HELD_CALLER_NAME, activeName)
            .putString(KEY_HELD_CALL_TYPE, activeType)
            .apply()

        VorynCallHostManager.updateState(newHeldCallId, CallState.HELD)
        VorynCallHostManager.updateState(newActiveCallId, CallState.ACTIVE)
        Log.d(TAG, "[CALL_STATE] switchCalls active=$newActiveCallId held=$newHeldCallId")
    }

    @Synchronized
    fun resumeHeldCall(context: Context, resumedCallId: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val heldName = prefs.getString(KEY_HELD_CALLER_NAME, "Voryn User") ?: "Voryn User"
        val heldType = prefs.getString(KEY_HELD_CALL_TYPE, "audio") ?: "audio"

        inMemoryMultiCallState = MultiCallState(
            activeCallId = resumedCallId,
            heldCallId = null,
            waitingCallId = inMemoryMultiCallState.waitingCallId,
            activeCallState = CallState.ACTIVE
        )
        inMemoryState = CallState.ACTIVE

        prefs.edit()
            .putString(KEY_ACTIVE_CALL_ID, resumedCallId)
            .putString(KEY_CALL_ID, resumedCallId)
            .putString(KEY_CALLER_NAME, heldName)
            .putString(KEY_CALL_TYPE, heldType)
            .remove(KEY_HELD_CALL_ID)
            .remove(KEY_HELD_CALLER_NAME)
            .remove(KEY_HELD_CALL_TYPE)
            .apply()

        VorynCallHostManager.updateState(resumedCallId, CallState.ACTIVE)
        Log.d(TAG, "[CALL_STATE] resumeHeldCall active=$resumedCallId held=null")
    }

    @Synchronized
    fun clearHeldCall(context: Context, heldCallId: String) {
        val s = getMultiCallState(context)
        if (s.heldCallId == heldCallId) {
            inMemoryMultiCallState = inMemoryMultiCallState.copy(heldCallId = null)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .remove(KEY_HELD_CALL_ID)
                .remove(KEY_HELD_CALLER_NAME)
                .remove(KEY_HELD_CALL_TYPE)
                .apply()
            VorynCallHostManager.releaseCall(heldCallId, VorynCallHostManager.getActiveHost())
            Log.d(TAG, "[CALL_STATE] clearHeldCall callId=$heldCallId")
        }
    }

    @Synchronized
    fun clearWaitingCall(context: Context, callId: String) {
        val s = getMultiCallState(context)
        if (s.waitingCallId == callId) {
            inMemoryMultiCallState = inMemoryMultiCallState.copy(waitingCallId = null)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .remove(KEY_WAITING_CALL_ID)
                .remove(KEY_WAITING_CALLER_NAME)
                .remove(KEY_WAITING_CALL_TYPE)
                .remove(KEY_WAITING_RECEIVED_AT)
                .apply()
            Log.d(TAG, "[CALL_STATE] clearWaitingCall callId=$callId")
        }
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
        inMemoryMultiCallState = inMemoryMultiCallState.copy(
            activeCallId = callId,
            activeCallState = CallState.ACCEPTING
        )

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_CALL_ID, callId)
            .putString(KEY_ACTIVE_CALL_ID, callId)
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
        inMemoryMultiCallState = inMemoryMultiCallState.copy(
            activeCallId = callId,
            activeCallState = CallState.ACTIVE
        )

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
            .putString(KEY_ACTIVE_CALL_ID, callId)
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
        val s = getMultiCallState(context)
        if (s.activeCallState != CallState.ACTIVE && s.activeCallState != CallState.ACCEPTING) {
            return null
        }
        val callId = s.activeCallId ?: return null
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val presentation = getPresentationState(context)
        val origin = getCallOrigin(context)
        val host = prefs.getString(KEY_HOST, null) ?: VorynCallHostManager.getActiveHost().name
        return mapOf(
            "callId" to callId,
            "state" to s.activeCallState.name,
            "presentation" to presentation.name,
            "origin" to origin.name,
            "host" to host,
            "callType" to (prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"),
            "displayName" to (prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"),
            "startedAt" to prefs.getLong(KEY_STARTED_AT, 0L),
            "heldCallId" to (s.heldCallId ?: ""),
            "heldCallerName" to (prefs.getString(KEY_HELD_CALLER_NAME, "") ?: "")
        )
    }

    @Synchronized
    fun transition(context: Context, callId: String, newState: CallState) {
        val s = getMultiCallState(context)

        // If held call transitioned to terminal
        if (s.heldCallId == callId) {
            if (newState == CallState.TERMINAL || newState == CallState.NONE) {
                clearHeldCall(context, callId)
            }
            return
        }

        // If waiting call transitioned to terminal
        if (s.waitingCallId == callId) {
            if (newState == CallState.TERMINAL || newState == CallState.NONE) {
                clearWaitingCall(context, callId)
            }
            return
        }

        // Active call transitioned
        inMemoryState = newState
        val isTerminal = (newState == CallState.TERMINAL || newState == CallState.NONE)

        if (isTerminal) {
            VorynCallHostManager.releaseCall(callId, VorynCallHostManager.getActiveHost())
            // If a held call exists, promote it to active!
            if (s.heldCallId != null) {
                resumeHeldCall(context, s.heldCallId)
                return
            } else {
                inMemoryMultiCallState = MultiCallState()
                inMemoryPresentation = PresentationState.FULLSCREEN
                inMemoryOrigin = null
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().clear().apply()
            }
        } else {
            inMemoryMultiCallState = inMemoryMultiCallState.copy(
                activeCallId = callId,
                activeCallState = newState
            )
            VorynCallHostManager.updateState(callId, newState)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(KEY_CALL_ID, callId)
                .putString(KEY_ACTIVE_CALL_ID, callId)
                .putString(KEY_CALL_STATE, newState.name)
                .apply()
        }

        Log.d(TAG, "[CALL_STATE] $newState callId=$callId (active=${inMemoryMultiCallState.activeCallId}, held=${inMemoryMultiCallState.heldCallId})")
    }

    @Synchronized
    fun getPendingIncomingCall(context: Context): Map<String, Any>? {
        val s = getMultiCallState(context)
        if (s.activeCallState != CallState.RINGING) {
            return null
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val callId = s.activeCallId ?: return null
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
    fun getWaitingCall(context: Context): Map<String, Any>? {
        val s = getMultiCallState(context)
        val waitingId = s.waitingCallId ?: return null
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val receivedAt = prefs.getLong(KEY_WAITING_RECEIVED_AT, 0L)
        val now = System.currentTimeMillis()
        if (receivedAt > 0L && (now - receivedAt) > 60000L) {
            return null
        }

        return mapOf(
            "callId" to waitingId,
            "callType" to (prefs.getString(KEY_WAITING_CALL_TYPE, "audio") ?: "audio"),
            "callerName" to (prefs.getString(KEY_WAITING_CALLER_NAME, "Voryn User") ?: "Voryn User"),
            "receivedAt" to receivedAt
        )
    }

    @Synchronized
    fun getActiveCall(context: Context): Map<String, Any>? {
        val s = getMultiCallState(context)
        if (s.activeCallState != CallState.ACTIVE && s.activeCallState != CallState.ACCEPTING) {
            return null
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val callId = s.activeCallId ?: return null
        return mapOf(
            "callId" to callId,
            "callType" to (prefs.getString(KEY_CALL_TYPE, "audio") ?: "audio"),
            "callerName" to (prefs.getString(KEY_CALLER_NAME, "Voryn User") ?: "Voryn User"),
            "host" to (prefs.getString(KEY_HOST, "LOCKED_CALL") ?: "LOCKED_CALL"),
            "startedAt" to prefs.getLong(KEY_STARTED_AT, 0L),
            "state" to s.activeCallState.name,
            "heldCallId" to (s.heldCallId ?: "")
        )
    }

    @Synchronized
    fun clear(context: Context, callId: String? = null) {
        val s = getMultiCallState(context)
        if (callId != null) {
            if (s.waitingCallId == callId) {
                clearWaitingCall(context, callId)
                return
            }
            if (s.heldCallId == callId) {
                clearHeldCall(context, callId)
                return
            }
        }
        if (callId == null || s.activeCallId == callId) {
            if (s.activeCallState == CallState.ACCEPTING || s.activeCallState == CallState.ACTIVE) {
                Log.d(TAG, "[CALL_STATE] clear() ignored because callId=$callId is ${s.activeCallState}")
                return
            }
            inMemoryPresentation = PresentationState.FULLSCREEN
            transition(context, callId ?: s.activeCallId ?: "", CallState.TERMINAL)
        }
    }
}
