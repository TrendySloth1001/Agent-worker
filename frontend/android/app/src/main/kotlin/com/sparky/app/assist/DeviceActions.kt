package com.sparky.app.assist

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Runs a device action the user confirmed on a card in the chat or the
 * overlay ('app/actions'). Nothing here runs without that tap: the card
 * calls [AssistProtocol.ACTIONS_RUN] only from its Confirm button. Calls are
 * never placed (ACTION_DIAL only fills the dialer) and messages are never
 * sent (the user presses send in their app).
 *
 * Keys mirror DeviceActionWire in lib/core/constants/device_actions.dart.
 * [onLeave] runs after an action that opens another app (the overlay closes
 * so that app is in front).
 */
class DeviceActions(
    private val context: Context,
    private val onLeave: (() -> Unit)? = null,
) : MethodChannel.MethodCallHandler {
    private companion object {
        const val TAG = AssistProtocol.LOG_TAG

        // Action types
        const val ALARM = "alarm"
        const val TIMER = "timer"
        const val EVENT = "event"
        const val APP = "app"
        const val URL = "url"
        const val DIAL = "dial"
        const val SMS = "sms"
        const val EMAIL = "email"
        const val WHATSAPP = "whatsapp"
        const val SHARE = "share"
        const val NAVIGATE = "navigate"

        // Argument keys
        const val HOUR = "hour"
        const val MINUTE = "minute"
        const val LABEL = "label"
        const val SECONDS = "seconds"
        const val TITLE = "title"
        const val BEGIN = "beginMs"
        const val END = "endMs"
        const val ALL_DAY = "allDay"
        const val LOCATION = "location"
        const val NOTES = "notes"
        const val NAME = "name"
        const val ADDRESS = "url"
        const val NUMBER = "number"
        const val BODY = "body"
        const val TO = "to"
        const val SUBJECT = "subject"
        const val TEXT = "text"
        const val DESTINATION = "destination"
        const val TRAVEL = "travel"

        const val WHATSAPP_PACKAGE = "com.whatsapp"
        const val WHATSAPP_LINK = "https://wa.me/"
        const val MAPS_PACKAGE = "com.google.android.apps.maps"
        const val NAV_PREFIX = "google.navigation:q="
        const val NAV_MODE = "&mode="
        const val GEO_PREFIX = "geo:0,0?q="
        const val TEL = "tel"
        const val SMSTO = "smsto"
        const val MAILTO = "mailto:"
        const val SMS_BODY = "sms_body"
        const val TEXT_PLAIN = "text/plain"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != AssistProtocol.ACTIONS_RUN) return result.notImplemented()
        val args = call.arguments as? Map<*, *> ?: return result.success(AssistProtocol.RESULT_FAILED)
        result.success(run(args))
    }

    private fun run(a: Map<*, *>): String {
        fun s(k: String): String? = (a[k] as? String)?.trim()?.takeIf { it.isNotEmpty() }
        fun n(k: String): Long? = (a[k] as? Number)?.toLong()
        return try {
            when (a[AssistProtocol.ACTION_TYPE]) {
                ALARM -> start(
                    Intent(AlarmClock.ACTION_SET_ALARM)
                        .putExtra(AlarmClock.EXTRA_HOUR, (n(HOUR) ?: return AssistProtocol.RESULT_FAILED).toInt())
                        .putExtra(AlarmClock.EXTRA_MINUTES, (n(MINUTE) ?: 0L).toInt())
                        .apply { s(LABEL)?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it) } }
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, true),
                    leaves = false,
                )
                TIMER -> start(
                    Intent(AlarmClock.ACTION_SET_TIMER)
                        .putExtra(AlarmClock.EXTRA_LENGTH, (n(SECONDS) ?: return AssistProtocol.RESULT_FAILED).toInt())
                        .apply { s(LABEL)?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it) } }
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, true),
                    leaves = false,
                )
                EVENT -> start(
                    Intent(Intent.ACTION_INSERT)
                        .setData(CalendarContract.Events.CONTENT_URI)
                        .putExtra(CalendarContract.Events.TITLE, s(TITLE) ?: "")
                        .apply {
                            n(BEGIN)?.let { putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, it) }
                            n(END)?.let { putExtra(CalendarContract.EXTRA_EVENT_END_TIME, it) }
                            if (a[ALL_DAY] == true) putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true)
                            s(LOCATION)?.let { putExtra(CalendarContract.Events.EVENT_LOCATION, it) }
                            s(NOTES)?.let { putExtra(CalendarContract.Events.DESCRIPTION, it) }
                        },
                )
                APP -> openApp(s(NAME) ?: return AssistProtocol.RESULT_FAILED)
                URL -> {
                    val url = s(ADDRESS) ?: return AssistProtocol.RESULT_FAILED
                    val uri = Uri.parse(url)
                    if (uri.scheme != "https" && uri.scheme != "http") return AssistProtocol.RESULT_FAILED
                    start(Intent(Intent.ACTION_VIEW, uri))
                }
                DIAL -> start(Intent(Intent.ACTION_DIAL, Uri.fromParts(TEL, s(NUMBER) ?: "", null)))
                SMS -> start(
                    Intent(Intent.ACTION_SENDTO, Uri.fromParts(SMSTO, s(NUMBER) ?: "", null))
                        .apply { s(BODY)?.let { putExtra(SMS_BODY, it) } },
                )
                EMAIL -> start(
                    Intent(Intent.ACTION_SENDTO, Uri.parse(MAILTO))
                        .apply {
                            s(TO)?.let { putExtra(Intent.EXTRA_EMAIL, arrayOf(it)) }
                            s(SUBJECT)?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                            s(BODY)?.let { putExtra(Intent.EXTRA_TEXT, it) }
                        },
                )
                WHATSAPP -> whatsapp(s(NUMBER), s(TEXT) ?: "")
                SHARE -> start(
                    Intent.createChooser(
                        Intent(Intent.ACTION_SEND).setType(TEXT_PLAIN).putExtra(Intent.EXTRA_TEXT, s(TEXT) ?: ""),
                        null,
                    ),
                )
                NAVIGATE -> navigate(s(DESTINATION) ?: return AssistProtocol.RESULT_FAILED, s(TRAVEL))
                else -> AssistProtocol.RESULT_FAILED
            }
        } catch (e: Exception) {
            Log.w(TAG, "device action failed", e)
            AssistProtocol.RESULT_FAILED
        }
    }

    private fun start(intent: Intent, leaves: Boolean = true): String = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        if (leaves) onLeave?.invoke()
        AssistProtocol.RESULT_OK
    } catch (e: ActivityNotFoundException) {
        AssistProtocol.RESULT_UNAVAILABLE
    } catch (e: SecurityException) {
        AssistProtocol.RESULT_UNAVAILABLE
    }

    /** The launcher app whose name best matches [name]: exact, prefix, then contains. */
    private fun openApp(name: String): String {
        val pm = context.packageManager
        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = pm.queryIntentActivities(main, PackageManager.MATCH_ALL).map {
            it.loadLabel(pm).toString().trim() to it.activityInfo.packageName
        }
        val want = name.lowercase()
        val pick = apps.firstOrNull { it.first.lowercase() == want }
            ?: apps.firstOrNull { it.first.lowercase().startsWith(want) }
            ?: apps.firstOrNull { it.first.lowercase().contains(want) }
            ?: apps.firstOrNull { it.second.lowercase().contains(want.replace(" ", "")) }
            ?: return AssistProtocol.RESULT_NOT_FOUND
        val launch = pm.getLaunchIntentForPackage(pick.second) ?: return AssistProtocol.RESULT_NOT_FOUND
        return start(launch)
    }

    private fun whatsapp(number: String?, text: String): String {
        val digits = number?.filter { it.isDigit() }.orEmpty()
        if (digits.isNotEmpty()) {
            val link = Uri.parse("$WHATSAPP_LINK$digits").buildUpon().appendQueryParameter(TEXT, text).build()
            return start(Intent(Intent.ACTION_VIEW, link))
        }
        val send = Intent(Intent.ACTION_SEND).setType(TEXT_PLAIN).putExtra(Intent.EXTRA_TEXT, text)
        val direct = start(Intent(send).setPackage(WHATSAPP_PACKAGE))
        return if (direct == AssistProtocol.RESULT_OK) direct else start(Intent.createChooser(send, null))
    }

    private fun navigate(destination: String, travel: String?): String {
        val q = Uri.encode(destination)
        val mode = travel?.firstOrNull()?.lowercaseChar()?.takeIf { it in "dwb" }
        val nav = Intent(Intent.ACTION_VIEW, Uri.parse("$NAV_PREFIX$q${mode?.let { "$NAV_MODE$it" } ?: ""}"))
            .setPackage(MAPS_PACKAGE)
        val r = start(nav)
        return if (r == AssistProtocol.RESULT_OK) r else start(Intent(Intent.ACTION_VIEW, Uri.parse("$GEO_PREFIX$q")))
    }
}
