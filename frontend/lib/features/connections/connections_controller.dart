import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/connections.dart';
import '../../core/constants/sso_constants.dart';
import '../auth/sso/github_web_auth.dart';
import '../../data/connect_api.dart';
import '../../data/connections_api.dart';

/// Where the GitHub connection stands, for the card and Settings.
enum GithubPhase {
  loading,
  loadFailed,
  notConfigured,
  idle,
  starting,
  waiting,

  /// One-tap web flow: GitHub is open in the GitHub app or a browser.
  browser,
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
  ConnectionsController._() {
    final web = GithubWebAuth.instance;
    web.addListener(notifyListeners);
    web.outcomes.listen((o) {
      if (o.ok || o.mode != GithubWeb.connect) return;
      // The web flow failed: show it like a failed device flow.
      web.cancel();
      _end(o.denied ? ConnectFlowStatus.denied : 'failed', o.message);
    });
  }
  static final instance = ConnectionsController._();

  GithubWebAuth get web => GithubWebAuth.instance;

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
    if (web.activeFor(GithubWeb.connect)) {
      if (web.phase == GithubWebPhase.failed) return GithubPhase.failed;
      return GithubPhase.browser;
    }
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

  /// CONNECT: the one-tap web flow (falls back to the code when the server
  /// has no client secret).
  Future<void> connectGithub() async {
    if (!(state?.githubWeb ?? false)) {
      await startGithub();
      return;
    }
    _stopTimers();
    flow = null;
    _flowEnd = null;
    flowError = null;
    justConnected = false;
    final ok = await web.start(GithubWeb.connect);
    if (!ok && web.activeFor(GithubWeb.connect)) {
      final message = web.error;
      web.cancel();
      _end('failed', message);
    }
  }

  /// USE A CODE INSTEAD: drops the web flow and starts the device flow.
  Future<void> useCode() async {
    if (web.activeFor(GithubWeb.connect)) web.cancel();
    await startGithub();
  }

  /// A web flow connected (or linked) GitHub: reload.
  Future<void> githubWebConnected({required bool justConnected}) async {
    _end('', null);
    _flowEnd = null;
    this.justConnected = justConnected;
    await refresh();
  }

  /// Drops the running flow (back to CONNECT).
  void cancelFlow() {
    if (web.activeFor(GithubWeb.connect)) web.cancel();
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

  // ---- connected apps (Google Drive, Notion) ------------------------------

  /// The linked account of [provider], if any.
  Connection? connection(String provider) => state?.byProvider(provider);

  /// The server has [provider]'s keys. Null while the list is loading.
  bool? configured(String provider) => state?.configured[provider];

  /// A connect flow of a connected app finished: reload the list.
  Future<void> appConnected() => refresh();

  /// Disconnects [provider] (the server revokes the grant), then reloads.
  Future<void> disconnectApp(String provider) async {
    await ConnectApi.instance.disconnect(provider);
    state?.items.removeWhere((c) => c.provider == provider);
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
