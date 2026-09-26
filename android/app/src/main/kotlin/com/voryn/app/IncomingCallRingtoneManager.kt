package com.voryn.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log

object IncomingCallRingtoneManager {
    private const val TAG = "VorynCall"
    private var ringtone: Ringtone? = null
    private var activeCallId: String? = null
    private var vibrator: Vibrator? = null

    @Synchronized
    fun start(context: Context, callId: String) {
        if (activeCallId == callId && ringtone?.isPlaying == true) {
            return
        }
        if (activeCallId != null && activeCallId != callId) {
            stop("new_incoming", activeCallId)
        }

        Log.d(TAG, "[RINGTONE] start callId=$callId")
        activeCallId = callId

        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val ringerMode = audioManager.ringerMode

            if (ringerMode == AudioManager.RINGER_MODE_NORMAL) {
                val uri = RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
                    ?: Settings.System.DEFAULT_RINGTONE_URI
                val rt = RingtoneManager.getRingtone(context, uri)
                if (rt != null) {
                    val attrs = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    rt.audioAttributes = attrs
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        rt.isLooping = true
                    }
                    rt.play()
                    ringtone = rt
                }
            }

            if (ringerMode != AudioManager.RINGER_MODE_SILENT) {
                startVibration(context)
            }
        } catch (e: Exception) {
            Log.e(TAG, "[RINGTONE] error starting ringtone: ${e.message}")
        }
    }

    @Synchronized
    fun playCallWaitingTone(context: Context) {
        Log.d(TAG, "[RINGTONE] playCallWaitingTone")
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (audioManager.ringerMode != AudioManager.RINGER_MODE_SILENT) {
                // Subtle dual-pulse vibration
                val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                    vm.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 150, 100, 150), -1))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(longArrayOf(0, 150, 100, 150), -1)
                }
            }

            // Discreet telephony call-waiting tone (tuned volume 60 out of 100)
            val tg = android.media.ToneGenerator(AudioManager.STREAM_VOICE_CALL, 60)
            tg.startTone(android.media.ToneGenerator.TONE_SUP_CALL_WAITING, 250)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    tg.release()
                } catch (_: Exception) {}
            }, 600)
        } catch (e: Exception) {
            Log.e(TAG, "[RINGTONE] error playing call waiting tone: ${e.message}")
        }
    }

    @Synchronized
    fun stop(reason: String, callId: String? = null) {
        if (callId != null && activeCallId != null && callId != activeCallId) {
            return
        }
        Log.d(TAG, "[RINGTONE] stop reason=$reason")
        try {
            ringtone?.let {
                if (it.isPlaying) {
                    it.stop()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "[RINGTONE] error stopping ringtone: ${e.message}")
        } finally {
            ringtone = null
            activeCallId = null
            stopVibration()
            Log.d(TAG, "[RINGTONE] released")
        }
    }

    private fun startVibration(context: Context) {
        try {
            val pattern = longArrayOf(0, 1000, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibrator = vm.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "[RINGTONE] error starting vibration: ${e.message}")
        }
    }

    private fun stopVibration() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        } finally {
            vibrator = null
        }
    }
}
