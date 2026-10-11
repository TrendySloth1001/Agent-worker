import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app_messenger.dart';
import '../../../core/constants/app_prefs.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/platform/browsers.dart';
import '../../../core/platform/deep_links.dart';
import '../../../data/sso_api.dart';
import '../../connections/connections_controller.dart';
import '../auth_controller.dart';

enum GithubWebPhase { idle, starting, waiting, redeeming, failed }

/// How one web flow ended.
class GithubWebOutcome {
  const GithubWebOutcome.ok(this.mode) : code = null, message = null;
  const GithubWebOutcome.failed(this.mode, this.message, {this.code});

  final String mode;
  final String? code, message;

  bool get ok => message == null;
  bool get denied => code == GithubWeb.errDenied;
}

/// The flow waiting for its deep link; persisted so a cold start can finish it.
class _Pending {
  _Pending(this.state, this.mode, this.url, this.at);

  factory _Pending.fromJson(Map<String, dynamic> j) => _Pending(
    j['state'] as String,
    j['mode'] as String,
    j['url'] as String? ?? '',
    DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
  );

  final String state, mode, url;
  final DateTime at;

  bool get stale =>
      DateTime.now().difference(at) > GithubWebDurations.pendingTtl;

  Map<String, dynamic> toJson() => {
    'state': state,
    'mode': mode,
    'url': url,
    'at': at.millisecondsSinceEpoch,
  };
}

/// "Continue with GitHub", "Connect GitHub" and Profile → LINK over the OAuth
/// web flow: start on the backend, open GitHub (the GitHub app when it can
/// handle the authorize URL, else the chosen browser), wait for
/// `sparky://auth/github?ticket&state`, redeem the ticket.
///
/// One flow at a time. A link counts only when its state matches the pending
/// flow (stray or replayed links are ignored). The result is applied here
/// (session stored, connections refreshed), so it also works when the app was
/// killed while the user was on GitHub; screens only follow [phase] and
/// [outcomes].
class GithubWebAuth extends ChangeNotifier {
  GithubWebAuth._();
  static final instance = GithubWebAuth._();

  GithubWebPhase phase = GithubWebPhase.idle;

  /// The running (or last failed) flow's mode.
  String? mode;

  /// GitHub opened in the GitHub app rather than a browser.
  bool openedInApp = false;
  String? error;

  _Pending? _pending;
  bool _started = false;
  final _outcomes = StreamController<GithubWebOutcome>.broadcast();

  Stream<GithubWebOutcome> get outcomes => _outcomes.stream;

  /// A flow of [m] is on screen (starting, waiting, redeeming or failed).
  bool activeFor(String m) => mode == m && phase != GithubWebPhase.idle;

  bool get busy =>
      phase == GithubWebPhase.starting ||
      phase == GithubWebPhase.waiting ||
      phase == GithubWebPhase.redeeming;

