import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../features/chat/widgets/rich/rich_parsers.dart';
import 'chat_api.dart';

/// Client for POST /assist/email (AI rewrite of an email draft).
class AssistApi {
  static const _timeout = Duration(seconds: 40);

  /// [action] is shorter, longer, formal, friendly, fix or custom.
  static Future<EmailDraft> rewriteEmail({
    required EmailDraft draft,
    required String action,
    String? instruction,
    Map<String, String> profile = const {},
  }) async {
    final http.Response response;
    try {
      response = await http
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
