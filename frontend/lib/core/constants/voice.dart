/// Voice input in the composer: copy, sizes, timings and language names.
abstract final class VoiceStrings {
  static const mic = 'Dictate a message';
  static const finish = 'Stop dictation';
  static const cancel = 'Cancel dictation';
  static const listening = 'LISTENING';
  static const transcribing = 'TRANSCRIBING';
  static const slideToCancel = 'SLIDE LEFT TO CANCEL';
  static const retry = 'TRY AGAIN';
  static const openSettings = 'OPEN SETTINGS';
  static const dismiss = 'Dismiss';

  // Permission
  static const rationaleTitle = 'Use the microphone?';
  static const rationaleBody =
      'sparky only listens while you dictate, and only to turn your voice '
      'into text for the message box.';
  static const rationaleAllow = 'ALLOW';
  static const rationaleNotNow = 'NOT NOW';
  static const blockedTitle = 'Microphone is off';
  static const blockedBody =
      'Microphone access was turned off for sparky. Turn it on in the app '
      'settings to dictate.';

  // Errors
  static const denied = 'Microphone access is needed to dictate.';
  static const blocked = 'Microphone access is off for sparky.';
  static const unavailable = 'Voice input is not available on this device.';
  static const noSpeech = "Didn't catch that. Try again.";
  static const network = 'No connection for voice input.';
  static const failed = 'Voice input failed. Try again.';
  static const emptyResult = 'No speech was found.';

  // Settings
  static const autoSendLabel = 'Send voice messages automatically';
  static const autoSendHelp =
      'Send as soon as you stop dictating. Off keeps the text in the box '
      'so you can edit it first.';
  static const accuracyLabel = 'High-accuracy transcription';
  static const accuracyHelp =
      'Record and transcribe on the server. Slower, but better with accents '
      'and mixed languages.';

  static String clock(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

abstract final class VoiceSizes {
  /// Columns of the dot-matrix level meter and the dots in each column.
  static const meterColumns = 24;
  static const meterRows = 5;
  static const meterDot = 3.0;
  static const meterGap = 3.0;
  static const meterMinLevel = 0.08;
  static const stripHeight = 40.0;
  static const timerWidth = 40.0;

  /// Distance the finger slides left, while holding, to cancel.
  static const holdCancelDistance = 72.0;
}

abstract final class VoiceConfig {
  /// The server accepts about two minutes of audio.
  static const maxDuration = Duration(minutes: 2);
  static const pauseFor = Duration(seconds: 6);

  /// An on-device engine that never reports a final result is cut off after this.
  static const finishTimeout = Duration(seconds: 3);
  static const amplitudeEvery = Duration(milliseconds: 80);
  static const tick = Duration(seconds: 1);

  /// m4a (AAC) mono at a speech-friendly rate: about 240 KB a minute.
  static const sampleRate = 16000;
  static const bitRate = 32000;
  static const fileExtension = 'm4a';
  static const requestTimeout = Duration(seconds: 60);

  /// Reply-language names (lowercase) to BCP-47 locale tags.
  static const languageTags = <String, String>{
    'hindi': 'hi-IN',
    'हिन्दी': 'hi-IN',
    'hinglish': 'hi-IN',
    'english': 'en',
    'spanish': 'es-ES',
    'español': 'es-ES',
    'german': 'de-DE',
    'deutsch': 'de-DE',
    'french': 'fr-FR',
    'français': 'fr-FR',
    'portuguese': 'pt-BR',
    'português': 'pt-BR',
    'italian': 'it-IT',
    'italiano': 'it-IT',
    'japanese': 'ja-JP',
    'korean': 'ko-KR',
    'chinese': 'zh-CN',
    'arabic': 'ar-SA',
    'russian': 'ru-RU',
    'bengali': 'bn-IN',
    'tamil': 'ta-IN',
    'telugu': 'te-IN',
    'marathi': 'mr-IN',
    'gujarati': 'gu-IN',
    'urdu': 'ur-IN',
  };
}