  /// Listens for links and finishes a flow the app was relaunched for.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    DeepLinks.links.listen(_onLink);
    final first = await DeepLinks.initial();
    if (first != null) await _onLink(first);
  }

  /// Starts a flow of [m] ([GithubWeb.signin] / connect / link) and opens
  /// GitHub. False when it could not (see [error]).
  Future<bool> start(String m) async {
    if (phase == GithubWebPhase.starting || phase == GithubWebPhase.redeeming) {
      return false;
    }
    mode = m;
    phase = GithubWebPhase.starting;
    error = null;
    openedInApp = false;
    notifyListeners();
    try {
      final s = await SsoApi.instance.startGithubWeb(
        m,
        device: m == GithubWeb.signin ? AuthController.device : null,
      );
      if (mode != m || phase != GithubWebPhase.starting) return false;
      await _save(_Pending(s.state, m, s.authorizeUrl, DateTime.now()));
      if (!await _open(s.authorizeUrl)) {
        await _save(null);
        _fail(GithubWebStrings.openFailed);
        return false;
      }
      phase = GithubWebPhase.waiting;
      notifyListeners();
      return true;
    } on SsoException catch (e) {
      if (mode == m) _fail(e.message);
      return false;
    }
  }

  /// Opens GitHub again for the waiting flow (the user closed the tab).
  Future<void> reopen() async {
    final p = _pending;
    if (p == null || phase != GithubWebPhase.waiting) return;
    await _open(p.url);
    notifyListeners();
  }

  /// Drops the flow; a late link for it is then ignored.
  void cancel() {
    unawaited(_save(null));
    mode = null;
    phase = GithubWebPhase.idle;
    error = null;
    openedInApp = false;
    notifyListeners();
  }

  /// GitHub app when it handles [url] itself, else the saved browser.
  Future<bool> _open(String url) async {
    final handlers = await Browsers.resolvesUrl(url);
    if (handlers.contains(GithubWeb.githubAppPackage) &&
        await Browsers.openUrl(url, package: GithubWeb.githubAppPackage)) {
      openedInApp = true;
      return true;
    }
    openedInApp = false;
    var browser = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      browser = prefs.getString(AppPrefs.browserPackage) ?? '';
    } catch (_) {}
    return Browsers.openUrl(url, package: browser);
  }

  Future<void> _onLink(Uri uri) async {
    if (uri.scheme != GithubWeb.scheme ||
        uri.host != GithubWeb.host ||
        uri.path != GithubWeb.path) {
      return;
    }
    final q = uri.queryParameters;
    final pending = _pending ?? await _load();
    // Only the flow this app started; anything else is a stray link.
    if (pending == null ||
        pending.stale ||
        q[GithubWeb.state] != pending.state) {
      return;
    }
    // Nothing on screen is waiting (cold start): report failures here too.
    final cold = phase == GithubWebPhase.idle;
    await _save(null);
    mode = pending.mode;
    final err = q[GithubWeb.error];
    final ticket = q[GithubWeb.ticket];
    if (err != null || ticket == null || ticket.isEmpty) {
      final message = err == GithubWeb.errDenied
          ? GithubWebStrings.denied
          : (q[GithubWeb.message] ?? GithubWebStrings.failed);
      return _finish(
        GithubWebOutcome.failed(pending.mode, message, code: err),
        cold,
      );
    }
    phase = GithubWebPhase.redeeming;
    notifyListeners();
    final signin = pending.mode == GithubWeb.signin;
    try {
      await _authSettled();
      if (!signin && !AuthController.instance.signedIn) {
        return _finish(
          GithubWebOutcome.failed(pending.mode, GithubWebStrings.failed),
          cold,
        );
      }
      final r = await SsoApi.instance.redeemGithubWeb(ticket, pending.mode);
      if (signin) {
        await AuthController.instance.signInWithSession(r);
      } else {
        await ConnectionsController.instance.githubWebConnected(
          justConnected: pending.mode == GithubWeb.connect,
        );
      }
      _finish(GithubWebOutcome.ok(pending.mode), cold);
    } on SsoException catch (e) {
      _finish(
        GithubWebOutcome.failed(pending.mode, e.message, code: e.code),
        cold,
      );
    }
  }

  void _finish(GithubWebOutcome o, bool cold) {
    if (o.ok) {
      Haptics.received();
      phase = GithubWebPhase.idle;
      error = null;
      AppMessenger.show(switch (o.mode) {
        GithubWeb.signin => GithubWebStrings.signedIn,
        GithubWeb.connect => GithubWebStrings.connected,
        _ => GithubWebStrings.linked,
      });
    } else {
      Haptics.error();
      phase = GithubWebPhase.failed;
      error = o.message;
      if (cold) AppMessenger.show(o.message ?? GithubWebStrings.failed);
    }
    notifyListeners();
    _outcomes.add(o);
  }

  void _fail(String message) {
    Haptics.error();
    phase = GithubWebPhase.failed;
    error = message;
    notifyListeners();
  }

  /// Waits for the saved session to be restored (cold start).
  Future<void> _authSettled() async {
    final auth = AuthController.instance;
    if (auth.status != AuthStatus.restoring) return;
    final done = Completer<void>();
    void check() {
      if (auth.status != AuthStatus.restoring && !done.isCompleted) {
        done.complete();
      }
    }

    auth.addListener(check);
    try {
      await done.future;
    } finally {
      auth.removeListener(check);
    }
  }

  Future<_Pending?> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppPrefs.githubWebPending);
      if (raw == null) return null;
      return _pending = _Pending.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(_Pending? p) async {
    _pending = p;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (p == null) {
        await prefs.remove(AppPrefs.githubWebPending);
      } else {
        await prefs.setString(AppPrefs.githubWebPending, jsonEncode(p));
      }
    } catch (_) {
      // Only costs finishing after a cold start.
    }
  }
}
