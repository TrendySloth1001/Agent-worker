import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/voice_fix.dart';
import 'api_client.dart';
import 'chat_api.dart';

/// One earlier chat message given to the fix as context.
typedef VoiceTurn = ({String role, String content});

/// What `POST /assist/fix-transcript` returns.
class ServerFix {
  const ServerFix(this.text, this.source, {this.ms = 0});
  final String text;

  /// llm, cache, skipped, timeout, rejected or error. Only llm and cache
  /// carry a corrected text.
  final String source;
  final int ms;

  bool get applied => source == 'llm' || source == 'cache';
}

/// The fast model pass over a dictated segment, and the user's vocabulary.
class TranscriptFixApi {
  TranscriptFixApi({http.Client Function()? makeClient})
    : _makeClient = makeClient ?? http.Client.new;

  final http.Client Function() _makeClient;

  /// Null when the request failed or ran past [timeout] (it is then
  /// cancelled); the caller keeps its local text.
  Future<ServerFix?> fix({
    required String text,
    List<VoiceTurn> context = const [],
    String? language,
    bool exact = false,
    List<String> vocab = const [],
    bool confident = false,
    List<double> localMs = const [],
    Duration timeout = VoiceFixConfig.llmTimeout,
  }) async {
    final client = _makeClient();
    final budget = timeout - VoiceFixConfig.networkMargin;
    try {
      final response = await AuthClient(client)
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/assist/fix-transcript'),
            headers: apiHeaders(json: true),
            body: jsonEncode({
              'text': text,
              'context': [
                for (final t in context) {'role': t.role, 'content': t.content},
              ],
              'language': ?language,
              'exact': exact,
              if (vocab.isNotEmpty) 'vocab': vocab,
              'confident': confident,
              if (localMs.isNotEmpty) 'localMs': localMs,
              if (budget.inMilliseconds >= 200)
                'budgetMs': budget.inMilliseconds,
            }),
          )
          .timeout(timeout);
      if (response.statusCode >= 400) return null;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      final fixed = (json['text'] as String? ?? '').trim();
      if (fixed.isEmpty) return null;
      return ServerFix(
        fixed,
        json['source'] as String? ?? 'error',
        ms: (json['ms'] as num?)?.toInt() ?? 0,
      );
    } on Object {
      return null;
    } finally {
      client.close();
    }
  }

  /// Names and repository names to spell right; empty on any failure.
  Future<List<String>> vocab() async {
    final client = _makeClient();
    try {
      final response = await AuthClient(client)
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/assist/voice-vocab'),
            headers: apiHeaders(),
          )
          .timeout(VoiceFixConfig.vocabTimeout);
      if (response.statusCode >= 400) return const [];
      final json = jsonDecode(response.body);
      return [
        for (final w in (json is Map ? json['words'] : null) as List? ?? [])
          if (w is String && w.trim().isNotEmpty) w.trim(),
      ].take(VoiceFixConfig.maxVocab).toList();
    } on Object {
      return const [];
    } finally {
      client.close();
    }
  }
}
