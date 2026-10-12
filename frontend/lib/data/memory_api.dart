import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/memory.dart';
import 'api_client.dart';
import 'chat_api.dart';

/// One thing the assistant remembers about the user.
class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.text,
    this.kind = 'fact',
    this.pinned = false,
  });

  final String id;
  final String text;

  /// fact, preference, project or instruction.
  final String kind;
  final bool pinned;

  factory MemoryItem.fromJson(Map<String, dynamic> j) => MemoryItem(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    kind: j['kind'] as String? ?? 'fact',
    pinned: j['pinned'] == true,
  );
}

class MemoryPage {
  const MemoryPage({
    required this.enabled,
    required this.total,
    required this.items,
    this.chatRecall = true,
  });
  final bool enabled;

  /// Whether past chats are indexed and searched ("have we talked about this?").
  final bool chatRecall;
  final int total;
  final List<MemoryItem> items;
}

/// Calls under /memory. All throw [ApiException].
class MemoryApi {
  MemoryApi._();
  static final instance = MemoryApi._();

  final _client = AuthClient();

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('${AppConfig.apiBaseUrl}/memory$path'),
    )..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(MemoryConfig.requestTimeout),
    );
    if (response.statusCode >= 400) {
      throw ApiException(
        errorMessage(response.body, response.statusCode),
        status: response.statusCode,
      );
    }
    return response;
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  Future<MemoryPage> list({String query = ''}) async {
    final q = query.trim();
    final j = _json(
      await _send('GET', q.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q)}'),
    );
    return MemoryPage(
      enabled: j['enabled'] != false,
      chatRecall: j['chatRecall'] != false,
      total: (j['total'] as num?)?.toInt() ?? 0,
      items: [
        for (final i in j['items'] as List? ?? const [])
          if (i is Map<String, dynamic>) MemoryItem.fromJson(i),
      ],
    );
  }

  Future<bool> setEnabled(bool enabled) async {
    final j = _json(
      await _send('PUT', '/settings', body: {'enabled': enabled}),
    );
    return j['enabled'] != false;
  }

  Future<bool> setChatRecall(bool enabled) async {
    final j = _json(
      await _send('PUT', '/settings', body: {'chatRecall': enabled}),
    );
    return j['chatRecall'] != false;
  }

  Future<MemoryItem> create(String text) async =>
      MemoryItem.fromJson(_json(await _send('POST', '', body: {'text': text})));

  Future<MemoryItem> update(String id, {String? text, bool? pinned}) async =>
      MemoryItem.fromJson(
        _json(
          await _send(
            'PATCH',
            '/$id',
            body: {'text': ?text, 'pinned': ?pinned},
          ),
        ),
      );

  Future<void> delete(String id) async {
    await _send('DELETE', '/$id');
  }

  Future<void> clear() async {
    await _send('DELETE', '');
  }
}
