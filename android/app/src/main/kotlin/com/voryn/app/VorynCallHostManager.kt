package com.voryn.app

import android.util.Log

object VorynCallHostManager {
    private const val TAG = "VorynCall"

    enum class HostType { NONE, MAIN, LOCKED_CALL }

    @Volatile
    private var activeCallId: String? = null

    @Volatile
    private var activeHost: HostType = HostType.NONE

    @Synchronized
    fun claimCall(callId: String, host: HostType): Boolean {
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
        Log.d(TAG, "[CALL_HOST] owner=$host callId=$callId")
        Log.d(TAG, "[HOST_OWNERSHIP] native host ownership = $host callId=$callId")
        return true
    }

    @Synchronized
    fun releaseCall(callId: String, host: HostType) {
        if (activeCallId == callId && activeHost == host) {
            Log.d(TAG, "[HOST_OWNERSHIP] released callId=$callId host=$host")
            activeCallId = null
            activeHost = HostType.NONE
        }
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
}
