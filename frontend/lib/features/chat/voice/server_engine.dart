import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/constants/error_copy.dart';
import '../../../core/constants/voice.dart';
import '../../../data/chat_api.dart';
import '../../../data/transcribe_api.dart';
import 'voice_engine.dart';

/// Records m4a with `record`, then has the backend transcribe it with
/// Whisper. No partial text; the result arrives after [stop].
class ServerVoiceEngine implements VoiceEngine {
  ServerVoiceEngine({TranscribeApi? api, AudioRecorder? recorder})
    : _api = api ?? TranscribeApi(),
      _recorder = recorder ?? AudioRecorder();

  final TranscribeApi _api;
  final AudioRecorder _recorder;
  StreamSubscription<Amplitude>? _levels;
  VoiceListener? _listener;
  String _locale = '';
  bool _live = false;

  @override
  String get id => 'server';

  @override
  bool get batch => true;

  @override
  Future<bool> available() async => true;

  @override
  Future<void> start(String locale, VoiceListener listener) async {
    _listener = listener;
    _locale = locale;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}'
          '.${VoiceConfig.fileExtension}';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: VoiceConfig.sampleRate,
          bitRate: VoiceConfig.bitRate,
          numChannels: 1,
        ),
        path: path,
      );
      _live = true;
      _levels = _recorder.onAmplitudeChanged(VoiceConfig.amplitudeEvery).listen(
        (a) {
          // dBFS: about -50 (quiet room) to 0 (loud).
          _listener?.onLevel(((a.current + 50) / 50).clamp(0.0, 1.0));
        },
      );
    } catch (_) {
      listener.onError(VoiceFailure.failed);
    }
  }

  @override
  Future<void> stop() async {
    final listener = _listener;
    if (!_live || listener == null) return;
    _live = false;
    await _levels?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (path == null) return listener.onError(VoiceFailure.failed);
    try {
      final out = await _api.transcribe(path, language: _language);
      if (identical(listener, _listener)) listener.onFinal(out.text);
    } on ApiException catch (e) {
      if (!identical(listener, _listener)) return;
      listener.onError(
        e.status == null ? VoiceFailure.network : VoiceFailure.failed,
        friendlyException(e),
      );
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  String get _language => _locale.split(RegExp('[-_]')).first;

  @override
  Future<void> cancel() async {
    _listener = null;
    _live = false;
    await _levels?.cancel();
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  @override
  void dispose() {
    _listener = null;
    unawaited(_levels?.cancel());
    unawaited(_recorder.dispose());
  }
}
