import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/error_copy.dart';
import '../../core/app_messenger.dart';
import '../../core/constants/connectors.dart';
import '../../core/haptics.dart';
import '../../core/platform/browsers.dart';
import '../../core/platform/deep_links.dart';
import '../../data/connect_api.dart';
import '../connections/connections_controller.dart';

enum ConnectorPhase { idle, starting, waiting, finishing, failed }

/// What a flow was for.
enum ConnectorFlow { connect, picker }

/// How one flow ended.
class ConnectorOutcome {
  const ConnectorOutcome({
    required this.provider,
    required this.flow,
    this.message,
    this.code,
    this.picked = 0,
    this.imported = 0,
    this.skipped = 0,
    this.limited = 0,
  });

  final String provider;
  final ConnectorFlow flow;
  final String? message, code;

  /// Drive picker: files sparky can now see.
  final int picked;

  /// Drive picker, folders: files imported from them, skipped, and folders
  /// Google would not let sparky open (the user picked files inside them).
  final int imported, skipped, limited;

  bool get ok => message == null;
}

/// The flow waiting for its deep link; persisted so a cold start can finish it.
class _Pending {
  _Pending(this.provider, this.flow, this.state, this.url, this.at);

  factory _Pending.fromJson(Map<String, dynamic> j) => _Pending(
    j['provider'] as String,
    ConnectorFlow.values.byName(j['flow'] as String? ?? 'connect'),
    j['state'] as String,
    j['url'] as String? ?? '',
    DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
  );

  final String provider, state, url;
  final ConnectorFlow flow;
  final DateTime at;

  bool get stale =>
      DateTime.now().difference(at) > ConnectorDurations.pendingTtl;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'flow': flow.name,
    'state': state,
    'url': url,
    'at': at.millisecondsSinceEpoch,
  };
}

/// Connect Google Drive / Notion over the OAuth web flow, and run the Drive
/// picker: start on the backend, open the page in a Custom Tab, wait for
/// `sparky://auth/connect?provider&ticket&state` (or `mode=picker&picked`),
/// redeem the ticket. Only the flow this app started counts (state match).
class ConnectorAuth extends ChangeNotifier {
  ConnectorAuth._();
  static final instance = ConnectorAuth._();

  /// Swapped in tests.
  ConnectApi get _api => ConnectApi.instance;

  ConnectorPhase phase = ConnectorPhase.idle;
  String? provider;
  ConnectorFlow? flow;
  String? error;

  _Pending? _pending;
  bool _started = false;
  final _outcomes = StreamController<ConnectorOutcome>.broadcast();

  Stream<ConnectorOutcome> get outcomes => _outcomes.stream;

  static const _prefsKey = 'connector_web_pending';

  /// A flow of [p] is running (or just failed).
  bool activeFor(String p, [ConnectorFlow f = ConnectorFlow.connect]) =>
      provider == p && flow == f && phase != ConnectorPhase.idle;

  bool busyFor(String p, [ConnectorFlow f = ConnectorFlow.connect]) =>
      activeFor(p, f) && phase != ConnectorPhase.failed;

  Future<void> init() async {
    if (_started) return;
    _started = true;
    DeepLinks.links.listen(_onLink);
    final first = await DeepLinks.initial();
    if (first != null) await _onLink(first);
  }

  /// CONTINUE TO GOOGLE / NOTION.
  Future<bool> connect(String p) =>
      _start(p, ConnectorFlow.connect, () => _api.start(p));

  /// PICK FILES FROM DRIVE.
  Future<bool> pickDriveFiles() => _start(
    ConnectorIds.drive,
    ConnectorFlow.picker,
    () => _api.startPicker(),
  );

  Future<bool> _start(
    String p,
    ConnectorFlow f,
    Future<ConnectStart> Function() begin,
  ) async {
    if (phase == ConnectorPhase.starting || phase == ConnectorPhase.finishing) {
      return false;
    }
    provider = p;
    flow = f;
    phase = ConnectorPhase.starting;
    error = null;
    notifyListeners();
    try {
      final s = await begin();
      if (provider != p || phase != ConnectorPhase.starting) return false;
      await _save(_Pending(p, f, s.state, s.url, DateTime.now()));
      if (!await _open(s.url)) {
        await _save(null);
        _fail(ConnectorStrings.failed);
        return false;
      }
      phase = ConnectorPhase.waiting;
      notifyListeners();
      return true;
    } on ConnectException catch (e) {
      if (provider == p) _fail(friendlyException(e));
      return false;
    }
  }

