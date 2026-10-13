import 'package:hugeicons/hugeicons.dart';

import 'app_sizes.dart';

/// The assistant overlay (power-button hold) and Settings > Assistant.
abstract final class AssistStrings {
  // Microphone not allowed yet: Android closes the overlay when it shows its
  // own permission dialog, so the app asks once instead.
  static const micTitle = 'Turn on the microphone';
  static const micBody =
      'Android can\'t ask for the microphone over other apps. Open sparky '
      'once to allow it, then voice works here too.';
  static const micNotNow = 'Not now';
  static const micOpen = 'Open sparky';
  // Overlay
  static const askHint = 'Ask sparky';
  static const attach = 'Add a photo';
  static const attachPhotos = 'Photos';
  static const attachCamera = 'Take a photo';
  static const mic = 'Dictate';
  static const talk = 'Talk to sparky';
  static const send = 'Send';
  static const stop = 'Stop';
  static const shareScreen = 'Share screen with sparky';
  static const sharingScreen = 'Reading the screen…';
  static const screenShared = 'Screen shared';
  static String screenSharedFrom(String app) => 'Screen shared · $app';
  static const unshare = 'Stop sharing the screen';
  static const screenTextOnly =
      'Text only. For a screenshot too, turn on "Use screenshot" in the '
      'assistant settings.';
  static const screenNothing =
      'Could not read this screen. Turn on "Use text from screen" in the '
      'assistant settings.';
  static const screenSettings = 'SETTINGS';
  static const openInSparky = 'Open in sparky';
  static const opening = 'Opening…';
  static const copy = 'Copy';
  static const copied = 'Copied';
  static const close = 'Close';
  static const thinking = 'THINKING';
  static const docInApp = 'Being written. Open in sparky to follow it.';
  static const answerFailed = 'Something went wrong. Try again.';
  static const openFailed = 'Could not open the chat. Try again.';
  static const openOffline =
      "You're offline — connect, then tap Open in sparky again.";
  static const attachFailed = 'That photo could not be added.';
  static const uploading = 'Adding the photo first…';
  static String attachLabel(
    int n, {
    bool screenshot = false,
    bool selection = false,
  }) {
    if (selection && n == 1) return 'SELECTION';
    if (screenshot && n == 1) return 'SCREENSHOT';
    return n == 1 ? '1 PHOTO' : '$n PHOTOS';
  }

  // Signed out
  static const signInTitle = 'Sign in to sparky';
  static const signInBody =
      'Sign in once in the app, then hold the power button to ask from '
      'anywhere.';
  static const signInAction = 'Open sparky';
  static const restoring = 'Signing you in…';

  // Settings > Assistant
  static const catTitle = 'Assistant';
  static const catSummaryOn = 'sparky is your assistant';
  static const catSummaryOff = 'Hold the power button for sparky';
  static const statusOnTitle = 'sparky is your digital assistant';
  static const statusOnBody =
      'Hold the power button (or use your assistant gesture) in any app to '
      'ask sparky.';
  static const statusOffTitle = 'sparky is not your assistant yet';
  static const statusOffBody =
      'Make sparky the default digital assistant app to open it over any '
      'app, like Gemini.';
  static const statusUnknown = 'Checking…';
  static const metaOn = 'DEFAULT';
  static const metaOff = 'NOT SET';
  static const metaChecking = 'CHECKING';
  static const setDefault = 'Set sparky as your assistant';
  static const changeDefault = 'Change the default assistant';
  static const setDefaultHelp =
      'Opens Default apps. Choose Digital assistant app, then sparky.';
  static const tryIt = 'Try it';
  static const tryItHelp = 'Opens the overlay over this screen.';
  static const secHow = 'How to open it';
  static const secScreen = 'Screen context';
  static const secSetup = 'Setup';
  static const howPowerTitle = 'Press and hold the power button';
  static const howPowerBody =
      'Settings > System > Gestures > Press and hold power button > Digital '
      'assistant. On some phones: Advanced features > Side button, or '
      'Buttons & gestures.';
  static const howGestureTitle = 'Or swipe up from a bottom corner';
  static const howGestureBody =
      'With gesture navigation, a diagonal swipe from either bottom corner '
      'opens the assistant. On 3-button navigation, hold Home.';
  static const howNothingTitle = 'Nothing Phone';
  static const howNothingBody =
      'Settings > System > Gestures > Press and hold power button > Digital '
      'assistant.';
  static const screenTextTitle = 'Use text from screen';
  static const screenshotTitle = 'Use screenshot';
  static const screenOn = 'On';
  static const screenOff = 'Off: turn on in the assistant settings';
  static const screenUnknown = 'Set in the assistant settings';
  static const screenPrivacy =
      'sparky only reads the screen when you tap "Share screen with sparky" '
      'in the overlay. Nothing is sent before that tap.';
  static const openAssistantSettings = 'Assistant settings';
  static const unavailable = 'Only on Android phones.';

