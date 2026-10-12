import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/voice.dart';
import '../../../core/haptics.dart';
import 'voice_engine.dart';
import 'voice_permission.dart';

enum VoicePhase { idle, listening, transcribing, error }

/// Called with the dictated text so far, and again when it is final.
typedef VoiceTextSink = void Function(String text, bool isFinal);

/// Runs one dictation at a time: permission, engine choice (on-device first,
/// the server as fallback or by setting), the timer, the level history and
/// errors. The composer only listens to this and shows it.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.onDevice,
    this.server,
    this.permission = const SystemVoicePermission(),
    this.locale = _defaultLocale,
    this.highAccuracy = _never,
    this.maxDuration = VoiceConfig.maxDuration,
  });

  static String _defaultLocale() => 'en-US';
  static bool _never() => false;

  final VoiceEngine onDevice;
  final VoiceEngine? server;
  final VoicePermission permission;

  /// Read at the start of every dictation, so settings changes apply at once.
  final String Function() locale;
  final bool Function() highAccuracy;
  final Duration maxDuration;

  VoicePhase _phase = VoicePhase.idle;
  VoiceFailure? _failure;
  String? _message;
  String _text = '';
  Duration _elapsed = Duration.zero;
  final List<double> _levels = List.filled(
    VoiceSizes.meterColumns,
    0.0,
    growable: true,
  );
  VoiceEngine? _engine;
  bool _fellBack = false;
  int _session = 0;
  Timer? _tick, _limit, _finishTimer;
  VoiceTextSink? _sink;

  VoicePhase get phase => _phase;
  VoiceFailure? get failure => _failure;

  /// A server-provided message for [failure], when there is one.
  String? get message => _message;
  String get text => _text;
  Duration get elapsed => _elapsed;
  List<double> get levels => List.unmodifiable(_levels);

  /// Which engine is running: 'device' or 'server'.
  String? get engineId => _engine?.id;
  bool get listening => _phase == VoicePhase.listening;

  /// Listening or waiting for the transcript.
  bool get active =>
      _phase == VoicePhase.listening || _phase == VoicePhase.transcribing;

  /// Whether the system would show the permission prompt or the app is blocked.
  Future<VoicePermissionState> permissionState() => permission.check();

  Future<void> openSettings() => permission.openSettings();

  Future<void> start(VoiceTextSink sink) async {
    if (active) return;
    final session = ++_session;
    _sink = sink;
    _reset();
    var state = await permission.check();
    if (state != VoicePermissionState.granted) {
      state = await permission.request();
    }
    if (session != _session) return;
    if (state != VoicePermissionState.granted) {
      return _fail(
        state == VoicePermissionState.blocked
            ? VoiceFailure.permissionBlocked
            : VoiceFailure.permissionDenied,
      );
    }
    final fallback = server;
    VoiceEngine? engine;
    if (highAccuracy() && fallback != null) {
      engine = fallback;
    } else if (await onDevice.available()) {
      engine = onDevice;
    } else if (fallback != null) {
      engine = fallback;
      _fellBack = true;
    }
    if (session != _session) return;
    if (engine == null) return _fail(VoiceFailure.unavailable);
    await _begin(engine, session);
  }

  Future<void> _begin(VoiceEngine engine, int session) async {
    _engine = engine;
    _phase = VoicePhase.listening;
    _elapsed = Duration.zero;
    _tick?.cancel();
    _tick = Timer.periodic(VoiceConfig.tick, (_) {
      _elapsed += VoiceConfig.tick;
      notifyListeners();
    });
    _limit?.cancel();
    _limit = Timer(maxDuration, stop);
    Haptics.recordStart();
    notifyListeners();
    await engine.start(
      locale(),
      VoiceListener(
        onPartial: (t) => _partial(session, t),
        onLevel: (l) => _level(session, l),
        onFinal: (t) => _final(session, t),
        onError: (f, [m]) => _error(session, f, m),
      ),
    );
  }

  void _partial(int session, String t) {
    if (session != _session || !active) return;
    _text = t;
    _sink?.call(t, false);
    notifyListeners();
  }

  void _level(int session, double l) {
    if (session != _session || !listening) return;
    _levels
      ..removeAt(0)
      ..add(l.clamp(0.0, 1.0));
    notifyListeners();
  }

  void _final(int session, String t) {
    if (session != _session || !active) return;
    final text = t.trim().isEmpty ? _text.trim() : t.trim();
    _stopTimers();
    if (text.isEmpty) return _fail(VoiceFailure.noSpeech);
    _text = text;
    _phase = VoicePhase.idle;
    _sink?.call(text, true);
    notifyListeners();
  }

  void _error(int session, VoiceFailure f, String? message) {
    if (session != _session || !active) return;
    // On-device recognition broke: record and send to the server instead.
    final fallback = server;
    final recoverable =
        f == VoiceFailure.unavailable ||
        f == VoiceFailure.failed ||
        f == VoiceFailure.network;
    if (_engine == onDevice &&
        !_fellBack &&
        fallback != null &&
        recoverable &&
        _phase == VoicePhase.listening) {
      _fellBack = true;
      final next = ++_session;
      unawaited(_engine?.cancel());
      _stopTimers();
      _levels.fillRange(0, _levels.length, 0);
      unawaited(_begin(fallback, next));
      return;
    }
    if (_text.isNotEmpty && f == VoiceFailure.noSpeech) {
      return _final(session, _text);
    }
    _stopTimers();
    _fail(f, message);
  }

  /// Ends listening; the text arrives through the sink.
  Future<void> stop() async {
    final engine = _engine;
    if (!listening || engine == null) return;
    final session = _session;
    _phase = VoicePhase.transcribing;
    _tick?.cancel();
    _limit?.cancel();
    Haptics.recordStop();
    notifyListeners();
    if (!engine.batch) {
      // If the recognizer never reports a final result, use the last partial.
      _finishTimer = Timer(
        VoiceConfig.finishTimeout,
        () => _final(session, _text),
      );
    }
    await engine.stop();
  }

  /// Drops the dictation; nothing reaches the sink.
  Future<void> cancel() async {
    if (!active) return;
    ++_session;
    final engine = _engine;
    _stopTimers();
    _phase = VoicePhase.idle;
    _text = '';
    Haptics.recordStop();
    notifyListeners();
    await engine?.cancel();
  }

  /// Clears an error.
  void dismiss() {
    if (_phase != VoicePhase.error) return;
    _phase = VoicePhase.idle;
    _failure = null;
    _message = null;
    notifyListeners();
  }

  void _reset() {
    _stopTimers();
    _failure = null;
    _message = null;
    _text = '';
    _fellBack = false;
    _levels.fillRange(0, _levels.length, 0);
  }

  void _fail(VoiceFailure f, [String? message]) {
    _stopTimers();
    _phase = VoicePhase.error;
    _failure = f;
    _message = message;
    Haptics.error();
    notifyListeners();
  }

  void _stopTimers() {
    _tick?.cancel();
    _limit?.cancel();
    _finishTimer?.cancel();
    _tick = _limit = _finishTimer = null;
  }

  @override
  void dispose() {
    ++_session;
    _stopTimers();
    unawaited(_engine?.cancel());
    onDevice.dispose();
    server?.dispose();
    super.dispose();
  }
}
