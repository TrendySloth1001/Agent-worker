package com.sparky.app

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.sparky.app.assist.AssistProtocol
import android.content.Intent
import android.os.Bundle
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import androidx.lifecycle.lifecycleScope
import com.sparky.app.assist.AssistantSetup
import com.sparky.app.assist.DeviceActions
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val channelName = "app/browsers"
    private val authChannelName = "app/auth"
    private val linksChannelName = "app/links"
    private var linksChannel: MethodChannel? = null
    private val assistant by lazy { AssistantSetup(this) }

    // A sparky:// link the app was opened with (cold start), until Dart asks.
    private var pendingLink: String? = null

    // Back on the last screen sends the app to the background instead of
    // finishing the activity, so a running answer (e.g. a round table) keeps
    // streaming and can notify when done.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before super: Dart may ask for the initial link as soon as it runs.
        if (savedInstanceState == null) pendingLink = appLink(intent)
        super.onCreate(savedInstanceState)
        maybeRequestMic(intent)
    }

    // The assistant overlay can't show Android's permission dialog (the system
    // closes it), so it opens the app with this extra and the app asks.
    private fun maybeRequestMic(intent: Intent?) {
        if (intent?.getBooleanExtra(AssistProtocol.EXTRA_REQUEST_MIC, false) != true) return
        intent.removeExtra(AssistProtocol.EXTRA_REQUEST_MIC)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            Toast.makeText(this, R.string.assistant_mic_ready, Toast.LENGTH_LONG).show()
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            AssistProtocol.REQUEST_MIC_CODE,
        )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != AssistProtocol.REQUEST_MIC_CODE) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        Toast.makeText(
            this,
            if (granted) R.string.assistant_mic_ready else R.string.assistant_mic_denied,
            Toast.LENGTH_LONG,
        ).show()
    }

    // singleTask: a sparky:// link while the app is alive lands here.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeRequestMic(intent)
        val link = appLink(intent) ?: return
        val channel = linksChannel
        if (channel == null) pendingLink = link else channel.invokeMethod("onLink", link)
    }

    /** The sparky:// URI of a VIEW intent (not when replayed from Recents). */
    private fun appLink(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        // The assistant's settings entry (Default apps > Digital assistant > gear).
        if (intent.component?.className == AssistantSetup.SETTINGS_ALIAS) return AssistantSetup.SETTINGS_LINK
        if (intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return if (uri.scheme == "sparky") uri.toString() else null
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (assistant.onActivityResult(requestCode)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        linksChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, linksChannelName)
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        // Hands out the cold-start link once.
                        "initialLink" -> {
                            result.success(pendingLink)
                            pendingLink = null
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(BrowsersHandler(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AssistantSetup.CHANNEL)
            .setMethodCallHandler(assistant)
        // Action cards in the chat (alarm, event, dial...) run only on Confirm.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AssistProtocol.ACTIONS_CHANNEL)
            .setMethodCallHandler(DeviceActions(this))
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
}
