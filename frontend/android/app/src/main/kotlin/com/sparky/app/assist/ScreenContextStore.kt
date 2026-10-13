package com.sparky.app.assist

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.io.File
import java.io.FileOutputStream

/**
 * What the system handed the assistant session about the screen behind it:
 * the view structure (text, app, URL) and, if the user allowed it, a
 * screenshot. Kept in memory for the current session only and handed to
 * Dart only when the user taps "Share screen with sparky".
 */
object ScreenContextStore {
    private const val SCREENSHOT_MAX_SIDE = 1600
    private const val JPEG_QUALITY = 82

    private val main = Handler(Looper.getMainLooper())

    /** Bumped on every new session; late callbacks of an old one are dropped. */
    @Volatile private var session = 0
    private var expecting = false
    private var structureDone = false
    private var screenshotDone = false
    private var nodes: List<Map<String, Any>> = emptyList()
    private var packageName: String? = null
    private var appLabel: String? = null
    private var url: String? = null
    private var screenshot: File? = null

    /** Size of the screen the screenshot shows (before it was scaled down). */
    private var screenWidth = 0
    private var screenHeight = 0

    /** A session started: forget the previous screen. */
    fun begin(context: Context, withAssist: Boolean): Int {
        session++
        expecting = withAssist
        structureDone = !withAssist
        screenshotDone = !withAssist
        nodes = emptyList()
        packageName = null
        appLabel = null
        url = null
        screenshot?.delete()
        screenshot = null
        screenWidth = 0
        screenHeight = 0
        // Old screenshots of crashed sessions.
        dir(context).listFiles()?.forEach { it.delete() }
        return session
    }

    /** No session (opened from the app or an ASSIST intent): nothing to share. */
    fun clear(context: Context) {
        begin(context, false)
    }

    val available: Boolean get() = expecting

    fun onStructure(
        context: Context,
        id: Int,
        extracted: ScreenTextExtractor.Result?,
        pkg: String?,
        webUri: String?,
    ) {
        if (id != session) return
        nodes = extracted?.nodes ?: emptyList()
        packageName = pkg
        appLabel = pkg?.let { label(context, it) }
        url = webUri ?: extracted?.webDomain?.let { "${AssistProtocol.HTTPS_PREFIX}$it" }
        structureDone = true
    }

    fun onScreenshot(context: Context, id: Int, bitmap: Bitmap?) {
        if (id != session) return
        if (bitmap == null) {
            screenshotDone = true
            return
        }
        screenWidth = bitmap.width
        screenHeight = bitmap.height
        // A software copy now (the system may reuse the bitmap), the JPEG on
        // a worker thread; the result lands back on main.
        val scaled = try {
            scale(bitmap)
        } catch (e: Exception) {
            screenshotDone = true
            return
        }
        Thread {
            val file = try {
                val f = File(dir(context), "${AssistProtocol.SCREENSHOT_PREFIX}${System.currentTimeMillis()}.jpg")
                FileOutputStream(f).use { scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it) }
                f
            } catch (e: Exception) {
                null
            }
            main.post {
                if (id == session) {
                    screenshot = file
                    screenshotDone = true
                } else {
                    file?.delete()
                }
            }
        }.start()
    }

    /**
     * The shared screen for Dart, waiting up to [waitMs] for callbacks that
     * have not arrived yet. Runs [done] on the main thread.
     */
    fun snapshot(waitMs: Long, done: (Map<String, Any?>) -> Unit) {
        val id = session
        val deadline = SystemClock.uptimeMillis() + waitMs
        fun check() {
            if (id != session) return done(empty())
            if ((structureDone && screenshotDone) || SystemClock.uptimeMillis() >= deadline) {
                done(current())
            } else {
                main.postDelayed({ check() }, AssistProtocol.SCREEN_POLL_MS)
            }
        }
        check()
    }

    private fun empty(): Map<String, Any?> = mapOf(AssistProtocol.AVAILABLE to false)

    private fun current(): Map<String, Any?> = mapOf(
        AssistProtocol.AVAILABLE to expecting,
        AssistProtocol.NODES to nodes,
        AssistProtocol.PACKAGE to packageName,
        AssistProtocol.APP to appLabel,
        AssistProtocol.URL to url,
        AssistProtocol.SCREENSHOT to screenshot?.absolutePath,
        AssistProtocol.STRUCTURE_ARRIVED to structureDone,
        AssistProtocol.SCREEN_WIDTH to screenWidth,
        AssistProtocol.SCREEN_HEIGHT to screenHeight,
    )

    private fun dir(context: Context): File =
        File(context.cacheDir, AssistProtocol.CACHE_DIR).apply { mkdirs() }

    private fun label(context: Context, pkg: String): String? = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        null
    } catch (e: Exception) {
        null
    }

    private fun scale(source: Bitmap): Bitmap {
        val b = if (source.config == Bitmap.Config.ARGB_8888 || source.config == Bitmap.Config.RGB_565) {
            source
        } else {
            source.copy(Bitmap.Config.ARGB_8888, false)
        }
        val side = maxOf(b.width, b.height)
        if (side <= SCREENSHOT_MAX_SIDE) return if (b === source) b.copy(b.config ?: Bitmap.Config.ARGB_8888, false) else b
        val f = SCREENSHOT_MAX_SIDE.toFloat() / side
        return Bitmap.createScaledBitmap(b, (b.width * f).toInt(), (b.height * f).toInt(), true)
    }
}
