import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/api_client.dart';
import '../../data/chat_api.dart';
import '../constants/app_config.dart';
import '../constants/errors.dart';
import 'errors_models.dart';

/// Calls for crash reporting. Everything throws [ApiException] on a failed response.
class ErrorsApi {
  ErrorsApi({AuthClient? client, String? baseUrl})
    : _client = client ?? AuthClient(),
      _base = baseUrl ?? AppConfig.apiBaseUrl;

  final AuthClient _client;
  final String _base;

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_base$path'))
      ..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(ErrorsConfig.requestTimeout),
    );
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    return response;
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  // ---- every signed-in user ------------------------------------------------

  Future<void> sendErrors(List<Map<String, dynamic>> errors) async {
    await _send('POST', '/app/errors', body: {'errors': errors});
  }

  Future<void> sendSessions(List<Map<String, dynamic>> sessions) async {
    await _send('POST', '/app/sessions', body: {'sessions': sessions});
  }

  // ---- owner ---------------------------------------------------------------

  Future<ErrorGroupList> groups({int? build, String status = 'open'}) async {
    final q = {
      'status': status,
      'limit': '${ErrorsSizes.listLimit}',
      'build': ?build?.toString(),
    };
    final path = Uri(path: '/admin/errors', queryParameters: q).toString();
    return ErrorGroupList.fromJson(_json(await _send('GET', path)));
  }

  Future<ErrorGroupDetail> detail(String fingerprint) async =>
      ErrorGroupDetail.fromJson(
        _json(await _send('GET', '/admin/errors/$fingerprint')),
      );

  Future<void> setStatus(String fingerprint, ErrorStatus status) async {
    await _send(
      'PATCH',
      '/admin/errors/$fingerprint',
      body: {'status': status.name},
    );
  }

  Future<String?> userEmail(String eventId) async =>
      _json(await _send('GET', '/admin/errors/events/$eventId/user'))['email']
          as String?;

  Future<List<BuildHealth>> buildHealth({int days = 7}) async {
    final j = _json(await _send('GET', '/admin/health/builds?days=$days'));
    return [
      for (final b in (j['builds'] as List? ?? const []))
        BuildHealth.fromJson(b as Map<String, dynamic>),
    ];
  }
}
