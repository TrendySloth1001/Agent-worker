import 'package:hugeicons/hugeicons.dart';

/// Live mode in the assistant overlay: talk, sparky answers aloud, talk again.
abstract final class LiveStrings {
  static const start = 'Live: talk with sparky';
  static const end = 'End Live';
  static const listening = 'LISTENING';
  static const thinking = 'THINKING';
  static const speaking = 'SPEAKING';
  static const tapToTalk = 'Tap to interrupt';
  static const speakNow = 'Speak, sparky answers aloud';
  static const live = 'LIVE';
  static const ended = 'Live ended: nothing heard for a while.';
}

abstract final class LiveConfig {
  /// TTS channel (TtsBridge.kt). Mirrors AssistProtocol.TTS_*.
  static const channel = 'app/tts';
  static const speak = 'speak';
  static const stop = 'stop';
  static const onDone = 'onDone';
  static const text = 'text';
  static const lang = 'lang';
  static const id = 'id';

  /// Silent listens in a row before Live stops by itself.
  static const maxSilentTurns = 2;

  /// While sparky talks, heard words that are not in its own answer (more
  /// than this many) count as the user interrupting.
  static const bargeInWords = 2;

  /// The shortest sentence spoken on its own (shorter ones wait for more).
  static const minChunkChars = 24;
}

abstract final class LiveSizes {
  static const dots = 3;
  static const dot = 8.0;
  static const dotGap = 4.0;
  static const dimAlpha = 0.3;
  static const pulsePeriod = Duration(milliseconds: 900);
}

abstract final class LiveIcons {
  static const live = HugeIcons.strokeRoundedAiVoice;
  static const end = HugeIcons.strokeRoundedCancel01;
}
