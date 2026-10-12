import 'app_icons.dart';

/// Suggested prompts and composer autocomplete: copy, sizes and timings.
abstract final class SuggestStrings {
  static const autocompleteSetting = 'AUTOCOMPLETE';
  static const accept = 'Accept suggestion';
  static const followUps = 'Suggested follow-ups';
  static String collapsed(int n) => n == 1 ? '1 SUGGESTION' : '$n SUGGESTIONS';
}

abstract final class SuggestIcons {
  static const accept = AppIcons.chevronRight;
  static const followUps = AppIcons.aiFormat;
  static const expand = AppIcons.expand;
  static const collapse = AppIcons.collapse;
}

abstract final class SuggestSizes {
  /// Follow-up chip under the latest reply.
  static const chipHeight = 36.0;
  static const chipMaxWidth = 320.0;

  /// Compact follow-up chips and the collapsed "N SUGGESTIONS" pill.
  static const denseChipHeight = 32.0;
  static const pillHeight = 28.0;
  static const pillIcon = 14.0;
  static const countdownHeight = 2.0;

  /// Next-word chips and the accept button above the keyboard.
  static const wordChipHeight = 32.0;
  static const acceptWidth = 44.0;

  /// Horizontal fling speed (px/s) that accepts the ghost text.
  static const swipeVelocity = 300.0;
  static const ghostOpacity = 0.45;
}

abstract final class SuggestConfig {
  static const followUpKey = 'suggestions';

  /// Fresh follow-ups stay open this long, then fold into one pill.
  static const followUpsVisible = Duration(seconds: 4);

  /// How long the starter prompts of the new-chat screen are reused.
  static const startersTtl = Duration(minutes: 10);

  /// Autocomplete.
  static const debounce = Duration(milliseconds: 350);
  static const requestTimeout = Duration(milliseconds: 2500);
  static const backoff = Duration(seconds: 15);
  static const minChars = 3;
  static const maxWords = 4;
  static const cacheSize = 60;
  static const contextChars = 400;

  /// Local word memory (the user's own messages).
  static const memoryKey = 'autocomplete_words';
  static const memoryMaxWords = 400;
  static const memoryMinWordLength = 2;
}
