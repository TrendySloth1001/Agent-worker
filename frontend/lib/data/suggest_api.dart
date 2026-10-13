import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/suggest.dart';
import 'api_client.dart';
import 'chat_api.dart';

/// What `POST /assist/complete` returns.
class Completion {
  const Completion({this.completion = '', this.nextWords = const []});
  final String completion;
  final List<String> nextWords;

  bool get isEmpty => completion.isEmpty && nextWords.isEmpty;
}

/// Composer autocomplete and personalised starter prompts.
class SuggestApi {
  SuggestApi({http.Client Function()? makeClient})
    : _makeClient = makeClient ?? http.Client.new;

  final http.Client Function() _makeClient;

  /// Asks for a completion. Close [cancel] (see [CompleteCall]) to abort.
  CompleteCall complete(String text, {String? conversationId}) {
    final client = _makeClient();
    final future = _complete(
      client,
      text,
      conversationId,
    ).whenComplete(client.close);
    return CompleteCall(future, client.close);
  }

  Future<Completion> _complete(
    http.Client client,
    String text,
    String? conversationId,
  ) async {
    final response = await AuthClient(client)
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/assist/complete'),
          headers: apiHeaders(json: true),
          body: jsonEncode({'text': text, 'conversationId': ?conversationId}),
        )
        .timeout(SuggestConfig.requestTimeout);
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) return const Completion();
    return Completion(
      completion: json['completion'] as String? ?? '',
      nextWords: [
        for (final w in json['nextWords'] as List? ?? const [])
          if (w is String && w.isNotEmpty) w,
      ],
    );
  }

  /// Starter prompts from recent chats; empty when there is nothing to base
  /// them on or the request fails (callers keep the built-in ones).
  Future<List<String>> starters() async {
    try {
      final response = await apiHttp
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/assist/starters'),
            headers: apiHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) return const [];
      final json = jsonDecode(response.body);
      return [
        for (final p in (json is Map ? json['prompts'] : null) as List? ?? [])
          if (p is String && p.trim().isNotEmpty) p.trim(),
      ];
    } on Object {
      return const [];
    }
  }
}

/// A running completion request that can be cancelled.
class CompleteCall {
  const CompleteCall(this.result, this.cancel);
  final Future<Completion> result;
  final void Function() cancel;
}
