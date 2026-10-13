import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/auth_constants.dart';
import 'api_client.dart';
import 'auth_models.dart';
import 'chat_api.dart';

/// Calls under /auth for the signed-in user. All throw [ApiException].
class AccountApi {
  const AccountApi();

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('${AppConfig.apiBaseUrl}/auth$path'),
    )..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await apiHttp.send(request).timeout(AuthDurations.request),
      );
    } catch (_) {
      throw const ApiException(AuthStrings.errNetwork);
    }
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    return response;
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  Future<AccountInfo> me() async =>
      AccountInfo.fromJson(_json(await _send('GET', '/me')));

  /// [avatar] is a data: URL; pass [clearAvatar] to remove the photo.
  Future<AuthUser> update({
    String? name,
    String? avatar,
    bool clearAvatar = false,
  }) async {
    final r = await _send(
      'PATCH',
      '/me',
      body: {
        'name': ?name,
        if (avatar != null || clearAvatar) 'avatar': avatar,
      },
    );
    return AuthUser.fromJson(_json(r)['user'] as Map<String, dynamic>);
  }

  /// Records that the first-run tour was finished or skipped.
  Future<AuthUser> setOnboarded(bool done) async {
    final r = await _send('PATCH', '/me', body: {'onboarded': done});
    return AuthUser.fromJson(_json(r)['user'] as Map<String, dynamic>);
  }

  /// [current] is null when the account has no password yet (GitHub/Google).
  Future<void> changePassword(String? current, String next) =>
      _send('POST', '/password', body: {'current': ?current, 'next': next});

  Future<List<DeviceSession>> sessions() async {
    final list = _json(await _send('GET', '/sessions'))['sessions'] as List;
    return [
      for (final s in list)
        if (s is Map<String, dynamic>) DeviceSession.fromJson(s),
    ];
  }

  Future<void> revokeSession(String id) => _send('DELETE', '/sessions/$id');

  /// [password] is null for accounts without one (GitHub/Google).
  Future<void> deleteAccount(String? password) =>
      _send('DELETE', '/me', body: {'password': ?password});
}
