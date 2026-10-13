/// Live transcript correction: copy, sizes and timings.
abstract final class VoiceFixStrings {
  static const fixing = 'FIXING';
  static const undo = 'Undo fix';
  static const undoSemantics =
      'Undo the automatic fix and restore what was heard';

  static String fixed(int words) =>
      words == 1 ? 'Fixed 1 word' : 'Fixed $words words';

  // Settings
  static const autoFixLabel = 'Auto-fix what I say';
  static const autoFixHelp =
      'Fix misheard words, punctuation, numbers and fillers as you dictate. '
      'Only the dictated text and your last two messages are sent.';
  static const exactLabel = 'Keep my exact words';
  static const exactHelp =
      'Only add punctuation and capitals. Never change, remove or replace '
      'a word.';
}

abstract final class VoiceFixSizes {
  static const chipHeight = 28.0;
  static const chipIcon = 14.0;

  /// Alpha of the highlight behind corrected words.
  static const highlightAlpha = 0.18;
}

abstract final class VoiceFixConfig {
  /// The whole model pass, network included; past it the local text stays.
  static const llmTimeout = Duration(milliseconds: 1200);

  /// Network allowance: the server gets [llmTimeout] minus this.
  static const networkMargin = Duration(milliseconds: 150);

  /// Fewer words than this is a command: the model is not asked.
  static const minLlmWords = 4;

  /// The recognizer's own confidence at which a short result is trusted as is.
  static const confidentAsr = 0.97;
  static const confidentMaxWords = 6;

  /// A gap between partial results this long is a pause in speech.
  static const pauseGap = Duration(milliseconds: 900);

  /// Corrected words stay highlighted this long; the undo chip stays longer.
  static const highlightFor = Duration(milliseconds: 2500);
  static const undoFor = Duration(seconds: 10);

  /// Names and repositories are fetched again after this.
  static const vocabTtl = Duration(minutes: 30);
  static const vocabTimeout = Duration(seconds: 5);
  static const maxVocab = 40;

  /// On-device timings held for the next request (owner telemetry).
  static const maxLocalSamples = 50;

  /// Context sent with a fix: the last two messages, each clipped.
  static const contextTurns = 2;
  static const contextChars = 400;

  /// Sentences shorter than this get a comma at a pause, not a full stop.
  static const minSentenceWords = 3;
}