  // Shared to "Ask sparky"
  static const sharedSkipped =
      'Some of what you shared could not be added (too big or unsupported).';

  // Settings > Assistant: more ways to ask, and what sparky may do.
  static const secMore = 'More ways to ask';
  static const circleTitle = 'Circle to search';
  static const circleBody =
      'Over any app, long-press the pill or tap Circle to search, then '
      'circle, scribble or tap what you want. Needs "Use screenshot".';
  static const tileTitle = 'Quick Settings tile';
  static const tileBody =
      'Edit your Quick Settings and add "Ask sparky" to open it from the '
      'shade.';
  static const shareTitle = 'Share to sparky';
  static const shareBody =
      'Pick "Ask sparky" in any share sheet: text, links, photos and files '
      'open in the overlay, ready to ask about.';
  static const shortcutsTitle = 'App shortcuts';
  static const shortcutsBody =
      'Long-press the sparky icon for "Ask sparky" and "Circle to search".';
  static const secDo = 'What sparky can do';
  static const actionsTitle = 'Phone actions';
  static const actionsBody =
      'Alarms, timers, reminders, calendar events, calls, messages, maps and '
      'apps, as a card you confirm. Nothing runs without your tap.';
  static const liveTitle = 'Live voice';
  static const liveBody =
      'The talk button starts a spoken conversation: sparky answers aloud '
      'and listens again. Tap or start talking to interrupt.';
  static const saveTitle = 'Save assistant chats to history';
  static const saveBody =
      'Questions and answers from the assistant appear in your chats. What is '
      'on your screen is never saved.';
}

abstract final class AssistSizes {
  /// Gap between the overlay and the screen edges.
  static const edge = AppSpacing.md;
  static const pillHeight = 60.0;
  static const pillRadius = 30.0;
  static const pillButton = 44.0;
  static const pillPadding = 8.0;
  static const chipHeight = 36.0;

  /// WEB / KB / TABLE / DOC under the field (smaller than the app's).
  static const toggleHeight = 28.0;
  static const sheetRadius = 28.0;

  /// The answer sheet takes at most this share of the free height.
  static const sheetMaxFactor = 0.62;
  static const sheetPadding = AppSpacing.lg;
  static const wordmark = AppFontSize.title;
  static const questionMaxWidthFactor = 0.82;
  static const actionHeight = 40.0;
  static const signInDots = 7;
  static const fieldMaxLines = 4;
  static const mutedAlpha = 0.7;

  static const shadowLight = 0.14;
  static const shadowDark = 0.5;
  static const shadowBlur = 24.0;
  static const shadowY = 8.0;
}

abstract final class AssistConfig {
  static const channel = AssistChannel.name;
  static const setupChannel = AssistSetupChannel.name;

  /// Screen text sent with a question (after trimming and deduping).
  static const maxScreenChars = 6000;

  /// A content description with fewer words is a button label, not text.
  static const minDescriptionWords = 3;

  /// One line longer than this is cut (huge text views, minified data).
  static const maxLineChars = 1200;

  static const screenshotName = 'screen.jpg';
  static const linkScheme = 'sparky';
  static const chatHost = 'chat';
  static const settingsHost = 'settings';
  static const chatLinkPrefix = '$linkScheme://$chatHost/';
  static const settingsLink = '$linkScheme://$settingsHost/assistant';

  /// Build.MANUFACTURER of Nothing phones (for their own setup path).
  static const nothingManufacturer = 'nothing';

  /// A question waits this long for a session that is still loading.
  static const authWait = Duration(seconds: 8);

  /// "Open in sparky": the wait before the one retry of a failed save.
  static const openRetryDelay = Duration(milliseconds: 800);
}

