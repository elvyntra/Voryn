package com.voryn.app

import android.util.Log

object VorynCallHostManager {
    private const val TAG = "VorynCall"

    enum class HostType { NONE, MAIN, LOCKED_CALL }

    @Volatile
    private var activeCallId: String? = null

    @Volatile
    private var activeHost: HostType = HostType.NONE

    @Volatile
    private var callState: VorynCallStateManager.CallState = VorynCallStateManager.CallState.NONE

    @Synchronized
    fun claimCall(
        callId: String,
        host: HostType,
        state: VorynCallStateManager.CallState = VorynCallStateManager.CallState.ACCEPTING
    ): Boolean {
        if (callId.isBlank()) return false
        if (activeCallId != null && activeCallId != callId && activeHost != HostType.NONE) {
            Log.w(
                TAG,
                "[HOST_OWNERSHIP] cannot claim callId=$callId for host=$host, already owned by callId=$activeCallId host=$activeHost"
            )
            return false
        }
        activeCallId = callId
        activeHost = host
        callState = state
        Log.d(TAG, "[CALL_HOST] callId=$callId owner=$host state=$state")
        Log.d(TAG, "[HOST_OWNERSHIP] native host ownership = $host callId=$callId")
        return true
    }

    @Synchronized
    fun updateState(callId: String, newState: VorynCallStateManager.CallState) {
        if (activeCallId == callId) {
            callState = newState
            Log.d(TAG, "[CALL_HOST] callId=$callId owner=$activeHost state=$newState")
        }
    }

    @Synchronized
    fun releaseCall(callId: String, host: HostType) {
        if (activeCallId == callId && activeHost == host) {
            Log.d(TAG, "[HOST_OWNERSHIP] released callId=$callId host=$host")
            activeCallId = null
            activeHost = HostType.NONE
            callState = VorynCallStateManager.CallState.NONE
        }
    }

    @Synchronized
    fun hasActiveOwner(callId: String): Boolean {
        return (activeCallId == callId) &&
            (activeHost == HostType.LOCKED_CALL || activeHost == HostType.MAIN) &&
            (callState == VorynCallStateManager.CallState.ACTIVE || callState == VorynCallStateManager.CallState.ACCEPTING)
    }

    @Synchronized
    fun isCallOwnedByLockedCall(callId: String): Boolean {
        return activeHost == HostType.LOCKED_CALL && (activeCallId == null || activeCallId == callId)
    }

    @Synchronized
    fun isAnyCallOwnedByLockedCall(): Boolean {
        return activeHost == HostType.LOCKED_CALL
    }

    @Synchronized
    fun getActiveCallId(): String? = activeCallId

    @Synchronized
    fun getActiveHost(): HostType = activeHost

    @Synchronized
    fun getState(): VorynCallStateManager.CallState = callState
}
