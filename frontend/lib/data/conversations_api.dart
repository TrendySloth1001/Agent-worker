import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/constants/app_sizes.dart';
import '../core/constants/app_strings.dart';
import 'chat_api.dart';
import 'chat_message.dart';
import 'conversation.dart';
import 'api_client.dart';

/// Calls under /conversations. All throw [ApiException] on failure.
class ConversationsApi {
  ConversationsApi(this.baseUrl);

  final String baseUrl;

  /// Random v4 UUID; the app names new chats so saves are idempotent.
  static String newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = AppDurations.conversationTimeout,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await apiHttp.send(request).timeout(timeout),
      );
    } catch (_) {
      throw const ApiException(AppStrings.errorNetwork);
    }
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

  /// Pinned first. [archived] lists only archived chats instead.
  Future<List<ConversationSummary>> list({
    String query = '',
    bool archived = false,
  }) async {
    final q = query.trim();
    final params = {if (q.isNotEmpty) 'q': q, if (archived) 'archived': '1'};
    final path = Uri(
      path: '/conversations',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
    final items = _json(await _send('GET', path))['conversations'] as List;
    return [
      for (final c in items)
        ConversationSummary.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<(ConversationSummary, List<ChatMessage>)> get(String id) async =>
      _full(_json(await _send('GET', '/conversations/$id')));

  /// A new chat holding the first [at] saved messages of [id].
  Future<(ConversationSummary, List<ChatMessage>)> fork(
    String id,
    int at,
  ) async => _full(
    _json(await _send('POST', '/conversations/$id/fork', body: {'at': at})),
  );

  /// A new chat that starts from a briefing of [a] and [b].
  Future<(ConversationSummary, List<ChatMessage>)> merge(
    String a,
    String b,
  ) async => _full(
    _json(
      await _send(
        'POST',
        '/conversations/merge',
        body: {
          'ids': [a, b],
        },
        timeout: AppDurations.mergeTimeout,
      ),
    ),
  );

  (ConversationSummary, List<ChatMessage>) _full(Map<String, dynamic> j) {
    return (
      ConversationSummary.fromJson(j),
      [
        for (final m in j['messages'] as List)
          ChatMessage.fromStorageJson(m as Map<String, dynamic>),
      ],
    );
  }

  /// Replaces the saved chat. The reply carries the title once it is named.
  Future<ConversationSummary> save(
    String id,
    List<ChatMessage> messages,
  ) async {
    final r = await _send(
      'PUT',
      '/conversations/$id',
      body: {
        'messages': [for (final m in messages) m.toStorageJson()],
      },
    );
    return ConversationSummary.fromJson(_json(r));
  }

  Future<ConversationSummary> rename(String id, String title) async =>
      ConversationSummary.fromJson(
        _json(
          await _send('PATCH', '/conversations/$id', body: {'title': title}),
        ),
      );

  Future<ConversationSummary> setPinned(String id, bool pinned) async =>
      ConversationSummary.fromJson(
        _json(
          await _send('PATCH', '/conversations/$id', body: {'pinned': pinned}),
        ),
      );

  /// Archiving also unpins.
  Future<ConversationSummary> setArchived(String id, bool archived) async =>
      ConversationSummary.fromJson(
        _json(
          await _send(
            'PATCH',
            '/conversations/$id',
            body: {'archived': archived},
          ),
        ),
      );

  Future<void> delete(String id) async {
    await _send('DELETE', '/conversations/$id');
  }
}
