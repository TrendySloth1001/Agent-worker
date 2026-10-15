package com.sparky.app.assist

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.util.Log
import com.sparky.app.BrowsersHandler
import com.sparky.app.PhoneHintsHandler
import com.sparky.app.MainActivity
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * The overlay's own Flutter engine, started ahead of time (when the system
 * binds the assistant service) so holding the power button only has to
 * attach a view to an engine whose Dart UI is already running. Runs the
 * `assistMain` entrypoint; separate from the app's engine, so MainActivity's
 * channels (links, auth, notifications) are untouched.
 */
object AssistEngine {
    const val ENGINE_ID = "sparky_assist"
    private const val TAG = AssistProtocol.LOG_TAG
    private const val LIBRARY = "package:app/assist/assist_main.dart"
    private const val ENTRYPOINT = "assistMain"

    private var channel: MethodChannel? = null
    private var speech: TtsBridge? = null
    private var dartReady = false
    private var activity: WeakReference<AssistActivity>? = null

    /** The latest show request, until Dart has seen it. */
    private var lastShow: Map<String, Any?>? = null

    /** Shared content that arrived before Dart was listening. */
    private var pendingShared: Map<String, Any?>? = null
    private var showAt = 0L
    private var latencyLogged = true

    /** The running engine, starting it on the first call (main thread). */
    fun ensure(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val started = SystemClock.uptimeMillis()
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, AssistProtocol.CHANNEL)
        ch.setMethodCallHandler { call, result -> handle(app, call, result) }
        channel = ch
        dartReady = false
        // Links in answers open like they do in the app.
        MethodChannel(engine.dartExecutor.binaryMessenger, AssistProtocol.BROWSERS_CHANNEL)
            .setMethodCallHandler(BrowsersHandler(app))
        MethodChannel(engine.dartExecutor.binaryMessenger, PhoneHintsHandler.CHANNEL)
            .setMethodCallHandler(PhoneHintsHandler(app))
        // Confirmed action cards; one that opens another app closes the overlay.
        MethodChannel(engine.dartExecutor.binaryMessenger, AssistProtocol.ACTIONS_CHANNEL)
            .setMethodCallHandler(DeviceActions(app) { closeOverlay() })
        // Live mode reads answers aloud.
        val tts = MethodChannel(engine.dartExecutor.binaryMessenger, AssistProtocol.TTS_CHANNEL)
        speech = TtsBridge(app, tts).also { tts.setMethodCallHandler(it) }
        val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(bundle, LIBRARY, ENTRYPOINT),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        Log.i(TAG, "engine warmed in ${SystemClock.uptimeMillis() - started} ms")
        return engine
    }

    fun attach(a: AssistActivity) {
        activity = WeakReference(a)
    }

    fun detach(a: AssistActivity) {
        if (activity?.get() === a) activity = null
    }

    /**
     * A new overlay: [source] is session (power button), assist (ASSIST /
     * VOICE_COMMAND intent) or try (the app's "Try it"). [t0] is when the
     * request started (uptime ms), for the latency log.
     */
    fun show(source: String, t0: Long, screen: Boolean, mode: String? = null) {
        showAt = t0
        latencyLogged = false
        pendingShared = null
        val args = mapOf<String, Any?>(
            AssistProtocol.SOURCE to source,
            AssistProtocol.T0 to t0,
            AssistProtocol.SCREEN to screen,
            AssistProtocol.MODE to mode,
        )
        lastShow = args
        if (dartReady) channel?.invokeMethod(AssistProtocol.ON_SHOW, args)
    }

    /** What was shared to "Ask sparky", once it is copied (after [show]). */
    fun shared(payload: Map<String, Any?>) {
        if (dartReady) {
            channel?.invokeMethod(AssistProtocol.ON_SHARED, payload)
        } else {
            pendingShared = payload
        }
    }

    /** The overlay is no longer visible: silence Live mode at once. */
    fun hidden() {
        speech?.stopNow()
        if (dartReady) channel?.invokeMethod(AssistProtocol.ON_HIDE, null)
    }

    private fun closeOverlay() {
        activity?.get()?.close()
        SparkySession.finishCurrent()
    }

    /** The first frame of the overlay reached the screen. */
    fun uiDisplayed() {
        if (latencyLogged || showAt == 0L) return
        latencyLogged = true
        Log.i(TAG, "overlay visible ${SystemClock.uptimeMillis() - showAt} ms after show")
    }

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Dart is listening: hand over a show that came before it was.
            AssistProtocol.READY -> {
                dartReady = true
                result.success(lastShow)
                pendingShared?.let { payload ->
                    pendingShared = null
                    channel?.invokeMethod(AssistProtocol.ON_SHARED, payload)
                }
            }
            // Dart drew the pill for this show (its own clock, for the log).
            AssistProtocol.SHOWN -> {
                val ms = SystemClock.uptimeMillis() - showAt
                Log.i(TAG, "pill drawn ${ms} ms after show")
                result.success(ms.toInt())
            }
            AssistProtocol.CLOSE -> {
                activity?.get()?.close()
                SparkySession.finishCurrent()
                result.success(null)
            }
            AssistProtocol.SCREEN_CONTEXT -> ScreenContextStore.snapshot(AssistProtocol.SCREEN_WAIT_MS) { result.success(it) }
            AssistProtocol.OPEN_APP -> {
                result.success(openApp(context, call.argument<String>(AssistProtocol.LINK)))
                activity?.get()?.close()
                SparkySession.finishCurrent()
            }
            AssistProtocol.ASSISTANT_SETTINGS -> result.success(AssistantSetup.openAssistantSettings(context))
            AssistProtocol.ALLOW_MIC -> {
                result.success(openAppForMic(context))
                activity?.get()?.close()
                SparkySession.finishCurrent()
            }
            else -> result.notImplemented()
        }
    }

    /** Opens the app, which asks for the microphone in a normal window. */
    private fun openAppForMic(context: Context): Boolean = try {
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(AssistProtocol.EXTRA_REQUEST_MIC, true),
        )
        true
    } catch (e: Exception) {
        Log.w(TAG, "could not open the app for the microphone", e)
        false
    }

    /** Opens the app, optionally on a sparky:// link (e.g. a conversation). */
    private fun openApp(context: Context, link: String?): Boolean = try {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (link != null && link.startsWith(AssistProtocol.LINK_SCHEME_PREFIX)) {
            intent.action = Intent.ACTION_VIEW
            intent.data = Uri.parse(link)
        } else {
            intent.action = Intent.ACTION_MAIN
            intent.addCategory(Intent.CATEGORY_LAUNCHER)
        }
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        Log.w(TAG, "could not open the app", e)
        false
    }
}
