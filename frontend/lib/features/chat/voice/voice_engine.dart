/// Why dictation could not run or stopped.
enum VoiceFailure {
  permissionDenied,
  permissionBlocked,
  unavailable,
  noSpeech,
  network,
  failed,
}

/// What an engine reports back while it runs.
class VoiceListener {
  const VoiceListener({
    required this.onPartial,
    required this.onLevel,
    required this.onFinal,
    required this.onError,
  });

  /// Text so far (on-device engines only).
  final void Function(String text) onPartial;

  /// Loudness, 0..1.
  final void Function(double level) onLevel;

  /// The finished transcript; may be empty.
  final void Function(String text) onFinal;
  final void Function(VoiceFailure failure, [String? message]) onError;
}

/// One way of turning speech into text. The composer talks only to this.
abstract class VoiceEngine {
  /// 'device' or 'server'.
  String get id;

  /// True when the engine only has a result after [stop] (no partial text).
  bool get batch;

  /// Whether the engine can run on this device right now.
  Future<bool> available();

  /// Starts listening. [locale] is a BCP-47 tag such as `en-IN`.
  Future<void> start(String locale, VoiceListener listener);

  /// Ends listening; the transcript arrives through [VoiceListener.onFinal].
  Future<void> stop();

  /// Ends listening and drops everything.
  Future<void> cancel();

  void dispose();
}
