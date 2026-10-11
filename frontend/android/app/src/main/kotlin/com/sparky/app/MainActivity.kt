package com.sparky.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.util.Base64
import androidx.core.content.FileProvider
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import androidx.lifecycle.lifecycleScope
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val channelName = "app/browsers"
    private val authChannelName = "app/auth"
    private val iconPx = 96
    private val maxDataUrlChars = 100_000

    // Back on the last screen sends the app to the background instead of
    // finishing the activity, so a running answer (e.g. a round table) keeps
    // streaming and can notify when done.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, authChannelName)
            .setMethodCallHandler { call, result -> handleAuth(call, result) }
    }

    // ---- "Continue with Google" (Credential Manager) ----------------------

    private fun handleAuth(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "googleIdToken" -> {
                val clientId = call.argument<String>("serverClientId")
                if (clientId.isNullOrEmpty()) {
                    result.error("bad_request", "serverClientId is required", null)
                    return
                }
                googleIdToken(clientId, call.argument<String>("mode") == "auto", result)
            }
            "googleSignOut" -> lifecycleScope.launch {
                try {
                    CredentialManager.create(this@MainActivity)
                        .clearCredentialState(ClearCredentialStateRequest())
                } catch (e: Exception) {
                    // Nothing to clear is fine.
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * An ID token for [serverClientId] (the server's WEB client id).
     * Button: the system "Sign in with Google" sheet (any account on the
     * device, can add one). Auto: only accounts that already authorized this
     * app, picked silently when there is exactly one.
     */
    private fun googleIdToken(serverClientId: String, auto: Boolean, result: MethodChannel.Result) {
        val option = if (auto) {
            GetGoogleIdOption.Builder()
                .setServerClientId(serverClientId)
                .setFilterByAuthorizedAccounts(true)
                .setAutoSelectEnabled(true)
                .build()
        } else {
            GetSignInWithGoogleOption.Builder(serverClientId).build()
        }
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        lifecycleScope.launch {
            try {
                val response = CredentialManager.create(this@MainActivity)
                    .getCredential(this@MainActivity, request)
                val credential = response.credential
                if (credential is CustomCredential &&
                    credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
                ) {
                    result.success(GoogleIdTokenCredential.createFrom(credential.data).idToken)
                } else {
                    result.error("failed", "Unexpected credential type", null)
                }
            } catch (e: GetCredentialCancellationException) {
                result.error("cancelled", e.message, null)
            } catch (e: NoCredentialException) {
                result.error("no_account", e.message, null)
            } catch (e: GoogleIdTokenParsingException) {
                result.error("failed", "Google returned an unreadable credential", null)
            } catch (e: GetCredentialException) {
                result.error("failed", "${e.type}: ${e.message ?: ""}".take(300), null)
            } catch (e: Exception) {
                result.error("failed", (e.message ?: e.toString()).take(300), null)
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listBrowsers" -> Thread {
                val out = try {
                    listBrowsers()
                } catch (e: Exception) {
                    emptyList()
                }
                runOnUiThread { result.success(out) }
            }.start()
            "openUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.success(false)
                } else {
                    result.success(openUrl(url, call.argument<String>("package")))
                }
            }
            "openHtml" -> {
                val html = call.argument<String>("html") ?: ""
                val title = call.argument<String>("title") ?: ""
                result.success(openHtml(html, title, call.argument<String>("package")))
            }
            else -> result.notImplemented()
        }
    }

    private fun browsableIntent(): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com"))
            .addCategory(Intent.CATEGORY_BROWSABLE)

    private fun listBrowsers(): List<Map<String, Any?>> {
        val pm = packageManager
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
        startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }

    private fun openUrl(url: String, pkg: String?): Boolean {
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
            val dir = File(cacheDir, "html").apply { mkdirs() }
            val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
            dir.listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
            val safe = title.replace(Regex("[^A-Za-z0-9_-]+"), "-").trim('-').take(40)
                .ifEmpty { "page" }
            val file = File(dir, "$safe-${System.currentTimeMillis()}.html")
            file.writeText(html, Charsets.UTF_8)
            FileProvider.getUriForFile(this, "$packageName.files", file)
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
                    grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
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
