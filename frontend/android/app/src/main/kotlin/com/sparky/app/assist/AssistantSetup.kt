package com.sparky.app.assist

import android.app.Activity
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's 'app/assistant' channel (Settings > Assistant): is sparky the
 * default digital assistant, ask to become it, open the system page, and
 * "Try it" (opens the overlay without a session).
 */
class AssistantSetup(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = AssistProtocol.SETUP_CHANNEL

        /** activity-alias the system opens from the assistant's gear icon. */
        const val SETTINGS_ALIAS = "com.sparky.app.AssistantSettings"
        const val SETTINGS_LINK = AssistProtocol.SETTINGS_LINK
        const val REQUEST_ROLE = 4711

        private const val VOICE_INTERACTION_SERVICE = "voice_interaction_service"
        private const val ASSISTANT = "assistant"
        private const val ASSIST_STRUCTURE = "assist_structure_enabled"
        private const val ASSIST_SCREENSHOT = "assist_screenshot_enabled"

        /** The system page where the digital assistant is chosen. */
        fun openAssistantSettings(context: Context): Boolean {
            val tries = buildList {
                add(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    add(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
                }
                add(Intent(Settings.ACTION_SETTINGS))
            }
            for (intent in tries) {
                try {
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    return true
                } catch (e: Exception) {
                }
            }
            return false
        }

        fun isDefault(context: Context): Boolean {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    val rm = context.getSystemService(RoleManager::class.java)
                    if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
                        return rm.isRoleHeld(RoleManager.ROLE_ASSISTANT)
                    }
                } catch (e: Exception) {
                }
            }
            val pkg = context.packageName
            fun owns(key: String): Boolean = try {
                Settings.Secure.getString(context.contentResolver, key)
                    ?.let { ComponentName.unflattenFromString(it)?.packageName == pkg } ?: false
            } catch (e: Exception) {
                false
            }
            return owns(VOICE_INTERACTION_SERVICE) || owns(ASSISTANT)
        }

        /** 1 on, 0 off, null when the setting can't be read. */
        private fun secureFlag(context: Context, key: String): Boolean? = try {
            when (Settings.Secure.getInt(context.contentResolver, key, -1)) {
                -1 -> null
                0 -> false
                else -> true
            }
        } catch (e: Exception) {
            null
        }
    }

    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            AssistProtocol.SETUP_STATUS -> result.success(
                mapOf(
                    AssistProtocol.SETUP_IS_DEFAULT to isDefault(activity),
                    AssistProtocol.SETUP_SDK to Build.VERSION.SDK_INT,
                    AssistProtocol.SETUP_MANUFACTURER to Build.MANUFACTURER,
                    AssistProtocol.SETUP_SCREEN_TEXT to secureFlag(activity, ASSIST_STRUCTURE),
                    AssistProtocol.SETUP_SCREENSHOT to secureFlag(activity, ASSIST_SCREENSHOT),
                ),
            )
            AssistProtocol.SETUP_REQUEST -> request(result)
            AssistProtocol.SETUP_OPEN_SETTINGS -> result.success(openAssistantSettings(activity))
            AssistProtocol.SETUP_TRY_IT -> result.success(
                try {
                    activity.startActivity(
                        AssistActivity.intent(activity, AssistProtocol.SOURCE_TRY, SystemClock.uptimeMillis(), false),
                    )
                    true
                } catch (e: Exception) {
                    false
                },
            )
            else -> result.notImplemented()
        }
    }

    /**
     * Asks for the assistant role where the system allows it; most builds do
     * not let apps request ROLE_ASSISTANT, so the fallback is the settings
     * page. Returns 'granted', 'settings' or 'failed'.
     */
    private fun request(result: MethodChannel.Result) {
        if (isDefault(activity)) return result.success(AssistProtocol.RESULT_GRANTED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && pending == null) {
            try {
                val rm = activity.getSystemService(RoleManager::class.java)
                if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
                    pending = result
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(
                        rm.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT),
                        REQUEST_ROLE,
                    )
                    return
                }
            } catch (e: Exception) {
                pending = null
            }
        }
        result.success(if (openAssistantSettings(activity)) AssistProtocol.RESULT_SETTINGS else AssistProtocol.RESULT_FAILED)
    }

    /** From MainActivity.onActivityResult. True when it was ours. */
    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_ROLE) return false
        val result = pending ?: return true
        pending = null
        if (isDefault(activity)) {
            result.success(AssistProtocol.RESULT_GRANTED)
        } else {
            result.success(if (openAssistantSettings(activity)) AssistProtocol.RESULT_SETTINGS else AssistProtocol.RESULT_FAILED)
        }
        return true
    }
}
