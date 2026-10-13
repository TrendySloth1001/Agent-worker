import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/constants/voice.dart';
import 'voice_engine.dart';
import 'voice_locale.dart';

/// Android's own recognizer through `speech_to_text`: free, with fast
/// partial results. Languages come from what the device has installed
/// (en-IN and hi-IN work wherever Google's speech service has them).
class OnDeviceVoiceEngine implements VoiceEngine {
  OnDeviceVoiceEngine({SpeechToText? speech}) : _stt = speech ?? SpeechToText();

  final SpeechToText _stt;
  Future<bool>? _init;
  VoiceListener? _listener;
  String _last = '';
  double? _confidence;
  bool _finished = false;

  @override
  String get id => 'device';

  @override
  bool get batch => false;

  @override
  Future<bool> available() => _init ??= _stt
      .initialize(onError: _onError, onStatus: _onStatus)
      .catchError((_) => false);

  @override
  Future<void> start(String locale, VoiceListener listener) async {
    _listener = listener;
    _last = '';
    _confidence = null;
    _finished = false;
    String? localeId;
    try {
      final ids = (await _stt.locales()).map((l) => l.localeId);
      localeId = pickRecognizerLocale(locale, ids);
    } catch (_) {}
    try {
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          localeId: localeId,
          listenFor: VoiceConfig.maxDuration,
          pauseFor: VoiceConfig.pauseFor,
        ),
      );
    } catch (_) {
      _fail(VoiceFailure.failed);
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    _last = r.recognizedWords;
    if (r.finalResult && r.hasConfidenceRating) _confidence = r.confidence;
    _listener?.onPartial(_last);
    if (r.finalResult) _finish();
  }

  /// Android reports roughly -2..10 dB; map to 0..1.
  void _onLevel(double db) =>
      _listener?.onLevel(((db + 2) / 12).clamp(0.0, 1.0));

  void _onStatus(String status) {
    // The recognizer ended by itself (silence): deliver what we have.
    if (status == SpeechToText.doneStatus) _finish();
  }

  void _onError(SpeechRecognitionError e) {
    final id = e.errorMsg;
    if (id == 'error_no_match' || id == 'error_speech_timeout') {
      if (_last.isNotEmpty) return _finish();
      return _fail(VoiceFailure.noSpeech);
    }
    if (id == 'error_permission') return _fail(VoiceFailure.permissionDenied);
    if (id.startsWith('error_network')) return _fail(VoiceFailure.network);
    if (id == 'error_busy' || id == 'error_client') return;
    _fail(e.permanent ? VoiceFailure.unavailable : VoiceFailure.failed);
  }

  void _finish() {
    final l = _listener;
    if (_finished || l == null) return;
    _finished = true;
    l.onFinal(_last, _confidence);
  }

  void _fail(VoiceFailure f) {
    final l = _listener;
    if (_finished || l == null) return;
    _finished = true;
    l.onError(f);
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
    // The final result normally arrives from stop(); if it does not, the
    // controller's finish timeout ends the session with the last partial.
  }

  @override
  Future<void> cancel() async {
    _finished = true;
    _listener = null;
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  @override
  void dispose() => _listener = null;
}
