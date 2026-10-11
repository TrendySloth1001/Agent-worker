import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../features/chat/widgets/rich/rich_parsers.dart';
import 'chat_api.dart';
import 'api_client.dart';

/// Client for POST /assist/email (AI rewrite of an email draft).
class AssistApi {
  static const _timeout = Duration(seconds: 40);

  /// Tidies a personalization field ([field] is about or instructions).
  static Future<String> formatProfile({
    required String field,
    required String text,
    required int max,
  }) async {
    final http.Response response;
    try {
      response = await apiHttp
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/assist/profile'),
            headers: apiHeaders(json: true),
            body: jsonEncode({'field': field, 'text': text, 'max': max}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('Formatting timed out.');
    } on http.ClientException catch (e) {
      throw ApiException(e.message);
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        errorMessage(response.body, response.statusCode),
        status: response.statusCode,
      );
    }
    final j = jsonDecode(response.body);
    return j is Map && j['text'] is String ? j['text'] as String : '';
  }

  /// [action] is shorter, longer, formal, friendly, fix or custom.
  static Future<EmailDraft> rewriteEmail({
    required EmailDraft draft,
    required String action,
    String? instruction,
    Map<String, String> profile = const {},
  }) async {
    final http.Response response;
    try {
      response = await apiHttp
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/assist/email'),
            headers: apiHeaders(json: true),
            body: jsonEncode({
              'draft': {
                'to': draft.to,
                'cc': draft.cc,
                'bcc': draft.bcc,
                'subject': draft.subject,
                'body': draft.body,
              },
              'action': action,
              'instruction': ?instruction,
              'profile': profile,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('The rewrite timed out.');
    } on http.ClientException catch (e) {
      throw ApiException(e.message);
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        errorMessage(response.body, response.statusCode),
        status: response.statusCode,
      );
    }
    final d = (jsonDecode(response.body) as Map<String, dynamic>)['draft'];
    String s(String k) => (d is Map && d[k] is String) ? d[k] as String : '';
    return EmailDraft(
      to: s('to'),
      cc: s('cc'),
      bcc: s('bcc'),
      subject: s('subject'),
      body: s('body'),
    );
  }
}
