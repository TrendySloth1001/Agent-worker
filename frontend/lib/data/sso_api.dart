import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/auth_constants.dart';
import '../core/constants/connections.dart';
import '../core/constants/sso_constants.dart';
import 'api_client.dart';
import 'chat_api.dart';
import 'connections_api.dart';

export 'connections_api.dart' show DeviceStart;

/// A failed sign-in call, with the backend's error code when it sent one.
class SsoException extends ApiException {
  const SsoException(super.message, {super.status, this.code});
  final String? code;
}

/// `GET /auth/providers`: which "Continue with ..." buttons to show.
class SsoProviders {
  const SsoProviders({this.github = false, this.googleWebClientId});

  SsoProviders.fromJson(Map<String, dynamic> j)
    : github = j['github'] == true,
      googleWebClientId = switch ((j['google'] as Map?)?['webClientId']) {
        final String id when id.isNotEmpty => id,
        _ => null,
      };

  final bool github;

  /// The Web OAuth client id (Google's serverClientId); null hides Google.
  final String? googleWebClientId;

  bool get google => googleWebClientId != null;
  bool get any => github || google;
}

/// One device-flow poll (sign-in or link).
class SsoPoll {
  SsoPoll(Map<String, dynamic> j)
    : status = j['status'] as String? ?? '',
      interval =
          (j['interval'] as num?)?.round() ?? ConnectDurations.defaultInterval,
      code = j['code'] as String?,
      error = j['error'] as String?,
      session = j['session'] as Map<String, dynamic>?;

  final String status;
  final int interval;
  final String? code, error;

  /// Sign-in only: same shape as the /auth/login response.
  final Map<String, dynamic>? session;

  bool get waiting =>
      status == SsoFlowStatus.pending || status == SsoFlowStatus.slowDown;
}

/// One linked GitHub/Google account (`GET /auth/identities`).
class LinkedIdentity {
  LinkedIdentity(Map<String, dynamic> j)
    : id = j['id'] as String? ?? '',
      provider = j['provider'] as String? ?? '',
      email = j['email'] as String?,
      login = j['login'] as String?;

  final String id, provider;
  final String? email, login;
}

class SignInMethods {
  SignInMethods(Map<String, dynamic> j)
    : hasPassword = j['hasPassword'] == true,
      identities = [
        for (final i in (j['identities'] as List? ?? const []))
          if (i is Map<String, dynamic>) LinkedIdentity(i),
      ];

  final bool hasPassword;
  final List<LinkedIdentity> identities;

  int get count => identities.length + (hasPassword ? 1 : 0);

  List<LinkedIdentity> of(String provider) =>
      identities.where((i) => i.provider == provider).toList();
}

/// GitHub/Google sign-in (`/auth/...`). Signed-out calls go without a token;
/// the link/unlink calls use the signed-in client. All throw [SsoException].
class SsoApi {
  SsoApi._();
  static final instance = SsoApi._();

  final _plain = http.Client();

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}/auth$path');

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool signedIn = false,
  }) async {
    final request = http.Request(method, _uri(path))
      ..headers.addAll(
        signedIn
            ? apiHeaders(json: body != null)
            : {if (body != null) 'Content-Type': 'application/json'},
      );
    if (body != null) request.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await (signedIn ? apiHttp : _plain)
            .send(request)
            .timeout(SsoDurations.request),
      );
    } catch (_) {
      throw const SsoException(AuthStrings.errNetwork);
    }
    if (res.statusCode >= 400) {
      throw SsoException(
        errorMessage(res.body, res.statusCode),
        status: res.statusCode,
        code: errorCode(res.body),
      );
    }
    if (res.body.isEmpty) return const {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<SsoProviders> providers() async =>
      SsoProviders.fromJson(await _send('GET', '/providers'));

  // ---- signed out -----------------------------------------------------

  Future<DeviceStart> startGithub(String device) async => DeviceStart(
    await _send('POST', '/github/device', body: {'device': device}),
  );

  Future<SsoPoll> pollGithub(String flowId) async => SsoPoll(
    await _send(
      'POST',
      '/github/device/${Uri.encodeComponent(flowId)}/poll',
      body: const {},
    ),
  );

  // ---- signed in (Profile) --------------------------------------------

  Future<SignInMethods> methods() async =>
      SignInMethods(await _send('GET', '/identities', signedIn: true));

  Future<DeviceStart> startGithubLink() async => DeviceStart(
    await _send('POST', '/identities/github/device', signedIn: true),
  );

  Future<SsoPoll> pollGithubLink(String flowId) async => SsoPoll(
    await _send(
      'POST',
      '/identities/github/device/${Uri.encodeComponent(flowId)}/poll',
      signedIn: true,
    ),
  );

  Future<void> linkGoogle(String idToken) => _send(
    'POST',
    '/identities/google',
    body: {'idToken': idToken},
    signedIn: true,
  );

  Future<void> unlink(String id) =>
      _send('DELETE', '/identities/${Uri.encodeComponent(id)}', signedIn: true);
}
