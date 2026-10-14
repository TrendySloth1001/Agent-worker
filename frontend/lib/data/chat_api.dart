import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/app_sizes.dart';
import '../core/constants/error_copy.dart';
import '../core/constants/smart_toggles.dart';
import '../core/constants/update.dart';
import '../core/update/app_build.dart';
import '../features/auth/auth_controller.dart';
import 'api_client.dart';
import 'ai_model.dart';
import 'chat_event.dart';
import 'chat_message.dart';

/// Carries a user-readable message from the server or the network layer,
/// plus the backend's machine [code] when it sent one.
class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.code});

  /// A failed response, with a friendly [message] (see [friendlyError]).
  factory ApiException.fromResponse(String body, int status) => ApiException(
    errorMessage(body, status),
    status: status,
    code: errorCode(body),
  );

  final String message;
  final int? status;
  final String? code;

  @override
  String toString() => message;
}

/// Headers for backend calls, with the signed-in user's access token.
/// Send through [AuthClient] (or `apiHttp`), which also refreshes on a 401.
/// The dart-define API_TOKEN is no longer sent: only for owner sign-up.
Map<String, String> apiHeaders({bool json = false}) {
  final token = AuthController.instance.accessToken;
  return {
    if (json) 'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
    if (AppBuild.current != null)
      UpdateConfig.buildHeader: '${AppBuild.current}',
  };
}

/// Code of a `{"error":{"code":...}}` body, e.g. `daily_limit`.
String? errorCode(String body) {
  try {
    final e = (jsonDecode(body) as Map<String, dynamic>)['error'];
    if (e is Map<String, dynamic> && e['code'] is String) {
      return e['code'] as String;
    }
  } catch (_) {}
  return null;
}

/// A daily-limit message with the reset time in local time.
String dailyLimitMessage(String serverMessage) {
  final now = DateTime.now().toUtc();
  final reset = DateTime.utc(now.year, now.month, now.day + 1).toLocal();
  final hh = reset.hour.toString().padLeft(2, '0');
  final mm = reset.minute.toString().padLeft(2, '0');
  final base = serverMessage.replaceAll(
    RegExp(r'\s*Your limit resets at .*$'),
    '',
  );
  return 'Daily limit reached. $base Resets at $hh:$mm.';
}

/// The raw `{"error":{"message":...}}` of a failed response, or null.
/// For logs and owner-only telemetry; users see [errorMessage].
String? rawErrorMessage(String body) {
  try {
    final e = (jsonDecode(body) as Map<String, dynamic>)['error'];
    if (e is Map<String, dynamic> && e['message'] is String) {
      return e['message'] as String;
    }
  } catch (_) {}
  return null;
}

/// A friendly, user-facing line for a failed response (never a status code
/// or raw server text that looks technical).
String errorMessage(String body, int status) => friendlyError(
  code: errorCode(body),
  message: rawErrorMessage(body),
  status: status,
);

class ChatApi {
  final _client = AuthClient();

  Future<List<AiModel>> fetchModels() async {
    final response = await _client.get(
      Uri.parse('${AppConfig.apiBaseUrl}/models'),
      headers: apiHeaders(),
    );
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
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
    WebMode webMode = WebMode.auto,
    required bool knowledge,
    required String mode,
    Map<String, String> profile = const {},
    String? context,
    bool roundTable = false,
    String? conversationId,
    bool smartSuggestions = true,
    Set<SuggestKind> suppressSuggest = const {},
    List<Map<String, String>> apps = const [],
    Map<String, Object>? screen,
    Map<String, Object>? deviceActions,
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
            'webSearch': webMode != WebMode.off,
            'webMode': webMode.wire,
            'knowledge': knowledge,
            'mode': mode,
            if (profile.isNotEmpty) 'profile': profile,
            'context': ?context,
            if (roundTable) 'roundTable': true,
            'conversationId': ?conversationId,
            if (!smartSuggestions) 'smartSuggestions': false,
            if (suppressSuggest.isNotEmpty)
              'suppressSuggest': [for (final k in suppressSuggest) k.name],
            if (apps.isNotEmpty) 'apps': apps,
            // Assistant overlay: the screen the user chose to share.
            'screen': ?screen,
            // Android: the phone can run confirmed actions (alarm, event...).
            'deviceActions': ?deviceActions,
            // With actions: the recent answers' source links, so "open it
            // on YouTube Music" opens the link the answer found.
            if (deviceActions != null)
              if (recentSourceLinks(history) case final links
                  when links.isNotEmpty)
                'sources': links,
          });

    // [client] stays the caller's (closing it stops the stream); the
    // wrapper adds the access token and retries once after a refresh.
    final response = await AuthClient(
      client,
    ).send(request).timeout(AppDurations.streamIdle);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiException.fromResponse(body, response.statusCode);
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

  /// Tells the server what the user did with a suggestion (telemetry only;
  /// failures are ignored).
  Future<void> reportSuggestion(
    SuggestKind kind,
    String outcome, {
    String? conversationId,
  }) async {
    final client = AuthClient();
    try {
      final response = await client
          .send(
            http.Request(
                'POST',
                Uri.parse('${AppConfig.apiBaseUrl}/chat/suggestion'),
              )
              ..headers.addAll(apiHeaders(json: true))
              ..body = jsonEncode({
                'kind': kind.name,
                'outcome': outcome,
                'conversationId': ?conversationId,
              }),
          )
          .timeout(AppDurations.streamIdle);
      await response.stream.drain<void>();
    } catch (_) {
    } finally {
      client.close();
    }
  }
}

/// Answers whose sources go with a request (the newest first).
const recentSourceAnswers = 2;

/// Most source links sent with a request (the server caps it at 40).
const maxSourceLinks = 30;

/// The web links the last [recentSourceAnswers] answers cited, newest first:
/// `{url, title}` for the `sources` field of POST /chat.
List<Map<String, String>> recentSourceLinks(List<ChatMessage> history) {
  final out = <Map<String, String>>[];
  final seen = <String>{};
  final answers = history.reversed
      .where((m) => m.role == Role.assistant && m.citations.isNotEmpty)
      .take(recentSourceAnswers);
  for (final m in answers) {
    for (final c in m.citations) {
      final uri = Uri.tryParse(c.url);
      if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
        continue;
      }
      if (!seen.add(c.url)) continue;
      out.add({'url': c.url, if (c.title.isNotEmpty) 'title': c.title});
      if (out.length >= maxSourceLinks) return out;
    }
  }
  return out;
}
