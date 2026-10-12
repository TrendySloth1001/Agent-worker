package com.sparky.app.assist

/**
 * Names shared with Dart over the overlay channels. Mirrored in
 * lib/core/constants/assist.dart (AssistChannel / AssistSetupChannel):
 * change both together.
 */
object AssistProtocol {
    const val CHANNEL = "app/assist"
    const val BROWSERS_CHANNEL = "app/browsers"

    // Native -> Dart
    const val ON_SHOW = "onShow"

    // Dart -> native
    const val READY = "ready"
    const val SHOWN = "shown"
    const val CLOSE = "close"
    const val SCREEN_CONTEXT = "screenContext"
    const val OPEN_APP = "openApp"
    const val ASSISTANT_SETTINGS = "assistantSettings"

    // Arguments and map keys
    const val SOURCE = "source"
    const val T0 = "t0"
    const val SCREEN = "screen"
    const val LINK = "link"
    const val AVAILABLE = "available"
    const val NODES = "nodes"
    const val NODE_TEXT = "text"
    const val NODE_DESC = "desc"
    const val APP = "app"
    const val PACKAGE = "package"
    const val URL = "url"
    const val SCREENSHOT = "screenshot"
    const val STRUCTURE_ARRIVED = "structureArrived"

    // Values of SOURCE
    const val SOURCE_SESSION = "session"
    const val SOURCE_ASSIST = "assist"
    const val SOURCE_TRY = "try"

    // Settings > Assistant channel
    const val SETUP_CHANNEL = "app/assistant"
    const val SETUP_STATUS = "status"
    const val SETUP_REQUEST = "request"
    const val SETUP_OPEN_SETTINGS = "openSettings"
    const val SETUP_TRY_IT = "tryIt"
    const val SETUP_IS_DEFAULT = "isDefault"
    const val SETUP_SDK = "sdk"
    const val SETUP_MANUFACTURER = "manufacturer"
    const val SETUP_SCREEN_TEXT = "screenText"
    const val SETUP_SCREENSHOT = "screenshot"
    const val RESULT_GRANTED = "granted"
    const val RESULT_SETTINGS = "settings"
    const val RESULT_FAILED = "failed"

    // Links into the app
    const val LINK_SCHEME_PREFIX = "sparky://"
    const val SETTINGS_LINK = "sparky://settings/assistant"

    // Timings and limits
    /** How long "Share screen" waits for the system's screen callbacks. */
    const val SCREEN_WAIT_MS = 1500L
    const val SCREEN_POLL_MS = 50L

    const val LOG_TAG = "SparkyAssist"

    // Screen context
    const val CACHE_DIR = "assist"
    const val SCREENSHOT_PREFIX = "screen-"
    const val WEB_SCHEME_PREFIX = "http"
    const val HTTPS_PREFIX = "https://"
}
