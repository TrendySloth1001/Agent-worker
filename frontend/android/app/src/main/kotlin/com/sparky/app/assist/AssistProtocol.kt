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
    /** Files and text shared to "Ask sparky" (after they were copied). */
    const val ON_SHARED = "onShared"
    /** The overlay went out of sight (Home, another app): stop talking and listening. */
    const val ON_HIDE = "onHide"

    // Dart -> native
    const val READY = "ready"
    const val SHOWN = "shown"
    const val CLOSE = "close"
    const val SCREEN_CONTEXT = "screenContext"
    const val OPEN_APP = "openApp"
    const val ASSISTANT_SETTINGS = "assistantSettings"
    // Microphone not allowed yet: Android closes the overlay when it shows its
    // permission dialog, so the app asks instead.
    const val ALLOW_MIC = "allowMic"

    /** Intent extra: MainActivity asks for the microphone permission. */
    const val EXTRA_REQUEST_MIC = "com.sparky.app.extra.REQUEST_MIC"
    const val REQUEST_MIC_CODE = 4107

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
    // Screen bounds of a text node (screen pixels) and the screen's size.
    const val NODE_LEFT = "l"
    const val NODE_TOP = "t"
    const val NODE_RIGHT = "r"
    const val NODE_BOTTOM = "b"
    const val SCREEN_WIDTH = "screenWidth"
    const val SCREEN_HEIGHT = "screenHeight"
    // How the overlay starts (show args): plain, or straight into circle mode.
    const val MODE = "mode"
    const val MODE_CIRCLE = "circle"
    // Shared content (ON_SHARED args).
    const val SHARED_TEXT = "text"
    const val SHARED_SUBJECT = "subject"
    const val SHARED_FILES = "files"
    const val FILE_PATH = "path"
    const val FILE_NAME = "name"
    const val FILE_SIZE = "size"
    const val SHARED_SKIPPED = "skipped"

    // Values of SOURCE
    const val SOURCE_SESSION = "session"
    const val SOURCE_ASSIST = "assist"
    const val SOURCE_TRY = "try"
    const val SOURCE_TILE = "tile"
    const val SOURCE_SHARE = "share"
    const val SOURCE_SHORTCUT = "shortcut"

    // Launcher shortcuts (res/xml/shortcuts.xml): explicit intents to AssistActivity.
    const val ACTION_ASK = "com.sparky.app.action.ASK"
    const val ACTION_CIRCLE = "com.sparky.app.action.CIRCLE"

    // Device actions the user confirmed on a card ('app/actions', both engines).
    const val ACTIONS_CHANNEL = "app/actions"
    const val ACTIONS_RUN = "run"
    const val ACTION_TYPE = "type"
    const val RESULT_OK = "ok"
    const val RESULT_NOT_FOUND = "not_found"
    const val RESULT_UNAVAILABLE = "unavailable"

    // Spoken answers in Live mode ('app/tts', overlay engine).
    const val TTS_CHANNEL = "app/tts"
    const val TTS_SPEAK = "speak"
    const val TTS_STOP = "stop"
    const val TTS_ON_DONE = "onDone"
    const val TTS_TEXT = "text"
    const val TTS_LANG = "lang"
    const val TTS_ID = "id"

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
    const val SHARE_DIR = "assist-share"
    /** Shared files bigger than this are skipped (the app's own cap is lower per kind). */
    const val SHARE_MAX_BYTES = 50L * 1024 * 1024
    const val SHARE_MAX_FILES = 10
    const val WEB_SCHEME_PREFIX = "http"
    const val HTTPS_PREFIX = "https://"
}
