import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/connections.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../data/sso_api.dart';

enum DeviceFlowPhase { starting, waiting, done, expired, denied, failed }

/// One GitHub device flow for sign-in (signed out) or linking (Profile):
/// gets a code, counts down, and polls the backend at the interval GitHub
/// asked for. [result] holds the finished poll (with the session when
/// signing in). Lives as long as its sheet.
class GithubDeviceFlow extends ChangeNotifier {
  GithubDeviceFlow({required this.start, required this.poll});

  /// Sign-in: [SsoApi.startGithub]; link: [SsoApi.startGithubLink].
  final Future<DeviceStart> Function() start;
  final Future<SsoPoll> Function(String flowId) poll;

  DeviceFlowPhase phase = DeviceFlowPhase.starting;
  DeviceStart? flow;
  SsoPoll? result;
  String? error;

  DateTime? _ends;
  Timer? _poll, _tick;
  bool _disposed = false;

  int get secondsLeft => _ends == null
      ? 0
      : _ends!.difference(DateTime.now()).inSeconds.clamp(0, 1 << 20);

  /// Fraction of the code's lifetime left (1 = fresh).
  double get timeLeftFraction {
    final f = flow;
    if (f == null || f.expiresIn <= 0) return 0;
    return (secondsLeft / f.expiresIn).clamp(0.0, 1.0);
  }

  /// Starts (or restarts) the flow.
  Future<void> begin() async {
    _stop();
    phase = DeviceFlowPhase.starting;
    flow = null;
    result = null;
    error = null;
    _notify();
    try {
      final f = await start();
      if (_disposed) return;
      flow = f;
      _ends = DateTime.now().add(Duration(seconds: f.expiresIn));
      phase = DeviceFlowPhase.waiting;
      _schedule(f.interval);
      _tick = Timer.periodic(ConnectDurations.tick, (_) => _onTick());
    } on SsoException catch (e) {
      phase = DeviceFlowPhase.failed;
      error = e.message;
    }
    _notify();
  }

  void _onTick() {
    if (phase != DeviceFlowPhase.waiting) return;
    if (secondsLeft <= 0) return _end(DeviceFlowPhase.expired);
    _notify();
  }

  void _schedule(int seconds) {
    _poll?.cancel();
    final s = seconds > 0 ? seconds : ConnectDurations.defaultInterval;
    _poll = Timer(Duration(seconds: s), _pollOnce);
  }

  Future<void> _pollOnce() async {
    final f = flow;
    if (f == null || phase != DeviceFlowPhase.waiting) return;
    final SsoPoll r;
    try {
      r = await poll(f.flowId);
    } on SsoException catch (e) {
      if (flow != f || _disposed) return;
      // 404: the server forgot the flow (restart); 4xx: give up. Else retry.
      final s = e.status ?? 0;
      if (s >= 400 && s < 500 && s != 429) {
        _end(DeviceFlowPhase.failed, e.message);
      } else {
        _schedule(f.interval);
      }
      return;
    }
    if (flow != f || _disposed) return;
    if (r.waiting) return _schedule(r.interval);
    switch (r.status) {
      case SsoFlowStatus.ok:
        result = r;
        _end(DeviceFlowPhase.done);
      case SsoFlowStatus.expired:
        _end(DeviceFlowPhase.expired);
      case SsoFlowStatus.denied:
        _end(DeviceFlowPhase.denied);
      default:
        _end(DeviceFlowPhase.failed, r.error ?? SsoStrings.failed);
    }
  }

  void _end(DeviceFlowPhase p, [String? message]) {
    _stop();
    phase = p;
    error = message;
    _notify();
  }

  void _stop() {
    _poll?.cancel();
    _tick?.cancel();
    _poll = null;
    _tick = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}
