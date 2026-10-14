package com.sparky.app

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

/**
 * Crash reporting, native side (the `sparky/diagnostics` channel).
 *
 *  - [install] sets a default uncaught-exception handler that writes a small file synchronously and then
 *    chains to the previous handler (a dying process cannot do network; Dart uploads it on the next launch).
 *  - `takePending` hands Dart, once, the saved crash file and the previous process's exit reason from
 *    ActivityManager.getHistoricalProcessExitReasons (API 30+).
 *
 * Only the throwable class, a truncated message, a truncated stack and the thread name are saved. Never
 * user content: nothing but what the runtime put in the exception.
 */
class CrashRecorder(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "sparky/diagnostics"
        private const val FILE = "last_crash.json"
        private const val PREFS = "diagnostics"
        private const val KEY_LAST_EXIT_TS = "last_exit_ts"
        private const val MAX_MESSAGE = 300
        private const val MAX_STACK = 8 * 1024

        // Reasons worth reporting: our own crash or a system kill that points to a problem.
        private val REASONS = mapOf(
            ApplicationExitInfo.REASON_CRASH to "crash",
            ApplicationExitInfo.REASON_CRASH_NATIVE to "crash_native",
            ApplicationExitInfo.REASON_ANR to "anr",
            ApplicationExitInfo.REASON_LOW_MEMORY to "low_memory",
            ApplicationExitInfo.REASON_SIGNALED to "signaled",
        )

        private fun file(context: Context) = File(context.filesDir, "crash/$FILE")

        fun install(context: Context) {
            val app = context.applicationContext
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, error ->
                try {
                    write(app, thread, error)
                } catch (_: Throwable) {
                    // Never let the recorder hide the real crash.
                }
                previous?.uncaughtException(thread, error)
            }
        }

        private fun write(context: Context, thread: Thread, error: Throwable) {
            val json = JSONObject()
                .put("type", error.javaClass.simpleName)
                .put("message", (error.message ?: "").take(MAX_MESSAGE))
                .put("stack", stackOf(error).take(MAX_STACK))
                .put("thread", thread.name)
                .put("at", System.currentTimeMillis())
            val f = file(context)
            f.parentFile?.mkdirs()
            // Synchronous on purpose: the process is about to die.
            f.writeText(json.toString())
        }

        private fun stackOf(error: Throwable): String {
            val sb = StringBuilder()
            var t: Throwable? = error
            var depth = 0
            while (t != null && depth < 3) {
                if (depth > 0) sb.append("Caused by: ")
                sb.append(t.javaClass.name).append('\n')
                for (e in t.stackTrace.take(40)) sb.append("\tat ").append(e).append('\n')
                t = t.cause
                depth++
            }
            return sb.toString()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePending" -> result.success(takePending())
            "device" -> result.success(
                mapOf(
                    "model" to Build.MODEL,
                    "sdk" to Build.VERSION.SDK_INT,
                    "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                ),
            )
            else -> result.notImplemented()
        }
    }

    /** {crash: {...}?, exit: {...}?}; each part is returned once. */
    private fun takePending(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        val f = file(context)
        if (f.exists()) {
            try {
                val j = JSONObject(f.readText())
                out["crash"] = mapOf(
                    "type" to j.optString("type"),
                    "message" to j.optString("message"),
                    "stack" to j.optString("stack"),
                    "thread" to j.optString("thread"),
                    "at" to j.optLong("at"),
                )
            } catch (_: Throwable) {
            }
            f.delete()
        }
        lastExit()?.let { out["exit"] = it }
        return out
    }

    private fun lastExit(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val seen = prefs.getLong(KEY_LAST_EXIT_TS, 0L)
            val infos = am.getHistoricalProcessExitReasons(context.packageName, 0, 5)
            val latest = infos.maxByOrNull { it.timestamp } ?: return null
            if (latest.timestamp <= seen) return null
            prefs.edit().putLong(KEY_LAST_EXIT_TS, latest.timestamp).apply()
            val reason = REASONS[latest.reason] ?: return null
            mapOf(
                "reason" to reason,
                "description" to (latest.description ?: "").take(MAX_MESSAGE),
                "at" to latest.timestamp,
                "importance" to latest.importance,
            )
        } catch (_: Throwable) {
            null
        }
    }
}
