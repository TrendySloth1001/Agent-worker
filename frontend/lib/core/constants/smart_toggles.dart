// Smart composer toggles: the three-state WEB chip and the "use your
// knowledge base?" / "write it as a Doc?" prompts the server suggests.

/// WEB: Auto lets the server decide per message, On always searches,
/// Off never does.
enum WebMode {
  auto,
  on,
  off;

  /// Value sent to and read from the server and saved prefs.
  String get wire => name;

  /// Tapping the chip steps to the next state.
  WebMode get next => WebMode.values[(index + 1) % WebMode.values.length];

  static WebMode fromWire(Object? value) => WebMode.values.firstWhere(
    (m) => m.name == value,
    orElse: () => WebMode.auto,
  );
}

/// What a `suggest_toggle` event offers.
enum SuggestKind {
  kb,
  doc;

  static SuggestKind? fromWire(Object? value) =>
      SuggestKind.values.where((k) => k.name == value).firstOrNull;
}

abstract final class SmartStrings {
  // Chip hints
  static const webAuto = 'AUTO';
  static const webOff = 'OFF';

  // Reply
  static const searchedWeb = 'Searched the web';

  // KB prompt
  static const kbTitle = 'Use your knowledge base?';
  static const kbUse = 'Use KB';
  static const notNow = 'Not now';
  static String kbBody(int count, String titles) => count > 0
      ? '$count of your documents look relevant: $titles'
      : 'You mentioned your notes. I can search them for this.';

  // Doc prompt
  static const docTitle = 'This looks like a long document.';
  static const docBody = 'Write it as a Doc?';
  static const docWrite = 'Write as Doc';
  static const docChat = 'Answer in chat';

  // Settings
  static const settingLabel = 'Smart suggestions';
  static const settingHelp =
      'Offer the knowledge base and Docs when a message looks like it '
      'needs them. Web search decides on its own.';
  static const settingKeywords = 'smart suggestions knowledge base docs ask';
}

abstract final class SmartConfig {
  /// Longest list of document titles shown in the knowledge-base prompt.
  static const maxTitles = 3;

  /// Prefs key of the per-conversation composer state (a JSON map).
  static const composerPrefsKey = 'composer_state_v1';

  /// `meta` key of a reply the server searched the web for on its own.
  static const searchedKey = 'webAuto';

  /// Conversations remembered before the oldest are dropped.
  static const maxRemembered = 200;
}

abstract final class SmartSizes {
  static const promptRadius = 20.0;
  static const promptIcon = 20.0;
  static const hintSpacing = 4.0;
}
