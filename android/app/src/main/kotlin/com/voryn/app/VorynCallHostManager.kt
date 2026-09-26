package com.voryn.app

import android.util.Log

object VorynCallHostManager {
    private const val TAG = "VorynCall"

    enum class HostType { NONE, MAIN, LOCKED_CALL }
    enum class CallPresentationOrigin { IN_APP, EXTERNAL }

    @Volatile
    private var activeHost: HostType = HostType.NONE

    private val callOrigins = mutableMapOf<String, CallPresentationOrigin>()
    private val callStates = mutableMapOf<String, VorynCallStateManager.CallState>()

    @Synchronized
    fun claimCall(
        callId: String,
        host: HostType,
        state: VorynCallStateManager.CallState = VorynCallStateManager.CallState.ACCEPTING,
        origin: CallPresentationOrigin = CallPresentationOrigin.EXTERNAL
    ): Boolean {
        if (callId.isBlank()) return false
        if (activeHost != HostType.NONE && activeHost != host) {
            Log.w(
                TAG,
                "[HOST_OWNERSHIP] cannot claim callId=$callId for host=$host, already owned by activeHost=$activeHost"
            )
            return false
        }
        activeHost = host
        callStates[callId] = state
        if (!callOrigins.containsKey(callId)) {
            callOrigins[callId] = origin
        }
        if (host == HostType.LOCKED_CALL && origin == CallPresentationOrigin.IN_APP) {
            Log.w(TAG, "[CALL_INVARIANT] suspicious combination: owner=LOCKED_CALL origin=IN_APP callId=$callId")
        }
        Log.d(TAG, "[CALL_HOST] claimCall callId=$callId owner=$host state=$state origin=${callOrigins[callId]}")
        return true
    }

    @Synchronized
    fun updateState(callId: String, newState: VorynCallStateManager.CallState) {
        if (callStates.containsKey(callId)) {
            callStates[callId] = newState
            Log.d(TAG, "[CALL_HOST] updateState callId=$callId owner=$activeHost state=$newState origin=${callOrigins[callId]}")
        }
    }

    @Synchronized
    fun getOrigin(callId: String? = null): CallPresentationOrigin {
        if (callId != null && callOrigins.containsKey(callId)) {
            return callOrigins[callId]!!
        }
        return callOrigins.values.firstOrNull() ?: CallPresentationOrigin.EXTERNAL
    }

    @Synchronized
    fun setOrigin(callId: String, origin: CallPresentationOrigin) {
        if (!callOrigins.containsKey(callId)) {
            callOrigins[callId] = origin
            Log.d(TAG, "[CALL_HOST] setOrigin callId=$callId owner=$activeHost origin=$origin")
        }
    }

    @Synchronized
    fun releaseCall(callId: String, host: HostType) {
        if (activeHost == host) {
            callStates.remove(callId)
            callOrigins.remove(callId)
            Log.d(TAG, "[HOST_OWNERSHIP] released callId=$callId host=$host remaining=${callStates.keys}")
            if (callStates.isEmpty()) {
                activeHost = HostType.NONE
                Log.d(TAG, "[HOST_OWNERSHIP] all calls released, activeHost reset to NONE")
            }
        }
    }

    @Synchronized
    fun hasActiveOwner(callId: String): Boolean {
        val st = callStates[callId]
        return (activeHost == HostType.LOCKED_CALL || activeHost == HostType.MAIN) &&
            (st == VorynCallStateManager.CallState.ACTIVE || st == VorynCallStateManager.CallState.ACCEPTING || st == VorynCallStateManager.CallState.HELD)
    }

    @Synchronized
    fun isCallOwnedByLockedCall(callId: String): Boolean {
        return activeHost == HostType.LOCKED_CALL && (callStates.isEmpty() || callStates.containsKey(callId))
    }

    @Synchronized
    fun isAnyCallOwnedByLockedCall(): Boolean {
        return activeHost == HostType.LOCKED_CALL
    }

    @Synchronized
    fun getActiveCallId(): String? = callStates.keys.firstOrNull()

    @Synchronized
    fun getActiveHost(): HostType = activeHost

    @Synchronized
    fun getState(callId: String? = null): VorynCallStateManager.CallState {
        if (callId != null) return callStates[callId] ?: VorynCallStateManager.CallState.NONE
        return callStates.values.firstOrNull() ?: VorynCallStateManager.CallState.NONE
    }
}
