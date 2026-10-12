package com.sparky.app.assist

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine

/**
 * The overlay window: a translucent, animation-free activity in its own task
 * that shows the pre-warmed assist engine on top of whatever app is open.
 * Started by the assistant session (power button), by ASSIST / VOICE_COMMAND
 * intents, or by "Try it" in the app's settings.
 */
class AssistActivity : FlutterActivity() {
    companion object {
        const val EXTRA_SOURCE = "sparky.assist.source"
        const val EXTRA_T0 = "sparky.assist.t0"
        const val EXTRA_SCREEN = "sparky.assist.screen"

        fun intent(context: Context, source: String, t0: Long, screen: Boolean): Intent =
            Intent(context, AssistActivity::class.java)
                .putExtra(EXTRA_SOURCE, source)
                .putExtra(EXTRA_T0, t0)
                .putExtra(EXTRA_SCREEN, screen)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
    }

    private var closing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // The engine must be in the cache before FlutterActivity looks it up.
        AssistEngine.ensure(this)
        AssistEngine.attach(this)
        announce(intent)
        super.onCreate(savedInstanceState)
        noAnimation()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        closing = false
        announce(intent)
    }

    /** Tells Dart a new overlay starts (resets it) before the view draws. */
    private fun announce(intent: Intent) {
        val source = intent.getStringExtra(EXTRA_SOURCE) ?: AssistProtocol.SOURCE_ASSIST
        val t0 = intent.getLongExtra(EXTRA_T0, SystemClock.uptimeMillis())
        val screen = intent.getBooleanExtra(EXTRA_SCREEN, false)
        // Opened without a session (ASSIST intent, Try it): no screen to share.
        if (source != AssistProtocol.SOURCE_SESSION) ScreenContextStore.clear(this)
        AssistEngine.show(source, t0, screen)
    }

    override fun getCachedEngineId(): String = AssistEngine.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    // Plugins are registered once, when the engine is created.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {}

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        AssistEngine.uiDisplayed()
    }

    // Home or Recents: the overlay goes away, like the system assistant.
    // (Picking a photo does not count: that is not a user leave.)
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        close()
    }

    fun close() {
        if (closing || isFinishing) return
        closing = true
        finish()
    }

    override fun finish() {
        super.finish()
        noAnimation()
        SparkySession.finishCurrent()
    }

    override fun onDestroy() {
        AssistEngine.detach(this)
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun noAnimation() {
        if (Build.VERSION.SDK_INT >= 34) {
            overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, 0, 0)
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            overridePendingTransition(0, 0)
        }
    }
}
