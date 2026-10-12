import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Plain-language copy for the Settings screen.
abstract final class SettingsStrings {
  static const searchHint = 'Search settings';
  static const searchClear = 'Clear search';
  static const noResults = 'No settings match that. Try another word.';

  // Groups: title (mono caption) and one-line helper.
  static const youTitle = 'YOU';
  static const youHelp = 'Tell sparky who you are so replies feel personal.';
  static const repliesTitle = 'REPLIES';
  static const repliesHelp = 'Pick how sparky should sound. Tap a style.';
  static const privacyTitle = 'PRIVACY & MEMORY';
  static const privacyHelp =
      'What sparky remembers and what it may look at when it answers.';
  static const appsTitle = 'CONNECTED APPS';
  static const appsHelp = 'Link your accounts so sparky can use them.';
  static const storageTitle = 'STORAGE';
  static const storageHelp = 'Files and uploads you have shared with sparky.';
  static const notificationsTitle = 'NOTIFICATIONS';
  static const notificationsHelp =
      'When sparky is allowed to get your attention.';
  static const appearanceTitle = 'APPEARANCE';
  static const appearanceHelp = 'Light or dark, text size and touch feedback.';
  static const advancedTitle = 'ADVANCED';
  static const advancedHelp = 'Models, modes, usage and server details.';
  static const aboutTitle = 'ABOUT';

  // You
  static const nameLabel = 'Your name';
  static const roleLabel = 'What you do';
  static const aboutYouLabel = 'About you';
  static const signatureLabel = 'Email sign-off';

  // Replies
  static const languageLabel = 'Language of replies';
  static const languageHint = 'e.g. English, Español, Deutsch';
  static const instructionsLabel = 'Anything else sparky should know';
  static const customise = 'Customise';
  static const customiseHelp = 'Fine control over tone and length.';
  static const toneLabel = 'Tone';
  static const lengthLabel = 'How long replies are';
  static const customStyle = 'Custom mix';
  static const defaultStyle = 'Default style';

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
  static const webHelp = 'Search the web for fresh answers in every new chat.';
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
  static const modeHelp = 'Changes what sparky focuses on in chat.';

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
}

abstract final class SettingsIcons {
  static const textSize = HugeIcons.strokeRoundedTextFont;
  static const privacy = HugeIcons.strokeRoundedSecurityLock;
  static const notifications = HugeIcons.strokeRoundedNotification01;
  static const advanced = HugeIcons.strokeRoundedSettings02;
  static const reset = HugeIcons.strokeRoundedArrowReloadHorizontal;
  static const apps = HugeIcons.strokeRoundedPlug01;
  static const storage = HugeIcons.strokeRoundedHardDrive;
  static const modelAuto = HugeIcons.strokeRoundedRocket01;
  static const modelFast = HugeIcons.strokeRoundedFlash;
  static const modelSmart = HugeIcons.strokeRoundedBrain02;
  static const presetTeacher = HugeIcons.strokeRoundedTeacher;
  static const presetFun = HugeIcons.strokeRoundedHappy;
  static const customise = HugeIcons.strokeRoundedSlidersHorizontal;
  static const you = AppIcons.personalization;
}

abstract final class SettingsSizes {
  /// Minimum height of any tappable row or card (Android guideline: 48dp).
  static const touchTarget = 56.0;
  static const presetIcon = 40.0;

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
}
