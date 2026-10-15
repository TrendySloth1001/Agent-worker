package com.sparky.app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * The 'app/browsers' channel: list browsers, open links and generated HTML
 * pages. Shared by the app (MainActivity) and the assistant overlay engine.
 */
class BrowsersHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    private val iconPx = 96
    private val maxDataUrlChars = 100_000
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listBrowsers" -> Thread {
                val out = try {
                    listBrowsers()
                } catch (e: Exception) {
                    emptyList()
                }
                main.post { result.success(out) }
            }.start()
            "openUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.success(false)
                } else {
                    result.success(openUrl(url, call.argument<String>("package")))
                }
            }
            "resolvesUrl" -> {
                val url = call.argument<String>("url")
                result.success(if (url.isNullOrEmpty()) emptyList<String>() else resolvesUrl(url))
            }
            "openHtml" -> {
                val html = call.argument<String>("html") ?: ""
                val title = call.argument<String>("title") ?: ""
                result.success(openHtml(html, title, call.argument<String>("package")))
            }
            "openFile" -> {
                val path = call.argument<String>("path")
                val mime = call.argument<String>("mime") ?: "*/*"
                result.success(if (path.isNullOrEmpty()) false else openFile(path, mime))
            }
            else -> result.notImplemented()
        }
    }

    /**
     * ACTION_VIEW for a file the app cached under cache/previews: "Open
     * with…" in the file preview. Paths outside that folder are refused.
     */
    private fun openFile(path: String, mime: String): Boolean {
        return try {
            val root = File(context.cacheDir, "previews").canonicalFile
            val file = File(path).canonicalFile
            if (!file.path.startsWith(root.path + File.separator) || !file.isFile) return false
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
            val view = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val chooser = Intent.createChooser(view, null)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            start(chooser)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Packages with an activity for [url] itself (e.g. the GitHub app for
     * github.com/login/oauth/authorize), the one that would open it first.
     */
    private fun resolvesUrl(url: String): List<String> = try {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)
        val out = LinkedHashSet<String>()
        pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName
            ?.takeIf { it != "android" }
            ?.let { out.add(it) }
        for (info in pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)) {
            info.activityInfo?.packageName?.let { out.add(it) }
        }
        out.toList()
    } catch (e: Exception) {
        emptyList()
    }

    private fun browsableIntent(): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com"))
            .addCategory(Intent.CATEGORY_BROWSABLE)

    private fun listBrowsers(): List<Map<String, Any?>> {
        val pm = context.packageManager
        val intent = browsableIntent()
        val found: List<ResolveInfo> =
            pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
        val defaultPkg = pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
            ?.activityInfo?.packageName
        val seen = HashSet<String>()
        val list = ArrayList<Map<String, Any?>>()
        for (info in found) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (!seen.add(pkg)) continue
            list.add(
                mapOf(
                    "package" to pkg,
                    "label" to info.loadLabel(pm).toString(),
                    "iconPng" to iconBase64(info.loadIcon(pm)),
                    "isDefault" to (pkg == defaultPkg),
                ),
            )
        }
        list.sortWith(
            compareByDescending<Map<String, Any?>> { it["isDefault"] as Boolean }
                .thenBy { (it["label"] as String).lowercase() },
        )
        return list
    }

    private fun iconBase64(d: Drawable): String? = try {
        val bmp = if (d is BitmapDrawable && d.bitmap.width == iconPx && d.bitmap.height == iconPx) {
            d.bitmap
        } else {
            val b = Bitmap.createBitmap(iconPx, iconPx, Bitmap.Config.ARGB_8888)
            val c = Canvas(b)
            d.setBounds(0, 0, iconPx, iconPx)
            d.draw(c)
            b
        }
        val os = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, os)
        Base64.encodeToString(os.toByteArray(), Base64.NO_WRAP)
    } catch (e: Exception) {
        null
    }

    private fun start(intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }

    fun openUrl(url: String, pkg: String?): Boolean {
        val uri = Uri.parse(url)
        if (!pkg.isNullOrEmpty()) {
            val targeted = Intent(Intent.ACTION_VIEW, uri)
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .setPackage(pkg)
            if (start(targeted)) return true
        }
        val plain = Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
        if (start(plain)) return true
        // Chosen browser is gone and there is no default: let the user pick.
        return start(Intent.createChooser(Intent(Intent.ACTION_VIEW, uri), null))
    }

    private fun openHtml(html: String, title: String, pkg: String?): Boolean {
        val uri = try {
            val dir = File(context.cacheDir, "html").apply { mkdirs() }
            val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
            dir.listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
            val safe = title.replace(Regex("[^A-Za-z0-9_-]+"), "-").trim('-').take(40)
                .ifEmpty { "page" }
            val file = File(dir, "$safe-${System.currentTimeMillis()}.html")
            file.writeText(html, Charsets.UTF_8)
            FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        } catch (e: Exception) {
            null
        }
        if (uri != null) {
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "text/html")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (!pkg.isNullOrEmpty()) {
                intent.setPackage(pkg)
                try {
                    context.grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (e: Exception) {
                }
            }
            if (start(intent)) return true
        }
        // Fallback: a data: URL for small pages.
        if (html.length <= maxDataUrlChars) {
            val b64 = Base64.encodeToString(html.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
            return openUrl("data:text/html;charset=utf-8;base64,$b64", pkg)
        }
        return false
    }
}
