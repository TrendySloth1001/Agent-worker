import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../data/api_client.dart';
import '../../data/chat_api.dart';
import '../constants/app_config.dart';
import '../constants/update.dart';
import 'update_models.dart';

/// Calls under `/app`. All throw [ApiException].
class UpdateApi {
  UpdateApi({AuthClient? client, String? baseUrl})
    : _client = client ?? AuthClient(),
      _base = '${baseUrl ?? AppConfig.apiBaseUrl}/app';

  final AuthClient _client;
  final String _base;

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_base$path'))
      ..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(UpdateConfig.requestTimeout),
    );
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    return response;
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  /// Is there a newer build than [build]?
  Future<UpdateInfo> check(int build, {String? deviceId}) async {
    final device = deviceId == null ? '' : '&device=$deviceId';
    return UpdateInfo.fromJson(
      _json(await _send('GET', '/update?build=$build$device')),
    );
  }

  /// Sends queued install-outcome events (`POST /app/health/events`).
  Future<void> sendEvents(
    String deviceId,
    List<Map<String, dynamic>> events,
  ) async {
    await _send(
      'POST',
      '/health/events',
      body: {'deviceId': deviceId, 'events': events},
    );
  }

  // ---- owner -----------------------------------------------------------

  Future<ReleaseList> releases() async =>
      ReleaseList.fromJson(_json(await _send('GET', '/releases')));

  Future<OwnerRelease> edit(String id, ReleaseEdit edit) async {
    final j = _json(await _send('PATCH', '/releases/$id', body: edit.toJson()));
    return OwnerRelease.fromJson(j['release'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _send('DELETE', '/releases/$id');
  }

  /// Uploads an APK with its details. [onProgress] gets 0..1 of the bytes sent.
  Future<OwnerRelease> upload({
    required String path,
    required String version,
    required int build,
    required UpdateKind kind,
    required String title,
    required List<String> notes,
    int? minSupportedBuild,
    bool live = false,
    void Function(double progress)? onProgress,
  }) async {
    final multipart = http.MultipartRequest('POST', Uri.parse('$_base/releases'))
      ..headers.addAll(apiHeaders())
      ..fields.addAll({
        'version': version,
        'build': '$build',
        'kind': kind.name,
        'title': title,
        'notes': jsonEncode(notes),
        'minSupportedBuild': ?minSupportedBuild?.toString(),
        'status': live ? 'live' : 'draft',
      })
      ..files.add(
        await http.MultipartFile.fromPath(
          'apk',
          path,
          filename: 'sparky-$version.apk',
          contentType: MediaType.parse(UpdateConfig.apkMime),
        ),
      );
    final total = multipart.contentLength;
    final stream = multipart.finalize();
    // Re-wrapped as a streamed request so the bytes can be counted.
    final request = http.StreamedRequest('POST', multipart.url)
      ..headers.addAll(multipart.headers)
      ..contentLength = total;
    final sending = _client.send(request);
    var sent = 0;
    await for (final chunk in stream) {
      request.sink.add(chunk);
      sent += chunk.length;
      if (total > 0) onProgress?.call(sent / total);
    }
    await request.sink.close();
    final response = await http.Response.fromStream(await sending);
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    return OwnerRelease.fromJson(_json(response)['release'] as Map<String, dynamic>);
  }
}
