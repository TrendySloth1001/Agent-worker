import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_sizes.dart';
import '../core/constants/app_strings.dart';
import 'chat_api.dart';
import 'kb_source.dart';
import 'api_client.dart';

/// Calls under /knowledge. All throw [ApiException] on failure.
class KnowledgeApi {
  KnowledgeApi(this.baseUrl);

  final String baseUrl;

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await apiHttp.send(request).timeout(AppDurations.kbRequestTimeout),
      );
    } catch (_) {
      throw const ApiException(AppStrings.errorNetwork);
    }
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    return response;
  }

  KbSource _source(http.Response r) => KbSource.fromJson(
    (jsonDecode(r.body) as Map<String, dynamic>)['source']
        as Map<String, dynamic>,
  );

  Future<List<KbSource>> list() async {
    final r = await _send('GET', '/knowledge/sources');
    final items = (jsonDecode(r.body) as Map<String, dynamic>)['sources'];
    return [
      for (final s in items as List)
        KbSource.fromJson(s as Map<String, dynamic>),
    ];
  }

  Future<KbSource> add(
    String input, {
    String type = 'auto',
    int? limit,
  }) async => _source(
    await _send(
      'POST',
      '/knowledge/sources',
      body: {'input': input, 'type': type, 'limit': ?limit},
    ),
  );

  /// Saves a chat reply as a note source. A 409 means it already exists.
  Future<KbSource> addNote({
    required String content,
    String? question,
    String? conversationId,
  }) async => _source(
    await _send(
      'POST',
      '/knowledge/notes',
      body: {
        'content': content,
        if (question != null && question.trim().isNotEmpty)
          'question': question.trim(),
        'conversationId': ?conversationId,
      },
    ),
  );

  Future<KbSource> refresh(String id) async =>
      _source(await _send('POST', '/knowledge/sources/$id/refresh'));

  Future<void> delete(String id) async {
    await _send('DELETE', '/knowledge/sources/$id');
  }
}
