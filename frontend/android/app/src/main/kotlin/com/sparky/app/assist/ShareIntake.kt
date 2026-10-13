package com.sparky.app.assist

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * "Ask sparky" in the Android share sheet (ACTION_SEND / SEND_MULTIPLE):
 * copies what was shared into the app's cache while the read grant lasts,
 * so the overlay can attach it like a picked file. Runs off the main thread.
 */
object ShareIntake {
    private const val BUFFER = 64 * 1024
    private const val FALLBACK_NAME = "shared"
    private val unsafe = Regex("[^A-Za-z0-9._ -]")

    fun isShare(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE

    /** The shared text and copied files as the `onShared` map for Dart. */
    fun read(context: Context, intent: Intent): Map<String, Any?> {
        val dir = File(context.cacheDir, AssistProtocol.SHARE_DIR).apply { mkdirs() }
        // One share at a time: the previous one's copies go.
        dir.listFiles()?.forEach { it.delete() }
        val files = ArrayList<Map<String, Any>>()
        var skipped = 0
        for ((i, uri) in uris(intent).withIndex()) {
            if (files.size >= AssistProtocol.SHARE_MAX_FILES) {
                skipped++
                continue
            }
            val copied = copy(context, uri, dir, i)
            if (copied == null) skipped++ else files.add(copied)
        }
        return mapOf(
            AssistProtocol.SHARED_TEXT to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
            AssistProtocol.SHARED_SUBJECT to intent.getStringExtra(Intent.EXTRA_SUBJECT),
            AssistProtocol.SHARED_FILES to files,
            AssistProtocol.SHARED_SKIPPED to skipped,
        )
    }

    @Suppress("DEPRECATION")
    private fun uris(intent: Intent): List<Uri> {
        val out = LinkedHashSet<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list: List<Uri>? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            list?.let { out.addAll(it) }
        } else {
            val one: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            one?.let { out.add(it) }
        }
        val clip: ClipData? = intent.clipData
        if (clip != null) for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { out.add(it) }
        return out.toList()
    }

    private fun copy(context: Context, uri: Uri, dir: File, index: Int): Map<String, Any>? {
        return try {
            val resolver = context.contentResolver
            var name: String? = null
            var size = -1L
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
                ?.use { c ->
                    if (c.moveToFirst()) {
                        val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val s = c.getColumnIndex(OpenableColumns.SIZE)
                        if (n >= 0) name = c.getString(n)
                        if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
                    }
                }
            if (size > AssistProtocol.SHARE_MAX_BYTES) return null
            val clean = (name ?: uri.lastPathSegment ?: FALLBACK_NAME).replace(unsafe, "_").take(120)
            val file = File(dir, "$index-$clean")
            var total = 0L
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(file).use { out ->
                    val buf = ByteArray(BUFFER)
                    while (true) {
                        val r = input.read(buf)
                        if (r < 0) break
                        total += r
                        if (total > AssistProtocol.SHARE_MAX_BYTES) throw IllegalStateException("too big")
                        out.write(buf, 0, r)
                    }
                }
            } ?: return null
            mapOf(
                AssistProtocol.FILE_PATH to file.absolutePath,
                AssistProtocol.FILE_NAME to clean,
                AssistProtocol.FILE_SIZE to total,
            )
        } catch (e: Exception) {
            Log.w(AssistProtocol.LOG_TAG, "could not read a shared item", e)
            dir.listFiles { f -> f.name.startsWith("$index-") }?.forEach { it.delete() }
            null
        }
    }
}
