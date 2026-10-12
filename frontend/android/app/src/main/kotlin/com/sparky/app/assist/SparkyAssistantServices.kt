package com.sparky.app.assist

import android.app.assist.AssistContent
import android.app.assist.AssistStructure
import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.os.SystemClock
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.util.Log
import java.lang.ref.WeakReference

/**
 * The always-bound assistant service (sparky is the default digital
 * assistant). Its only job besides existing: start the overlay's Flutter
 * engine early so the power-button hold opens fast.
 */
class SparkyVoiceInteractionService : VoiceInteractionService() {
    override fun onReady() {
        super.onReady()
        try {
            AssistEngine.ensure(this)
        } catch (e: Exception) {
            // The overlay starts its engine itself if this failed.
            Log.w(AssistProtocol.LOG_TAG, "could not warm the engine", e)
        }
    }
}

/** Creates a [SparkySession] for each assistant invocation. */
class SparkySessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession = SparkySession(this)
}

/**
 * One assistant invocation. It draws no UI of its own (the session window
 * would sit above the overlay and eat its touches); it opens [AssistActivity]
 * and collects the screen context the system delivers, which stays on the
 * device until the user taps "Share screen with sparky".
 */
class SparkySession(context: Context) : VoiceInteractionSession(context) {
    companion object {
        private var current: WeakReference<SparkySession>? = null

        /** The overlay closed: end the system session too. */
        fun finishCurrent() {
            val s = current?.get() ?: return
            current = null
            try {
                s.finish()
            } catch (e: Exception) {
            }
        }
    }

    private var id = 0

    override fun onCreate() {
        super.onCreate()
        setUiEnabled(false)
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        val t0 = SystemClock.uptimeMillis()
        current = WeakReference(this)
        val withAssist = showFlags and SHOW_WITH_ASSIST != 0 || showFlags and SHOW_WITH_SCREENSHOT != 0
        id = ScreenContextStore.begin(context, withAssist)
        val intent = AssistActivity.intent(context, AssistProtocol.SOURCE_SESSION, t0, withAssist)
        try {
            startAssistantActivity(intent)
        } catch (e: Exception) {
            // Older or unusual builds: a plain start still works while the
            // session is showing.
            try {
                context.startActivity(intent)
            } catch (e2: Exception) {
                Log.w(AssistProtocol.LOG_TAG, "could not open the overlay", e2)
                finish()
            }
        }
    }

    // API 29+: one call per activity on screen; index 0 is the focused one.
    override fun onHandleAssist(state: AssistState) {
        if (state.index != 0) return
        handle(state.assistStructure, state.assistContent)
    }

    @Deprecated("Replaced by onHandleAssist(AssistState) on API 29+")
    @Suppress("DEPRECATION")
    override fun onHandleAssist(data: Bundle?, structure: AssistStructure?, content: AssistContent?) {
        handle(structure, content)
    }

    private fun handle(structure: AssistStructure?, content: AssistContent?) {
        val extracted = try {
            structure?.let { ScreenTextExtractor.extract(it) }
        } catch (e: Exception) {
            null
        }
        val pkg = structure?.activityComponent?.packageName
        val web = content?.webUri?.toString()?.takeIf { it.startsWith(AssistProtocol.WEB_SCHEME_PREFIX) }
        ScreenContextStore.onStructure(context, id, extracted, pkg, web)
    }

    override fun onHandleScreenshot(screenshot: Bitmap?) {
        ScreenContextStore.onScreenshot(context, id, screenshot)
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        super.onDestroy()
    }
}
