import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/app_sizes.dart';
import 'ai_model.dart';
import 'chat_event.dart';
import 'chat_message.dart';

/// Carries a user-readable message from the server or the network layer.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

Map<String, String> apiHeaders({bool json = false}) => {
  if (json) 'Content-Type': 'application/json',
  if (AppConfig.apiToken.isNotEmpty)
    'Authorization': 'Bearer ${AppConfig.apiToken}',
};

/// Reads `{"error":{"message":...}}` from a failed response.
String errorMessage(String body, int status) {
  try {
    final e = (jsonDecode(body) as Map<String, dynamic>)['error'];
    if (e is Map<String, dynamic> && e['message'] is String) {
      return e['message'] as String;
    }
  } catch (_) {}
  return 'HTTP $status';
}

class ChatApi {
  final _client = http.Client();

  Future<List<AiModel>> fetchModels() async {
    final response = await _client.get(
      Uri.parse('${AppConfig.apiBaseUrl}/models'),
      headers: apiHeaders(),
    );
    if (response.statusCode >= 400) {
      throw ApiException(errorMessage(response.body, response.statusCode));
    }
    final list = jsonDecode(response.body)['models'] as List;
    return [
      for (final m in list)
        if (m is Map<String, dynamic> && m['provider'] != 'auto')
          AiModel.fromJson(m),
    ];
  }

  /// Streams a reply. [client] belongs to the caller; closing it stops the
  /// stream. Throws [ApiException] for non-200 answers.
  Stream<ChatEvent> streamChat(
    http.Client client,
    List<ChatMessage> history, {
    String? modelId,
    required bool webSearch,
    required bool knowledge,
    required String mode,
    Map<String, String> profile = const {},
    String? context,
    bool roundTable = false,
  }) async* {
    final request =
        http.Request('POST', Uri.parse('${AppConfig.apiBaseUrl}/chat'))
          ..headers.addAll({
            ...apiHeaders(json: true),
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode({
            'messages': history.map((m) => m.toJson()).toList(),
            'model': ?modelId,
            'webSearch': webSearch,
            'knowledge': knowledge,
            'mode': mode,
            if (profile.isNotEmpty) 'profile': profile,
            'context': ?context,
            if (roundTable) 'roundTable': true,
          });

    final response = await client
        .send(request)
        .timeout(AppDurations.streamIdle);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiException(errorMessage(body, response.statusCode));
    }

    final lines = response.stream
        .timeout(
          AppDurations.streamIdle,
          onTimeout: (sink) => sink.addError(TimeoutException('idle')),
        )
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    var event = 'message';
    final data = StringBuffer();
    await for (final line in lines) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          final parsed = ChatEvent.parse(event, data.toString());
          if (parsed != null) yield parsed;
        }
        event = 'message';
        data.clear();
      } else if (line.startsWith(':')) {
        continue;
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        if (data.isNotEmpty) data.write('\n');
        data.write(line.substring(5).trimLeft());
      }
    }
  }
}
