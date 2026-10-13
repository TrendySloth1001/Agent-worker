import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app/core/constants/error_copy.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/chat_event.dart';

/// Words that mark a line as written for developers, not users.
final _banned = RegExp(
  r'\b(429|5\d\d|Exception|stack|undefined|null|provider|quota|ollama|groq|'
  r'openrouter|nvidia)\b',
  caseSensitive: false,
);

void main() {
  group('ErrorCopy constants', () {
    test('none read like developer text', () {
      for (final line in ErrorCopy.all) {
        expect(_banned.hasMatch(line), isFalse, reason: line);
        expect(isUserSafe(line), isTrue, reason: line);
      }
    });

    test('every mapped code and notice uses a listed constant', () {
      for (final line in ErrorCopy.codes.values) {
        expect(ErrorCopy.all, contains(line));
      }
      for (final line in ErrorCopy.notices.values.whereType<String>()) {
        expect(ErrorCopy.all, contains(line));
      }
    });
  });

  group('friendlyError', () {
    const raw = [
      'Ollama quota exhausted until 2026-11-01T00:00:00Z',
      'HTTP 502',
      'GitHub: Validation Failed',
      'Expected multipart/form-data with a `file` field',
      'GitHub is not configured (GITHUB_TOKEN)',
      'groq:openai/gpt-oss-20b failed, trying nvidia:x',
      'TypeError: Cannot read properties of undefined',
      'connect ECONNREFUSED 127.0.0.1:5432',
    ];

    test('hides raw server text whatever the code', () {
      for (final code in [null, 'internal', 'bad_request', 'upstream_failed']) {
        for (final status in [null, 400, 422, 502]) {
          for (final m in raw) {
            final out = friendlyError(code: code, message: m, status: status);
            expect(out, isNot(m), reason: '$code $status $m');
            expect(_banned.hasMatch(out), isFalse, reason: out);
            expect(isUserSafe(out), isTrue, reason: out);
          }
        }
      }
    });

    test('never shows a status code', () {
      for (final s in [400, 401, 403, 404, 413, 429, 500, 502, 503]) {
        final out = friendlyError(status: s);
        expect(out.contains('$s'), isFalse, reason: out);
        expect(out.contains('HTTP'), isFalse, reason: out);
      }
    });

    test('maps known codes to their copy', () {
      expect(friendlyError(code: 'rate_limited'), ErrorCopy.rateLimited);
      expect(friendlyError(code: 'fair_use'), ErrorCopy.rateLimited);
      expect(friendlyError(code: 'busy'), ErrorCopy.busy);
      expect(friendlyError(code: 'all_models_failed'), ErrorCopy.busy);
      expect(
        friendlyError(code: 'unauthorized', message: 'Session expired'),
        ErrorCopy.sessionExpired,
      );
      expect(
        friendlyError(code: 'upstream_failed', message: 'Try again'),
        ErrorCopy.busy,
      );
    });

    test('keeps a safe, specific server message', () {
      expect(
        friendlyError(code: 'not_found', message: 'Conversation not found'),
        'Conversation not found',
      );
      expect(
        friendlyError(
          code: 'limit_reached',
          message: 'Memory is full. Delete some first.',
        ),
        'Memory is full. Delete some first.',
      );
      expect(
        friendlyError(message: 'Wrong email or password.', status: 401),
        'Wrong email or password.',
      );
      // A server failure never echoes its text.
      expect(
        friendlyError(message: 'Please wait', status: 503),
        ErrorCopy.busy,
      );
    });

    test('daily limit keeps the reset time', () {
      final out = friendlyError(
        code: 'daily_limit',
        message:
            "You've used all 50 messages for today. Your limit resets at "
            '00:00 UTC.',
        status: 429,
      );
      expect(out, startsWith('Daily limit reached.'));
      expect(out, contains('Resets at'));
    });

    test('errorMessage never falls back to HTTP status', () {
      expect(errorMessage('<html>Bad Gateway</html>', 502), ErrorCopy.busy);
      expect(errorMessage('', 400), ErrorCopy.generic);
      expect(
        errorMessage(
          '{"error":{"code":"github_invalid","message":"GitHub: Validation '
          'Failed"}}',
          422,
        ),
        ErrorCopy.githubInvalid,
      );
    });

    test('ApiException.fromResponse carries code and friendly text', () {
      final e = ApiException.fromResponse(
        '{"error":{"code":"rate_limited","message":"429 Too Many Requests"}}',
        429,
      );
      expect(e.code, 'rate_limited');
      expect(e.status, 429);
      expect(e.message, ErrorCopy.rateLimited);
    });
  });

  group('friendlyException', () {
    test('network failures', () {
      expect(
        friendlyException(const SocketException('Connection refused')),
        ErrorCopy.offline,
      );
      expect(
        friendlyException(http.ClientException('Connection closed')),
        ErrorCopy.offline,
      );
      expect(friendlyException(TimeoutException('idle')), ErrorCopy.timeout);
    });

    test('anything else is generic', () {
      expect(
        friendlyException(const FormatException('Unexpected character')),
        ErrorCopy.generic,
      );
      expect(friendlyException(Exception('boom')), ErrorCopy.generic);
      expect(friendlyException(StateError('bad state')), ErrorCopy.generic);
    });

    test('an ApiException with raw text is cleaned', () {
      expect(
        friendlyException(const ApiException('HTTP 502', status: 502)),
        ErrorCopy.busy,
      );
      expect(
        friendlyException(const ApiException('Could not load.')),
        'Could not load.',
      );
    });
  });

  group('chat notices', () {
    NoticeEvent notice(String code, String message) =>
        ChatEvent.parse('notice', '{"code":"$code","message":"$message"}')
            as NoticeEvent;

    test('model switches are silent', () {
      expect(
        notice(
          'fallback',
          'groq:openai/gpt-oss-20b failed, trying nvidia:x.',
        ).text,
        isNull,
      );
      expect(
        notice('vision_model', 'Using a vision model instead.').text,
        isNull,
      );
    });

    test('known codes use friendly copy', () {
      expect(
        notice('vision_unavailable', 'raw').text,
        ErrorCopy.noticeVisionUnavailable,
      );
      expect(
        notice('attachment_failed', 'Could not read: a.pdf').text,
        ErrorCopy.noticeAttachmentFailed,
      );
      expect(
        notice('kb_unavailable', 'raw').text,
        ErrorCopy.noticeKbUnavailable,
      );
    });

    test('unknown codes show only safe text', () {
      expect(
        notice('new_thing', 'Answering briefly.').text,
        'Answering briefly.',
      );
      expect(notice('new_thing', 'ollama quota hit').text, isNull);
    });

    test('error events keep their code', () {
      final e =
          ChatEvent.parse(
                'error',
                '{"error":{"code":"busy","message":"x","retryable":true}}',
              )
              as ErrorEvent;
      expect(e.code, 'busy');
      expect(friendlyError(code: e.code, message: e.message), ErrorCopy.busy);
    });
  });

  test('UI code never shows raw exception text', () {
    final patterns = [
      RegExp(r'''['"]\$\{?(e|err|error)\}?['"]'''),
      RegExp(r'\b(e|err|error)\.toString\(\)'),
      RegExp(r'''['"]HTTP \$'''),
      RegExp(r'Text\(\s*(e|err|error)\.message'),
    ];
    final skip = [
      'lib/assist/',
      'lib/features/settings/telemetry/',
      'lib/data/telemetry_api.dart',
    ];
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (skip.any(path.contains)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.contains('debugPrint')) continue;
        if (patterns.any((p) => p.hasMatch(l))) hits.add('$path:${i + 1}: $l');
      }
    }
    expect(hits, isEmpty);
  });
}
