package com.sparky.app.assist

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Speaks answers in the overlay's Live mode with Android's TextToSpeech
 * ('app/tts'). `speak` queues one utterance; `onDone(id)` goes back to Dart
 * when it finished or was stopped, so Dart knows when to listen again.
 * The engine starts on first use and stays (the overlay engine is cached).
 */
class TtsBridge(context: Context, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ready = false
    private var failed = false

    /** Utterances asked before the engine was ready. */
    private val pending = ArrayList<Triple<String, String?, String>>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            AssistProtocol.TTS_SPEAK -> {
                val text = call.argument<String>(AssistProtocol.TTS_TEXT).orEmpty()
                val id = call.argument<String>(AssistProtocol.TTS_ID).orEmpty()
                val lang = call.argument<String>(AssistProtocol.TTS_LANG)
                result.success(speak(text, lang, id))
            }
            AssistProtocol.TTS_STOP -> {
                stopNow()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun stopNow() {
        pending.clear()
        tts?.stop()
    }

    private fun speak(text: String, lang: String?, id: String): Boolean {
        if (failed || text.isBlank()) return false
        if (!ready) {
            pending.add(Triple(text, lang, id))
            ensure()
            return true
        }
        val engine = tts ?: return false
        if (!lang.isNullOrBlank()) {
            val locale = Locale.forLanguageTag(lang)
            if (engine.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE) engine.language = locale
        }
        return engine.speak(text, TextToSpeech.QUEUE_ADD, null, id) == TextToSpeech.SUCCESS
    }

    private fun ensure() {
        if (tts != null) return
        tts = TextToSpeech(app) { status ->
            main.post {
                if (status != TextToSpeech.SUCCESS) {
                    failed = true
                    Log.w(AssistProtocol.LOG_TAG, "text to speech unavailable")
                    pending.forEach { done(it.third) }
                    pending.clear()
                    return@post
                }
                ready = true
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) = done(utteranceId)
                    override fun onStop(utteranceId: String?, interrupted: Boolean) = done(utteranceId)

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) = done(utteranceId)
                })
                val queued = ArrayList(pending)
                pending.clear()
                queued.forEach { speak(it.first, it.second, it.third) }
            }
        }
    }

    private fun done(id: String?) {
        main.post { channel.invokeMethod(AssistProtocol.TTS_ON_DONE, id) }
    }
}
