package com.voryn.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.util.Log

object VorynProximityController {
    private const val TAG = "VorynCall"
    private var wakeLock: PowerManager.WakeLock? = null
    private var isSupported: Boolean = false
    private var initialized: Boolean = false

    private var currentCallId: String? = null
    private var isConnected: Boolean = false
    private var mediaMode: String = "audio"
    private var isHeld: Boolean = false
    private var isEnding: Boolean = false

    private var listenerRegistered: Boolean = false
    private var communicationDeviceListener: Any? = null

    @Synchronized
    fun probe(context: Context): Boolean {
        if (initialized) return isSupported
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            val sensor = sm?.getDefaultSensor(Sensor.TYPE_PROXIMITY)
            val featureSensorAvailable = sensor != null
            val wakeLockSupported = pm?.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK) == true

            Log.d(TAG, "[PROXIMITY] featureSensorAvailable=$featureSensorAvailable wakeLockSupported=$wakeLockSupported")

            isSupported = featureSensorAvailable && wakeLockSupported
            if (isSupported && pm != null) {
                wakeLock = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "voryn:proximity_lock").apply {
                    setReferenceCounted(false)
                }
            }
            registerAudioDeviceListener(context)
        } catch (e: Exception) {
            Log.e(TAG, "[PROXIMITY] probe error: ${e.message}")
            isSupported = false
        }
        initialized = true
        return isSupported
    }

    fun isSupported(): Boolean = isSupported

    private fun registerAudioDeviceListener(context: Context) {
        if (listenerRegistered) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            val listener = AudioManager.OnCommunicationDeviceChangedListener { _ ->
                evaluate(context)
            }
            try {
                am.addOnCommunicationDeviceChangedListener(context.mainExecutor, listener)
                communicationDeviceListener = listener
                listenerRegistered = true
            } catch (e: Exception) {
                Log.w(TAG, "[PROXIMITY] failed to register communication device listener: ${e.message}")
            }
        }
    }

    fun getEffectiveAudioRouteInfo(context: Context): Pair<String, Int> {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return Pair("earpiece", -1)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = am.communicationDevice
            if (device != null) {
                val route = when (device.type) {
                    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_BLE_HEADSET,
                    AudioDeviceInfo.TYPE_HEARING_AID -> "bluetooth"
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_USB_HEADSET -> "headset"
                    else -> "other"
                }
                return Pair(route, device.type)
            }
        }
        if (am.isSpeakerphoneOn) return Pair("speaker", AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
        if (am.isBluetoothScoOn) return Pair("bluetooth", AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
        @Suppress("DEPRECATION")
        if (am.isWiredHeadsetOn) return Pair("headset", AudioDeviceInfo.TYPE_WIRED_HEADSET)
        return Pair("earpiece", AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
    }

    @Synchronized
    fun updateCallState(
        context: Context,
        callId: String,
        connected: Boolean,
        mode: String,
        held: Boolean,
        ending: Boolean
    ) {
        currentCallId = callId
        isConnected = connected
        mediaMode = mode
        isHeld = held
        isEnding = ending
        evaluate(context)
    }

    @Synchronized
    fun evaluate(context: Context) {
        if (!isSupported || wakeLock == null) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val (route, deviceType) = getEffectiveAudioRouteInfo(context)
        val available = am?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.map { d ->
            when (d.type) {
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_HEARING_AID -> "bluetooth"
                AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_HEADSET -> "headset"
                else -> "other(${d.type})"
            }
        }?.distinct() ?: emptyList()
        Log.d(TAG, "[AUDIO_ROUTE] available=$available")
        Log.d(TAG, "[AUDIO_ROUTE] actual=$route deviceType=$deviceType")
        Log.d(TAG, "[PROXIMITY] audioRoute=$route deviceType=$deviceType")
        val shouldEnable = isConnected && mediaMode == "audio" && route == "earpiece" && !isHeld && !isEnding

        try {
            if (shouldEnable) {
                if (wakeLock?.isHeld != true) {
                    wakeLock?.acquire()
                    Log.d(TAG, "[PROXIMITY] enable route=$route held=true")
                }
            } else {
                if (wakeLock?.isHeld == true) {
                    val reason = when {
                        isEnding -> "call_end"
                        !isConnected -> "not_connected"
                        isHeld -> "hold"
                        mediaMode != "audio" -> "video"
                        route != "earpiece" -> route
                        else -> "disabled"
                    }
                    wakeLock?.release()
                    Log.d(TAG, "[PROXIMITY] disable reason=$reason held=false")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "[PROXIMITY] evaluate error: ${e.message}")
        }
    }

    @Synchronized
    fun releaseAll(reason: String = "call_end") {
        isConnected = false
        isEnding = true
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.d(TAG, "[PROXIMITY] disable reason=$reason held=false")
            }
        } catch (e: Exception) {
            Log.e(TAG, "[PROXIMITY] releaseAll error: ${e.message}")
        }
    }
}