abstract final class AssistIcons {
  static const screen = HugeIcons.strokeRoundedSmartPhone01;
  static const stop = HugeIcons.strokeRoundedStop;
  static const live = HugeIcons.strokeRoundedAudioWave01;
  static const openApp = HugeIcons.strokeRoundedArrowUpRight01;
  static const camera = HugeIcons.strokeRoundedCamera01;
  static const photos = HugeIcons.strokeRoundedImage01;
  static const power = HugeIcons.strokeRoundedPower;
  static const gesture = HugeIcons.strokeRoundedTouch01;
  static const nothing = HugeIcons.strokeRoundedSmartPhone02;
  static const assistant = HugeIcons.strokeRoundedAiChat02;
  static const tryIt = HugeIcons.strokeRoundedPlay;
  static const settings = HugeIcons.strokeRoundedSettings02;
  static const screenText = HugeIcons.strokeRoundedTextFont;
  static const screenshot = HugeIcons.strokeRoundedImage01;
  static const privacy = HugeIcons.strokeRoundedShield01;
  static const circle = HugeIcons.strokeRoundedSearchArea;
  static const tile = HugeIcons.strokeRoundedDashboardSquare02;
  static const shareTo = HugeIcons.strokeRoundedShare08;
  static const shortcuts = HugeIcons.strokeRoundedTouchInteraction01;
  static const actions = HugeIcons.strokeRoundedAlarmClock;
  static const liveVoice = HugeIcons.strokeRoundedAiVoice;
  static const history = HugeIcons.strokeRoundedClock01;
}

/// The overlay engine's channel. Mirrors AssistProtocol in AssistEngine.kt:
/// change both together.
abstract final class AssistChannel {
  static const name = 'app/assist';

  // Native -> Dart
  static const onShow = 'onShow';
  static const onShared = 'onShared';
  static const onHide = 'onHide';

  // Dart -> native
  static const ready = 'ready';
  static const shown = 'shown';
  static const close = 'close';
  static const screenContext = 'screenContext';
  static const openApp = 'openApp';
  static const assistantSettings = 'assistantSettings';
  static const allowMic = 'allowMic';

  // Arguments and map keys
  static const source = 'source';
  static const screen = 'screen';
  static const link = 'link';
  static const available = 'available';
  static const nodes = 'nodes';
  static const nodeText = 'text';
  static const nodeDesc = 'desc';
  static const app = 'app';
  static const package = 'package';
  static const url = 'url';
  static const screenshot = 'screenshot';
  static const structureArrived = 'structureArrived';
  static const nodeLeft = 'l';
  static const nodeTop = 't';
  static const nodeRight = 'r';
  static const nodeBottom = 'b';
  static const screenWidth = 'screenWidth';
  static const screenHeight = 'screenHeight';
  static const mode = 'mode';
  static const modeCircle = 'circle';

  // Shared content ([onShared])
  static const sharedText = 'text';
  static const sharedSubject = 'subject';
  static const sharedFiles = 'files';
  static const sharedSkipped = 'skipped';
  static const filePath = 'path';
  static const fileName = 'name';
  static const fileSize = 'size';

  // Values of [source]
  static const sourceSession = 'session';
  static const sourceAssist = 'assist';
  static const sourceTry = 'try';
  static const sourceTile = 'tile';
  static const sourceShare = 'share';
  static const sourceShortcut = 'shortcut';
}

/// The app's Settings > Assistant channel. Mirrors AssistantSetup.kt.
abstract final class AssistSetupChannel {
  static const name = 'app/assistant';
  static const status = 'status';
  static const request = 'request';
  static const openSettings = 'openSettings';
  static const tryIt = 'tryIt';

  static const isDefault = 'isDefault';
  static const screenText = 'screenText';
  static const screenshot = 'screenshot';
  static const manufacturer = 'manufacturer';

  // Results of [request]
  static const granted = 'granted';
  static const settings = 'settings';
  static const failed = 'failed';
  static const ok = 'ok';
}

/// The `screen` object of POST /chat (backend src/context/screen.ts).
abstract final class AssistWire {
  static const text = 'text';
  static const app = 'app';
  static const package = 'package';
  static const url = 'url';
  static const screenshot = 'screenshot';
}
