import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/connections.dart';
import 'api_client.dart';
import 'chat_api.dart';

/// A failed /connections call, with the backend's error code when it sent one
/// (e.g. `github_oauth_not_configured`).
class ConnectionsException extends ApiException {
  const ConnectionsException(super.message, {super.status, super.code});

  bool get notConfigured => code == ConnectCodes.notConfigured;
}

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
String _s(Object? v) => v is String ? v : '';
List<String> _strings(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is String) e,
];

/// One linked account. The server never sends tokens.
class Connection {
  Connection(Map<String, dynamic> j)
    : provider = _s(j['provider']),
      login = _s(j['accountLogin']),
      avatarUrl = _s(j['avatarUrl']),
      scopes = _strings(j['scopes']),
      missingScopes = _strings(j['missingScopes']),
      createdAt = _date(j['createdAt']),
      lastUsedAt = _date(j['lastUsedAt']),
      accountName = _s(j['accountName']),
      accountEmail = _s(j['accountEmail']),
      meta = j['meta'] is Map<String, dynamic>
          ? j['meta'] as Map<String, dynamic>
          : const {},
      needsReauth = j['needsReauth'] == true;

  final String provider, login, avatarUrl;

  /// Account name and email (Google Drive, Notion); empty for GitHub.
  final String accountName, accountEmail;

  /// Non-secret extras (Notion: workspaceName, workspaceIcon).
  final Map<String, dynamic> meta;

  /// The app stopped accepting sparky's access: offer Reconnect.
  final bool needsReauth;

  String get workspaceName => _s(meta['workspaceName']);
  String get workspaceIcon => _s(meta['workspaceIcon']);
  final List<String> scopes;

  /// Scopes sparky asks for that this grant lacks; reconnecting adds them.
  final List<String> missingScopes;
  final DateTime? createdAt, lastUsedAt;
}

/// `GET /connections`.
class ConnectionsState {
  ConnectionsState(Map<String, dynamic> j)
    : items = [
        for (final c in (j['items'] as List? ?? const []))
          if (c is Map<String, dynamic>) Connection(c),
      ],
      githubConfigured =
          ((j['providers'] as Map?)?['github'] as Map?)?['configured'] == true,
      githubWeb = ((j['providers'] as Map?)?['github'] as Map?)?['web'] == true,
      configured = {
        for (final e in ((j['providers'] as Map?) ?? const {}).entries)
          if (e.key is String && e.value is Map)
            e.key as String: (e.value as Map)['configured'] == true,
      },
      pickerReady =
          ((j['providers'] as Map?)?['google_drive'] as Map?)?['picker'] ==
          true,
      isOwner = j['isOwner'] == true;

  final List<Connection> items;
  final bool githubConfigured, isOwner;

  /// One-tap OAuth web flow available (else the device code).
  final bool githubWeb;

  /// Per provider: the server has its keys (Google Drive, Notion, GitHub).
  final Map<String, bool> configured;

  /// The Google Drive file picker has its API key on the server.
  final bool pickerReady;

  Connection? byProvider(String provider) =>
      items.where((c) => c.provider == provider).firstOrNull;

  Connection? get github =>
      items.where((c) => c.provider == ConnectProviders.github).firstOrNull;
}

/// `POST /connections/github/device`.
class DeviceStart {
  DeviceStart(Map<String, dynamic> j)
    : flowId = _s(j['flowId']),
      userCode = _s(j['userCode']),
      verificationUri = _s(j['verificationUri']),
      verificationUriComplete = j['verificationUriComplete'] as String?,
      expiresIn = (j['expiresIn'] as num?)?.round() ?? 900,
      interval =
          (j['interval'] as num?)?.round() ?? ConnectDurations.defaultInterval;

  final String flowId, userCode, verificationUri;
  final String? verificationUriComplete;
  final int expiresIn, interval;

  /// Where to send the user: the prefilled page when GitHub offers one.
  String get openUrl => (verificationUriComplete?.isNotEmpty ?? false)
      ? verificationUriComplete!
      : verificationUri;
}

/// `GET /connections/github/device/:flowId`.
class DevicePoll {
  DevicePoll(Map<String, dynamic> j)
    : status = _s(j['status']),
      interval =
          (j['interval'] as num?)?.round() ?? ConnectDurations.defaultInterval,
      expiresIn = (j['expiresIn'] as num?)?.round() ?? 0,
      error = j['error'] as String?;

  final String status;
  final int interval, expiresIn;
  final String? error;
}

/// The signed-in user's linked accounts (`/connections`).
class ConnectionsApi {
  ConnectionsApi._();
  static final instance = ConnectionsApi._();

  Future<Map<String, dynamic>> _send(String method, String path) async {
    final request = http.Request(
      method,
      Uri.parse('${AppConfig.apiBaseUrl}/connections$path'),
    )..headers.addAll(apiHeaders());
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await apiHttp.send(request).timeout(ConnectDurations.request),
      );
    } catch (_) {
      throw const ConnectionsException(ConnectStrings.failed);
    }
    if (res.statusCode >= 400) {
      throw ConnectionsException(
        errorMessage(res.body, res.statusCode),
        status: res.statusCode,
        code: errorCode(res.body),
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<ConnectionsState> list() async =>
      ConnectionsState(await _send('GET', ''));

  Future<DeviceStart> startGithub() async =>
      DeviceStart(await _send('POST', '/github/device'));

  Future<DevicePoll> pollGithub(String flowId) async => DevicePoll(
    await _send('GET', '/github/device/${Uri.encodeComponent(flowId)}'),
  );

  Future<void> disconnectGithub() => _send('DELETE', '/github');
}
