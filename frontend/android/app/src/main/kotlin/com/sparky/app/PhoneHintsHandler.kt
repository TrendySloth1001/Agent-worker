package com.sparky.app

import android.content.Context
import android.telephony.TelephonyManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.TimeZone

/**
 * The 'app/phone_hints' channel: coarse facts about the phone that need no permission.
 * SIM country, network country (two-letter ISO, lower case, empty when unknown), the
 * time zone id and the locale. No location is read; the server turns these (with the
 * request's network address) into an approximate city / country, only when a question
 * needs it. Shared by the app (MainActivity) and the assistant overlay engine.
 */
class PhoneHintsHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hints" -> result.success(hints())
            else -> result.notImplemented()
        }
    }

    private fun hints(): Map<String, String> {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        // getSimCountryIso / getNetworkCountryIso need no permission; both can be empty (no SIM, Wi-Fi only).
        val sim = runCatching { tm?.simCountryIso }.getOrNull().orEmpty()
        val network = runCatching { tm?.networkCountryIso }.getOrNull().orEmpty()
        return mapOf(
            "simCountry" to sim,
            "networkCountry" to network,
            "timeZone" to TimeZone.getDefault().id,
            "locale" to Locale.getDefault().toLanguageTag(),
        )
    }

    companion object {
        const val CHANNEL = "app/phone_hints"
    }
}
