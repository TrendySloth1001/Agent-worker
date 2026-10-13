package com.sparky.app

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors

/**
 * In-app updates: the `sparky/updater` channel.
 *
 *  - canInstall: may this app install packages ("Install unknown apps")?
 *  - openInstallSettings: the system page where the user allows it.
 *  - install(path): checks the APK is signed like this app, then installs it
 *    through a PackageInstaller session. Answers with one of
 *    success | cancelled | signature_mismatch | failed.
 */
class Updater(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "sparky/updater"
        const val ACTION_STATUS = "com.sparky.app.UPDATE_STATUS"

        // The install in flight; the status receiver answers it.
        @Volatile
        private var pending: MethodChannel.Result? = null
        private val main = Handler(Looper.getMainLooper())

        fun deliver(status: String) {
            val result = pending ?: return
            pending = null
            main.post { result.success(status) }
        }
    }

    private val worker = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstall" -> result.success(canInstall())
            "openInstallSettings" -> {
                openInstallSettings()
                result.success(null)
            }
            "install" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("bad_request", "path is required", null)
                    return
                }
                install(path, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun openInstallSettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}"),
        )
        try {
            activity.startActivity(intent)
        } catch (e: Exception) {
            activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }
    }

    private fun install(path: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "An install is already running", null)
            return
        }
        pending = result
        worker.execute {
            val status = try {
                run(path)
            } catch (e: Exception) {
                "failed"
            }
            // "started" means the session is committed; the receiver answers.
            if (status != "started") deliver(status)
        }
    }

    private fun run(path: String): String {
        val file = File(path)
        if (!file.isFile) return "failed"
        when (checkSigner(file)) {
            Signer.OK -> {}
            Signer.MISMATCH -> return "signature_mismatch"
            Signer.BAD -> return "failed"
        }
        val installer = activity.packageManager.packageInstaller
        // Leftovers of an earlier attempt.
        installer.mySessions.forEach {
            try {
                installer.abandonSession(it.sessionId)
            } catch (e: Exception) {
            }
        }
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(activity.packageName)
        params.setSize(file.length())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            session.openWrite("base.apk", 0, file.length()).use { out ->
                FileInputStream(file).use { it.copyTo(out) }
                session.fsync(out)
            }
            val intent = Intent(activity, UpdaterReceiver::class.java).setAction(ACTION_STATUS)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pi = PendingIntent.getBroadcast(activity, id, intent, flags)
            session.commit(pi.intentSender)
        }
        return "started"
    }

    private enum class Signer { OK, MISMATCH, BAD }

    /** The archive must be this app, signed with the same certificate. */
    private fun checkSigner(file: File): Signer {
        val pm = activity.packageManager
        val own = activity.packageName
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val flags = PackageManager.GET_SIGNING_CERTIFICATES
            val archive = pm.getPackageArchiveInfo(file.path, flags) ?: return Signer.BAD
            if (archive.packageName != own) return Signer.BAD
            val theirs = archive.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet()
            val mine = pm.getPackageInfo(own, flags).signingInfo?.apkContentsSigners
                ?.map { it.toCharsString() }?.toSet()
            if (theirs.isNullOrEmpty() || mine.isNullOrEmpty()) Signer.BAD
            else if (theirs == mine) Signer.OK else Signer.MISMATCH
        } else {
            @Suppress("DEPRECATION")
            val flags = PackageManager.GET_SIGNATURES
            val archive: PackageInfo = pm.getPackageArchiveInfo(file.path, flags) ?: return Signer.BAD
            if (archive.packageName != own) return Signer.BAD
            @Suppress("DEPRECATION")
            val theirs = archive.signatures?.map { it.toCharsString() }?.toSet()
            @Suppress("DEPRECATION")
            val mine = pm.getPackageInfo(own, flags).signatures?.map { it.toCharsString() }?.toSet()
            if (theirs.isNullOrEmpty() || mine.isNullOrEmpty()) Signer.BAD
            else if (theirs == mine) Signer.OK else Signer.MISMATCH
        }
    }
}

/** Receives the PackageInstaller status of an update started by [Updater]. */
class UpdaterReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // The system wants the user's OK: open its confirmation.
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm == null) {
                    Updater.deliver("failed")
                    return
                }
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(confirm)
                } catch (e: Exception) {
                    Updater.deliver("failed")
                }
            }
            PackageInstaller.STATUS_SUCCESS -> Updater.deliver("success")
            PackageInstaller.STATUS_FAILURE_ABORTED -> Updater.deliver("cancelled")
            else -> Updater.deliver("failed")
        }
    }
}
