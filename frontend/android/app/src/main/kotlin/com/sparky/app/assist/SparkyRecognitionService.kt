package com.sparky.app.assist

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * Android only lists an assistant that names a speech recognizer, and makes
 * that recognizer the system default when the assistant is chosen. sparky
 * has no recognizer of its own, so this one forwards every request to the
 * best other recognizer on the device (Google's when present); dictation in
 * other apps (and in sparky) keeps working after switching assistants.
 */
class SparkyRecognitionService : RecognitionService() {
    private var delegate: SpeechRecognizer? = null

    private val preferred = listOf(
        "com.google.android.googlequicksearchbox",
        "com.google.android.tts",
        "com.google.android.as",
    )

    override fun onStartListening(intent: Intent, callback: Callback) {
        release()
        val target = pickTarget()
        if (target == null) {
            safe { callback.error(SpeechRecognizer.ERROR_CLIENT) }
            return
        }
        val recognizer = try {
            SpeechRecognizer.createSpeechRecognizer(this, target)
        } catch (e: Exception) {
            safe { callback.error(SpeechRecognizer.ERROR_CLIENT) }
            return
        }
        delegate = recognizer
        recognizer.setRecognitionListener(Forward(callback))
        recognizer.startListening(intent)
    }

    override fun onStopListening(callback: Callback) {
        delegate?.stopListening()
    }

    override fun onCancel(callback: Callback) {
        delegate?.cancel()
        release()
    }

    override fun onDestroy() {
        release()
        super.onDestroy()
    }

    private fun release() {
        try {
            delegate?.destroy()
        } catch (e: Exception) {
        }
        delegate = null
    }

    /** Another app's RecognitionService: a preferred one, else the first. */
    private fun pickTarget(): ComponentName? {
        val services = try {
            packageManager.queryIntentServices(
                Intent(SERVICE_INTERFACE),
                PackageManager.MATCH_ALL,
            )
        } catch (e: Exception) {
            emptyList()
        }
        val others = services.mapNotNull { it.serviceInfo }
            .filter { it.packageName != packageName }
            .map { ComponentName(it.packageName, it.name) }
        for (pkg in preferred) {
            others.firstOrNull { it.packageName == pkg }?.let { return it }
        }
        return others.firstOrNull()
    }

    private inline fun safe(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
        }
    }

    private inner class Forward(private val cb: Callback) : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = safe { cb.readyForSpeech(params ?: Bundle()) }
        override fun onBeginningOfSpeech() = safe { cb.beginningOfSpeech() }
        override fun onRmsChanged(rmsdB: Float) = safe { cb.rmsChanged(rmsdB) }
        override fun onBufferReceived(buffer: ByteArray?) = safe { if (buffer != null) cb.bufferReceived(buffer) }
        override fun onEndOfSpeech() = safe { cb.endOfSpeech() }
        override fun onError(error: Int) {
            safe { cb.error(error) }
            release()
        }
        override fun onResults(results: Bundle?) {
            safe { cb.results(results ?: Bundle()) }
            release()
        }
        override fun onPartialResults(partialResults: Bundle?) = safe { cb.partialResults(partialResults ?: Bundle()) }
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onSegmentResults(segmentResults: Bundle) {
            if (Build.VERSION.SDK_INT >= 33) safe { cb.segmentResults(segmentResults) }
        }

        override fun onEndOfSegmentedSession() {
            if (Build.VERSION.SDK_INT >= 33) safe { cb.endOfSegmentedSession() }
        }
    }
}
