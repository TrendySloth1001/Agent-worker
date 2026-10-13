import 'package:hugeicons/hugeicons.dart';

/// Plain-language copy for the Settings screen.
abstract final class SettingsStrings {
  static const searchHint = 'Search settings';
  static const searchResults = 'Results';
  static const resetKeywords = 'reset defaults restore';
  static const searchClear = 'Clear search';
  static const noResults = 'No settings match that. Try another word.';

  // Root screen
  static const title = 'Settings';
  static const accountFallback = 'Your profile';
  static const accountHelp = 'Account, photo and sessions';

  // Categories: title and the summary shown when nothing live is available.
  static const catProfile = 'Profile & personalization';
  static const catReplies = 'Replies & voice';
  static const catPrivacy = 'Privacy & memory';
  static const catSearch = 'Search & knowledge';
  static const catApps = 'Connected apps';
  static const catStorage = 'Storage';
  static const catNotifications = 'Notifications';
  static const catAppearance = 'Appearance';
  static const catModels = 'Models & usage';
  static const catTelemetry = 'Telemetry & analytics';
  static const catServer = 'Server status';
  static const catAbout = 'About sparky';

  static const sumPrivacy = 'Memory and saved knowledge';
  static const sumApps = 'GitHub, Google Drive, Google Photos';
  static const sumStorage = 'Files and uploads you shared';
  static const sumTelemetry = 'Owner only: model calls, tokens, latency';
  static const sumNotSet = 'Not set';
  static const on = 'On';
  static const off = 'Off';
  static const separator = ' \u00b7 ';

  // Section headers on sub-pages
  static const secAbout = 'About you';
  static const secAccount = 'Account';
  static const secStyle = 'Style';
  static const secLanguage = 'Language & instructions';
  static const secTyping = 'Typing & voice';
  static const secMemory = 'Memory';
  static const secDefaults = 'On by default in new chats';
  static const secAccounts = 'Accounts';
  static const secLinks = 'Links';
  static const secTheme = 'Display';
  static const secText = 'Text';
  static const secFeedback = 'Feedback';
  static const secModel = 'Which AI answers';
  static const secUsage = 'Usage today';
  static const secProviders = 'Providers and quotas';
  static const secServices = 'Data and tools';
  static const secHealth = 'Health';

  // Sentence-case option labels
  static const themeSystem = 'System';
  static const themeLight = 'Light';
  static const themeDark = 'Dark';
  static const toneNone = 'No preference';
  static const toneFriendly = 'Friendly';
  static const toneProfessional = 'Professional';
  static const toneCasual = 'Casual';
  static const toneDirect = 'Direct';
  static const toneEnthusiastic = 'Enthusiastic';
  static const lengthConcise = 'Concise';
  static const lengthBalanced = 'Balanced';
  static const lengthDetailed = 'Detailed';
  static const modeEngineer = 'Engineer';
  static const modeDebug = 'Debug';
  static const modeReview = 'Review';
  static const modeArchitect = 'Architect';
  static const modeExplain = 'Explain';
  static const toneHelp = 'The voice sparky answers in.';
  static const lengthHelp = 'How much sparky writes back.';
  static const defaultReply = 'Default';
  static const textPreview =
      'The quick brown fox jumps over the lazy dog. Sparky replies will look '
      'like this.';
  static const textSizeTitle = 'Text size';
  static const browserTitle = 'Browser';
  static const systemDefault = 'System default';
  static const soon = 'Coming soon';
  static const connect = 'Tap to connect';
  static const waiting = 'Waiting for approval';
  static const unavailable = 'Unavailable';
  static const online = 'Online';
  static const offline = 'Offline';
  static const degraded = 'Degraded';
  static const checking = 'Checking';
  static const backend = 'Backend';
  static const status = 'Status';
  static const database = 'Database';
  static const embeddings = 'Embeddings';
  static const unknown = 'Unknown';
  static const providersActive = 'providers active';
  static const resetTitle = 'Reset to defaults';
  static const saveFirstProfile = 'Add your name';

  static const accountTitle = 'Account and sessions';
  static const replyStyleTitle = 'Reply style';
  static const knowledgeTitle = 'Saved knowledge';
  static const knowledgeHelp = 'Notes and files sparky can check first.';
  static const searchService = 'Web search';
  static const sumWeb = 'Web';
  static const sumKnowledge = 'Knowledge';
  static const sumRoundTable = 'Round table';
  static const sumAllOff = 'All off';

  // You
  static const nameLabel = 'Your name';
  static const roleLabel = 'What you do';
  static const aboutYouLabel = 'About you';
  static const signatureLabel = 'Email sign-off';

  // Replies
  static const languageLabel = 'Language of replies';
  static const languageHint = 'e.g. English, Español, Deutsch';
  static const instructionsLabel = 'Anything else sparky should know';
  static const toneLabel = 'Tone';
  static const lengthLabel = 'How long replies are';

  // Memory and typing
  static const memoryLabel = 'Remember things about me';
  static const memoryHelp =
      "sparky keeps useful facts so you don't repeat yourself. "
      'Tap to turn it on or off and manage what it knows.';
  static const autocompleteLabel = 'Suggest words as I type';
  static const autocompleteHelp =
      'Finish my sentences while I write a message.';

  // Search & knowledge
  static const webLabel = 'Look things up online';
  static const webHelp =
      'Search the web on its own when a question needs fresh answers. '
      'Tap WEB in a chat to always or never search.';
  static const kbLabel = 'Use my saved knowledge';
  static const kbHelp = 'Check the notes and files you added first.';
  static const tableLabel = 'Ask several AIs at once';
  static const tableHelp = 'Round table: slower, but cross-checked answers.';

