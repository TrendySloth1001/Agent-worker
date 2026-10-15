package com.sparky.app.assist

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.util.Log
import com.sparky.app.R

/**
 * The short chime when the assistant opens. The sample is preloaded (service
 * start) so the first play is instant. It is a sonification: no audio focus,
 * so music keeps playing. Silent on silent / vibrate, under Do Not Disturb,
 * or when the user turned "Sound on open" off. Never throws.
 */
object AssistSound {
    // Flutter's shared_preferences file and key prefix (see AppPrefs.assistOpenSound).
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.assist_open_sound"
    private const val VOLUME = 0.6f

    private var pool: SoundPool? = null
    private var soundId = 0

    @Volatile
    private var loaded = false

    /** Loads the sample once; safe to call repeatedly. */
    @Synchronized
    fun preload(context: Context) {
        if (pool != null) return
        try {
            val p = SoundPool.Builder()
                .setMaxStreams(1)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .build()
            p.setOnLoadCompleteListener { _, _, status -> loaded = status == 0 }
            soundId = p.load(context.applicationContext, R.raw.assist_open, 1)
            pool = p
        } catch (e: Exception) {
            Log.w(AssistProtocol.LOG_TAG, "could not load the open sound", e)
        }
    }

    /** Plays the chime once if the setting and the phone's state allow it. */
    fun play(context: Context) {
        try {
            val app = context.applicationContext
            if (!enabled(app) || !audible(app)) return
            preload(app)
            val p = pool ?: return
            if (loaded) p.play(soundId, VOLUME, VOLUME, 1, 0, 1f)
        } catch (e: Exception) {
            Log.w(AssistProtocol.LOG_TAG, "could not play the open sound", e)
        }
    }

    private fun enabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, true)

    private fun audible(context: Context): Boolean {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return false
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val filter = nm.currentInterruptionFilter
        return filter == NotificationManager.INTERRUPTION_FILTER_ALL ||
            filter == NotificationManager.INTERRUPTION_FILTER_UNKNOWN
    }
}
