import 'package:flutter_test/flutter_test.dart';
import 'package:app/data/api_client.dart';
import 'package:app/data/chat_event.dart';

void main() {
  group('Citation kind', () {
    test('every kind survives save and reload', () {
      for (final k in CitationKind.values) {
        final c = Citation(id: 'X1', kind: k, title: 't', url: 'u', site: 's');
        expect(Citation.fromJson(c.toJson()).kind, k);
      }
    });

    test('stored JSON from before stays readable', () {
      expect(Citation.fromJson({'id': 'K1', 'kind': 'kb'}).isKb, isTrue);
      expect(Citation.fromJson({'id': 'W1', 'kind': 'web'}).isKb, isFalse);
      expect(
        Citation.fromJson({'id': 'D1', 'kind': 'file'}).kind,
        CitationKind.file,
      );
      expect(Citation.fromJson({'id': 'W2'}).kind, CitationKind.web);
      expect(
        Citation.fromJson({'id': 'W3', 'kind': 'weird'}).kind,
        CitationKind.web,
      );
    });

    test('the isKb flag still builds the right kind', () {
      expect(
        const Citation(id: 'K1', isKb: true, title: '', url: '', site: '').kind,
        CitationKind.kb,
      );
    });
  });

  group('AuthClient.isApiUrl', () {
    final base = Uri.parse('https://api.example.com');

    test('same origin matches', () {
      expect(
        AuthClient.isApiUrl(Uri.parse('https://api.example.com/chat'), base),
        isTrue,
      );
      expect(
        AuthClient.isApiUrl(
          Uri.parse('https://api.example.com:443/chat'),
          base,
        ),
        isTrue,
      );
    });

    test('look-alike hosts, other schemes and ports do not', () {
      for (final u in [
        'https://api.example.com.evil.tld/chat',
        'https://evil.tld/https://api.example.com',
        'https://api.example.com@evil.tld/chat',
        'http://api.example.com/chat',
        'https://api.example.com:8443/chat',
      ]) {
        expect(AuthClient.isApiUrl(Uri.parse(u), base), isFalse, reason: u);
      }
    });

    test('a base path matches only on a / boundary', () {
      final b = Uri.parse('https://api.example.com/v1');
      expect(
        AuthClient.isApiUrl(Uri.parse('https://api.example.com/v1/chat'), b),
        isTrue,
      );
      expect(
        AuthClient.isApiUrl(Uri.parse('https://api.example.com/v10/chat'), b),
        isFalse,
      );
    });

    test('the refresh endpoint is never authorized', () {
      expect(
        AuthClient.isApiUrl(
          Uri.parse('https://api.example.com/auth/refresh'),
          base,
        ),
        isFalse,
      );
    });
  });
}