  /// Opens the waiting flow's page again (the user closed the tab).
  Future<void> reopen() async {
    final p = _pending;
    if (p == null || phase != ConnectorPhase.waiting) return;
    await _open(p.url);
  }

  void cancel() {
    unawaited(_save(null));
    provider = null;
    flow = null;
    phase = ConnectorPhase.idle;
    error = null;
    notifyListeners();
  }

  /// A Custom Tab (Google allows OAuth there, unlike web views); the saved
  /// browser when Custom Tabs are not available.
  Future<bool> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return true;
    } catch (_) {}
    return Browsers.openUrl(url);
  }

  @visibleForTesting
  Future<void> handleLink(Uri uri) => _onLink(uri);

  Future<void> _onLink(Uri uri) async {
    if (uri.scheme != ConnectorLink.scheme ||
        uri.host != ConnectorLink.host ||
        uri.path != ConnectorLink.path) {
      return;
    }
    final q = uri.queryParameters;
    final pending = _pending ?? await _load();
    if (pending == null ||
        pending.stale ||
        q[ConnectorLink.state] != pending.state ||
        q[ConnectorLink.provider] != pending.provider) {
      return;
    }
    final cold = phase == ConnectorPhase.idle;
    await _save(null);
    provider = pending.provider;
    flow = pending.flow;
    final err = q[ConnectorLink.error];
    if (pending.flow == ConnectorFlow.picker) {
      if (err != null) {
        return _finish(
          ConnectorOutcome(
            provider: pending.provider,
            flow: pending.flow,
            code: err,
            message: DriveStrings.pickerUnavailable,
          ),
          cold,
        );
      }
      return _finish(
        ConnectorOutcome(
          provider: pending.provider,
          flow: pending.flow,
          picked: int.tryParse(q[ConnectorLink.picked] ?? '') ?? 0,
          imported: int.tryParse(q[ConnectorLink.imported] ?? '') ?? 0,
          skipped: int.tryParse(q[ConnectorLink.skipped] ?? '') ?? 0,
          limited: int.tryParse(q[ConnectorLink.limited] ?? '') ?? 0,
        ),
        cold,
      );
    }
    final ticket = q[ConnectorLink.ticket];
    if (err != null || ticket == null || ticket.isEmpty) {
      return _finish(
        ConnectorOutcome(
          provider: pending.provider,
          flow: pending.flow,
          code: err,
          message: safeOr(q[ConnectorLink.message], ConnectorStrings.failed),
        ),
        cold,
      );
    }
    phase = ConnectorPhase.finishing;
    notifyListeners();
    try {
      await _api.redeem(pending.provider, ticket);
      await ConnectionsController.instance.appConnected();
      _finish(
        ConnectorOutcome(provider: pending.provider, flow: pending.flow),
        cold,
      );
    } on ConnectException catch (e) {
      _finish(
        ConnectorOutcome(
          provider: pending.provider,
          flow: pending.flow,
          code: e.code,
          message: friendlyException(e),
        ),
        cold,
      );
    }
  }

  void _finish(ConnectorOutcome o, bool cold) {
    if (o.ok) {
      Haptics.received();
      phase = ConnectorPhase.idle;
      error = null;
      if (o.flow == ConnectorFlow.picker) {
        AppMessenger.show(
          DriveStrings.pickedSummary(
            picked: o.picked,
            imported: o.imported,
            skipped: o.skipped,
            limited: o.limited,
          ),
          duration: o.limited > 0 ? ConnectorDurations.longNotice : null,
        );
      } else {
        AppMessenger.show(
          ConnectorStrings.connectedAs(
            o.provider == ConnectorIds.drive
                ? DriveStrings.title
                : NotionStrings.title,
          ),
        );
      }
    } else {
      Haptics.error();
      phase = ConnectorPhase.failed;
      final text = safeOr(o.message, ConnectorStrings.failed);
      error = text;
      if (cold || o.flow == ConnectorFlow.picker) AppMessenger.show(text);
    }
    notifyListeners();
    _outcomes.add(o);
  }

  void _fail(String message) {
    Haptics.error();
    phase = ConnectorPhase.failed;
    error = message;
    notifyListeners();
  }

  Future<_Pending?> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
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
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, jsonEncode(p));
      }
    } catch (_) {}
  }
}
