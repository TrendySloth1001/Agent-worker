import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/api_client.dart';
import '../../data/chat_api.dart';
import '../constants/app_config.dart';
import '../constants/vault.dart';

/// What `GET /admin/vault` says. Never carries the key.
class VaultStatus {
  const VaultStatus({
    required this.exists,
    this.updatedAt,
    this.needsReseal = false,
  });

  factory VaultStatus.fromJson(Map<String, dynamic> j) => VaultStatus(
    exists: j['exists'] == true,
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal(),
    needsReseal: j['needsReseal'] == true,
  );

  final bool exists;
  final DateTime? updatedAt;
  final bool needsReseal;

  VaultState get state => !exists
      ? VaultState.notSetUp
      : needsReseal
      ? VaultState.needsReseal
      : VaultState.sealed;
}

/// Owner-only calls. The password only ever goes in a POST body.
class VaultApi {
  VaultApi({AuthClient? client, String? baseUrl})
    : _client = client ?? AuthClient(),
      _base = baseUrl ?? AppConfig.apiBaseUrl;

  final AuthClient _client;
  final String _base;

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_base/admin/vault$path'))
      ..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(VaultConfig.requestTimeout),
    );
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<VaultStatus> status() async =>
      VaultStatus.fromJson(await _send('GET', ''));

  Future<VaultStatus> seed(String password) async => VaultStatus.fromJson(
    await _send('POST', '/seed', body: {'password': password}),
  );

  /// The key itself. Keep it in memory only as long as it is shown.
  Future<String> reveal(String password) async =>
      (await _send('POST', '/reveal', body: {'password': password}))['secret']
          as String;
}
