package com.sparky.app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Runs the intent behind a button of an action card ('sparky/intents').
 * The card calls [RUN] only from a tap; nothing here starts on its own, no
 * call is placed (ACTION_DIAL only fills the dialer), no message is sent and
 * nothing is paid (UPI apps open with the payment filled in).
 *
 * Only the actions, uri schemes, https hosts and extras listed below are
 * accepted; anything else is refused. Mirrors IntentCardPolicy in
 * lib/core/constants/intent_cards.dart and the server's cardLinks.ts.
 */
class CardIntents(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "sparky/intents"
        const val RUN = "run"
        const val INSTALLED = "installed"
        private const val TAG = "CardIntents"
        private const val OK = "ok"
        private const val UNAVAILABLE = "unavailable"
        private const val FAILED = "failed"

        private val SCHEMES = mapOf(
            "view" to setOf("https", "geo", "google.navigation", "upi"),
            "dial" to setOf("tel"),
            "sendto" to setOf("smsto", "mailto"),
        )
        private val ACTIONS = setOf("view", "dial", "sendto", "send", "set_alarm", "set_timer", "insert_event", "insert_contact", "launch")
        private val HOSTS = setOf(
            "www.google.com", "maps.google.com", "google.com", "play.google.com", "wa.me",
            "www.amazon.in", "amazon.in", "www.flipkart.com", "www.myntra.com", "www.swiggy.com",
            "www.zomato.com", "m.uber.com", "www.uber.com", "www.olacabs.com", "www.rapido.bike",
            "www.irctc.co.in", "www.ixigo.com", "www.makemytrip.com", "www.openstreetmap.org",
        )
        private val PACKAGE = Regex("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            INSTALLED -> {
                val packages = (call.argument<List<*>>("packages") ?: emptyList<Any>()).filterIsInstance<String>().filter { PACKAGE.matches(it) }
                result.success(packages.associateWith { installed(it) })
            }
            RUN -> result.success(run(call.arguments as? Map<*, *> ?: return result.success(FAILED)))
            else -> result.notImplemented()
        }
    }

    private fun run(a: Map<*, *>): String {
        val action = a["action"] as? String ?: return FAILED
        if (action !in ACTIONS) return FAILED
        val rawUri = (a["uri"] as? String)?.takeIf { it.isNotBlank() }
        val uri = if (rawUri != null) (allowedUri(action, rawUri) ?: return FAILED) else null
        val pkg = (a["package"] as? String)?.takeIf { PACKAGE.matches(it) }
        val chooser = a["chooser"] == true
        val x = a["extras"] as? Map<*, *> ?: emptyMap<Any, Any>()
        fun s(k: String): String? = (x[k] as? String)?.trim()?.takeIf { it.isNotEmpty() }
        fun n(k: String): Long? = (x[k] as? Number)?.toLong()
        return try {
            when (action) {
                "view" -> view(uri ?: return FAILED, pkg, chooser)
                "dial" -> start(Intent(Intent.ACTION_DIAL, uri ?: return FAILED))
                "sendto" -> {
                    val target = uri ?: return FAILED
                    start(
                        Intent(Intent.ACTION_SENDTO, target).apply {
                            s("body")?.let { putExtra(if (target.scheme == "smsto") "sms_body" else Intent.EXTRA_TEXT, it) }
                            s("subject")?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                        },
                    )
                }
                "send" -> start(
                    Intent.createChooser(
                        Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, s("text") ?: return FAILED),
                        null,
                    ),
                )
                // The system alarm / timer app opens with the values filled in (no SKIP_UI), so the user sees and confirms them.
                "set_alarm" -> start(
                    Intent(AlarmClock.ACTION_SET_ALARM)
                        .putExtra(AlarmClock.EXTRA_HOUR, (n("hour") ?: return FAILED).toInt())
                        .putExtra(AlarmClock.EXTRA_MINUTES, (n("minutes") ?: 0L).toInt())
                        .apply { s("message")?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it) } }
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, false),
                )
                "set_timer" -> start(
                    Intent(AlarmClock.ACTION_SET_TIMER)
                        .putExtra(AlarmClock.EXTRA_LENGTH, (n("length") ?: return FAILED).toInt())
                        .apply { s("message")?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it) } }
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, false),
                )
                "insert_event" -> start(
                    Intent(Intent.ACTION_INSERT)
                        .setData(CalendarContract.Events.CONTENT_URI)
                        .putExtra(CalendarContract.Events.TITLE, s("title") ?: "")
                        .apply {
                            n("beginMs")?.let { putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, it) }
                            n("endMs")?.let { putExtra(CalendarContract.EXTRA_EVENT_END_TIME, it) }
                            if (x["allDay"] == true) putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true)
                            s("location")?.let { putExtra(CalendarContract.Events.EVENT_LOCATION, it) }
                            s("description")?.let { putExtra(CalendarContract.Events.DESCRIPTION, it) }
                        },
                )
                "insert_contact" -> start(
                    Intent(ContactsContract.Intents.Insert.ACTION)
                        .setType(ContactsContract.RawContacts.CONTENT_TYPE)
                        .apply {
                            s("name")?.let { putExtra(ContactsContract.Intents.Insert.NAME, it) }
                            s("phone")?.let { putExtra(ContactsContract.Intents.Insert.PHONE, it) }
                            s("email")?.let { putExtra(ContactsContract.Intents.Insert.EMAIL, it) }
                        },
                )
                "launch" -> {
                    val p = pkg?.takeIf { installed(it) } ?: return UNAVAILABLE
                    start(context.packageManager.getLaunchIntentForPackage(p) ?: return UNAVAILABLE)
                }
                else -> FAILED
            }
        } catch (e: Exception) {
            Log.w(TAG, "card intent failed", e)
            FAILED
        }
    }

    /** [raw] as a Uri when its scheme (and, for https, its host) is allowed for [action]. */
    private fun allowedUri(action: String, raw: String): Uri? {
        if (raw.length > 2000) return null
        val u = Uri.parse(raw)
        val scheme = u.scheme?.lowercase() ?: return null
        if (SCHEMES[action]?.contains(scheme) != true) return null
        if (scheme == "https" && (u.host?.lowercase() !in HOSTS || u.userInfo != null)) return null
        return u
    }

    /** In [pkg]'s app when it is installed and handles the link, else wherever Android sends it. */
    private fun view(uri: Uri, pkg: String?, chooser: Boolean): String {
        fun build(withPackage: Boolean): Intent {
            val i = Intent(Intent.ACTION_VIEW, uri)
            if (withPackage && pkg != null) i.setPackage(pkg)
            return if (chooser) Intent.createChooser(i, null) else i
        }
        if (pkg != null && installed(pkg)) {
            val r = start(build(true))
            if (r == OK) return r
        }
        return start(build(false))
    }

    private fun start(intent: Intent): String = try {
        context.startActivity(intent)
        OK
    } catch (e: ActivityNotFoundException) {
        UNAVAILABLE
    } catch (e: SecurityException) {
        UNAVAILABLE
    }

    private fun installed(pkg: String): Boolean = try {
        context.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}
