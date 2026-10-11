import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/connections.dart';
import '../../data/connections_api.dart';

/// Where the GitHub connection stands, for the card and Settings.
enum GithubPhase {
  loading,
  loadFailed,
  notConfigured,
  idle,
  starting,
  waiting,
  connected,
  expired,
  denied,
  failed,
}

/// The user's linked accounts plus the one running GitHub device flow.
///
/// A singleton so the chat card, Settings and the sheet show the same state,
/// and a flow keeps polling while its card scrolls out of view. Polls the
/// backend at the interval GitHub asked for (the backend never asks GitHub
/// faster than that either).
class ConnectionsController extends ChangeNotifier {
  ConnectionsController._();
  static final instance = ConnectionsController._();

  final _api = ConnectionsApi.instance;

  ConnectionsState? state;
  bool loading = false;
  bool loadFailed = false;

  /// Set when starting a flow answered "not configured" (even if the list
  /// said otherwise, e.g. the server restarted without the env var).
  bool _notConfigured = false;

  DeviceStart? flow;
  DateTime? _flowEnds;
  String? _flowEnd; // expired | denied | failed
  String? flowError;
  bool starting = false;

  /// True right after a successful sign-in (shows "Authentication successful").
  bool justConnected = false;

  Timer? _poll, _tick;

  Connection? get github => state?.github;
  bool get isOwner => state?.isOwner ?? false;

  /// Seconds left on the current code.
  int get secondsLeft => _flowEnds == null
      ? 0
      : _flowEnds!.difference(DateTime.now()).inSeconds.clamp(0, 1 << 20);

  /// Fraction of the code's lifetime left (1 = fresh).
  double get timeLeftFraction {
    final f = flow;
    if (f == null || f.expiresIn <= 0) return 0;
    return (secondsLeft / f.expiresIn).clamp(0.0, 1.0);
  }

  GithubPhase get githubPhase {
    if (github != null) return GithubPhase.connected;
    if (starting) return GithubPhase.starting;
    if (flow != null) return GithubPhase.waiting;
    switch (_flowEnd) {
      case ConnectFlowStatus.expired:
        return GithubPhase.expired;
      case ConnectFlowStatus.denied:
        return GithubPhase.denied;
      case 'failed':
        return GithubPhase.failed;
    }
    if (_notConfigured) return GithubPhase.notConfigured;
    final s = state;
    if (s == null) {
      return loadFailed ? GithubPhase.loadFailed : GithubPhase.loading;
    }
    if (!s.githubConfigured) return GithubPhase.notConfigured;
    return GithubPhase.idle;
  }

  /// Loads once; later calls reuse the result.
  Future<void> ensureLoaded() async {
    if (state != null || loading) return;
    await refresh();
  }

  Future<void> refresh() async {
    loading = true;
    loadFailed = false;
    notifyListeners();
    try {
      state = await _api.list();
      if (state!.githubConfigured) _notConfigured = false;
    } catch (_) {
      loadFailed = state == null;
    }
    loading = false;
    notifyListeners();
  }

  /// Starts the device flow. Returns the new flow, or null on failure.
  Future<DeviceStart?> startGithub() async {
    if (starting) return null;
    _stopTimers();
    starting = true;
    flow = null;
    _flowEnd = null;
    flowError = null;
    justConnected = false;
    notifyListeners();
    try {
      final f = await _api.startGithub();
      flow = f;
      _flowEnds = DateTime.now().add(Duration(seconds: f.expiresIn));
      _schedulePoll(f.interval);
      _tick = Timer.periodic(ConnectDurations.tick, (_) => _onTick());
      return f;
    } on ConnectionsException catch (e) {
      if (e.notConfigured) {
        _notConfigured = true;
      } else {
        _flowEnd = 'failed';
        flowError = e.message;
      }
      return null;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  /// Drops the running flow (back to CONNECT).
  void cancelFlow() {
    _stopTimers();
    flow = null;
    _flowEnd = null;
    flowError = null;
    notifyListeners();
  }

  Future<void> disconnectGithub() async {
    await _api.disconnectGithub();
    justConnected = false;
    _flowEnd = null;
    final s = state;
    if (s != null) {
      s.items.removeWhere((c) => c.provider == ConnectProviders.github);
    }
    notifyListeners();
    await refresh();
  }

  /// Signed out: forget everything about the previous user.
  void reset() {
    _stopTimers();
    state = null;
    loading = false;
    loadFailed = false;
    _notConfigured = false;
    flow = null;
    _flowEnds = null;
    _flowEnd = null;
    flowError = null;
    starting = false;
    justConnected = false;
    notifyListeners();
  }

  void _onTick() {
    if (flow == null) return;
    if (secondsLeft <= 0) {
      _end(ConnectFlowStatus.expired);
      return;
    }
    notifyListeners();
  }

  void _schedulePoll(int seconds) {
    _poll?.cancel();
    final s = seconds > 0 ? seconds : ConnectDurations.defaultInterval;
    _poll = Timer(Duration(seconds: s), _pollOnce);
  }

  Future<void> _pollOnce() async {
    final f = flow;
    if (f == null) return;
    DevicePoll r;
    try {
      r = await _api.pollGithub(f.flowId);
    } on ConnectionsException catch (e) {
      if (flow != f) return;
      // 404: the server forgot the flow (restart): start over.
      if (e.status == 404) {
        _end('failed', e.message);
      } else {
        _schedulePoll(f.interval);
      }
      return;
    }
    if (flow != f) return;
    switch (r.status) {
      case ConnectFlowStatus.pending:
        _schedulePoll(r.interval);
      case ConnectFlowStatus.connected:
        _stopTimers();
        flow = null;
        justConnected = true;
        await refresh();
      case ConnectFlowStatus.expired || ConnectFlowStatus.denied:
        _end(r.status);
      default:
        _end('failed', r.error);
    }
  }

  void _end(String how, [String? error]) {
    _stopTimers();
    flow = null;
    _flowEnd = how;
    flowError = error;
    notifyListeners();
  }

  void _stopTimers() {
    _poll?.cancel();
    _tick?.cancel();
    _poll = null;
    _tick = null;
  }
}