  // Apps
  static const browserHelp = 'Where links open when you tap them.';

  // Notifications
  static const tableNotifyLabel = 'Tell me when a round table is done';
  static const tableNotifyHelp =
      'A notification if you left the app meanwhile.';

  // Appearance
  static const themeLabel = 'Theme';
  static const textSizeLabel = 'Text size';
  static const textSizeHelp = 'Makes words bigger or smaller everywhere.';
  static const textSmall = 'Small';
  static const textNormal = 'Normal';
  static const textLarge = 'Large';
  static const textHuge = 'Largest';
  static const hapticsLabel = 'Vibrate on tap';
  static const hapticsHelp = 'A tiny buzz when you press things.';

  // Advanced
  static const modelTitle = 'Which AI answers';
  static const modelAuto = 'Auto (recommended)';
  static const modelAutoHelp = 'sparky picks the best one available each time.';
  static const modelFast = 'Fastest';
  static const modelFastHelp = 'Quick answers, a little less depth.';
  static const modelSmart = 'Smartest';
  static const modelSmartHelp = 'Slower, best for hard questions.';
  static const allModels = 'Choose a specific model';
  static const allModelsHelp = 'For people who know what they want.';
  static const modelsLoading = 'Loading models...';
  static const modelsFailed = 'Could not load the model list.';
  static const modeTitle = 'Working mode';

  // Reset
  static const reset = 'Reset to defaults';
  static const resetHelp =
      'Puts every preference back. Your name and notes stay.';
  static const resetConfirmTitle = 'Reset settings?';
  static const resetConfirmBody =
      'Reply style, toggles, theme, text size and model go back to normal. '
      'Your name and personal notes are kept.';
  static const resetDone = 'Settings reset';
  static const cancel = 'Cancel';

  // Developer (owner only): server, usage numbers and telemetry.
  static const developer = 'Developer';
  static const developerHelp = 'Server, usage numbers and telemetry';
  static const developerShow = 'Show developer tools';
  static const developerHide = 'Hide developer tools';

  // Plain connection notice, shown to everyone only when there is a problem.
  static const unreachableTitle = "sparky can't be reached right now";
  static const unreachableHelp =
      'Check your internet connection, then try again.';
  static const troubleTitle = 'sparky is having a little trouble';
  static const troubleHelp = 'Some answers may be slower than usual.';
  static const tryAgain = 'Try again';
}

abstract final class SettingsIcons {
  static const textSize = HugeIcons.strokeRoundedTextFont;
  static const theme = HugeIcons.strokeRoundedPaintBoard;
  static const tone = HugeIcons.strokeRoundedSmile;
  static const length = HugeIcons.strokeRoundedTextAlignLeft;
  static const account = HugeIcons.strokeRoundedUserCircle;
  static const listModels = HugeIcons.strokeRoundedListView;
  static const privacy = HugeIcons.strokeRoundedSecurityLock;
  static const notifications = HugeIcons.strokeRoundedNotification01;
  static const reset = HugeIcons.strokeRoundedArrowReloadHorizontal;
  static const apps = HugeIcons.strokeRoundedPlug01;
  static const modelAuto = HugeIcons.strokeRoundedRocket01;
  static const modelFast = HugeIcons.strokeRoundedFlash;
  static const modelSmart = HugeIcons.strokeRoundedBrain02;
  static const presetTeacher = HugeIcons.strokeRoundedTeacher;
  static const presetFun = HugeIcons.strokeRoundedHappy;
  static const developer = HugeIcons.strokeRoundedSourceCode;
  static const expand = HugeIcons.strokeRoundedArrowDown01;
  static const unreachable = HugeIcons.strokeRoundedWifiDisconnected02;
}

abstract final class SettingsSizes {
  /// Minimum height of any tappable row or card (Android guideline: 48dp).
  static const touchTarget = 56.0;

  /// Android 16 style grouping: big outer corners, small inner ones, a thin
  /// gap between cells.
  static const groupOuterRadius = 28.0;
  static const groupInnerRadius = 6.0;
  static const groupGap = 2.0;
  static const iconCircle = 40.0;
  static const iconGlyph = 22.0;
  static const avatar = 56.0;
  static const groupSpacing = 20.0;
  static const headerInset = 16.0;
  static const pageTransition = Duration(milliseconds: 300);
  static const pageShift = 30.0;
  static const highlightMs = Duration(milliseconds: 1400);

  /// Model ids behind the "Fastest" and "Smartest" presets.
  static const fastModelId = 'groq:openai/gpt-oss-20b';
  static const smartModelId = 'nvidia:nvidia/nemotron-3-ultra-550b-a55b';

  /// Text size ids to scale factor.
  static const textScales = {
    'small': 0.9,
    'normal': 1.0,
    'large': 1.15,
    'huge': 1.3,
  };

  /// M3 Expressive slider track height.
  static const sliderTrack = 16.0;

  /// Dot-matrix accent (hero avatar, empty states).
  static const dotSpacing = 8.0;
  static const dotRadius = 1.2;
  static const heroAvatar = 96.0;
  static const heroDotField = 168.0;
  static const accentDot = 6.0;
  static const accentGap = 2.0;
  static const badge = 32.0;
  static const metaFont = 11.0;
  static const emptyDots = 96.0;
}
