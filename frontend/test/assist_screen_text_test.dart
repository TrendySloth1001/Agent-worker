import 'package:app/assist/assist_links.dart';
import 'package:app/assist/screen_text.dart';
import 'package:app/core/notify/notify_target.dart';
import 'package:flutter_test/flutter_test.dart';

ScreenNode t(String s) => ScreenNode(s);
ScreenNode d(String s) => ScreenNode(s, description: true);

void main() {
  group('buildScreenText', () {
    test('collapses whitespace and drops empty or invisible-only nodes', () {
      final out = buildScreenText([
        t('  Hello\n\n   world  '),
        t('   '),
        t('​​'),
        t('Next\tline'),
      ]);
      expect(out, 'Hello world\nNext line');
    });

    test('drops exact duplicates regardless of case', () {
      final out = buildScreenText([
        t('Inbox'),
        t('Meeting at 5'),
        t('INBOX'),
        t('Meeting at 5'),
      ]);
      expect(out, 'Inbox\nMeeting at 5');
    });

    test('keeps the fuller of a container and its label', () {
      expect(
        buildScreenText([t('Order #4411 shipped'), t('Order #4411')]),
        'Order #4411 shipped',
      );
      expect(
        buildScreenText([t('Order #4411'), t('Order #4411 shipped today')]),
        'Order #4411 shipped today',
      );
    });

    test('skips short content descriptions, keeps descriptive ones', () {
      final out = buildScreenText([
        d('Back'),
        d('More options'),
        t('Article title'),
        d('Photo of a red bicycle by the lake'),
      ]);
      expect(out, 'Article title\nPhoto of a red bicycle by the lake');
    });

    test('caps the total on a line boundary', () {
      final nodes = [for (var i = 0; i < 100; i++) t('line number $i')];
      final out = buildScreenText(nodes, maxChars: 60);
      expect(out.length, lessThanOrEqualTo(60));
      expect(out.split('\n').last, startsWith('line number'));
      expect(out, startsWith('line number 0\nline number 1'));
    });

    test('a single huge node is cut, not lost', () {
      final out = buildScreenText([t('x' * 10000)], maxChars: 100);
      expect(out.length, lessThanOrEqualTo(100));
      expect(out, endsWith('…'));
    });

    test('default cap is about 6k characters', () {
      final nodes = [for (var i = 0; i < 2000; i++) t('row $i of the feed')];
      expect(buildScreenText(nodes).length, lessThanOrEqualTo(6000));
    });
  });

  group('ScreenContext', () {
    test('reads the channel map and builds the request field', () {
      final ctx = ScreenContext.fromChannel({
        'available': true,
        'nodes': [
          {'text': 'Flight UA 88', 'desc': false},
          {'text': 'Back', 'desc': true},
          {'text': 'Gate 12', 'desc': false},
          'junk',
        ],
        'app': 'Gmail',
        'package': 'com.google.android.gm',
        'url': null,
        'screenshot': '/cache/assist/screen-1.jpg',
        'structureArrived': true,
      });
      expect(ctx.text, 'Flight UA 88\nGate 12');
      expect(ctx.appName, 'Gmail');
      expect(ctx.hasScreenshot, isTrue);
      expect(ctx.toJson(), {
        'text': 'Flight UA 88\nGate 12',
        'app': 'Gmail',
        'package': 'com.google.android.gm',
        'screenshot': true,
      });
    });

    test('falls back to the package name and knows when it is empty', () {
      final ctx = ScreenContext.fromChannel({'package': 'com.example.x'});
      expect(ctx.appName, 'com.example.x');
      expect(ctx.isEmpty, isTrue);
      expect(ctx.toJson().containsKey('screenshot'), isFalse);
    });
  });

  group('AssistLinks', () {
    test('maps overlay links to in-app targets', () {
      expect(
        AssistLinks.targetFor(Uri.parse('sparky://chat/abc-123')),
        const ChatTarget('abc-123'),
      );
      expect(
        AssistLinks.targetFor(Uri.parse('sparky://settings/assistant')),
        isA<SettingsTarget>().having((t) => t.page, 'page', 'assistant'),
      );
    });

    test('ignores other links', () {
      expect(
        AssistLinks.targetFor(Uri.parse('sparky://auth/github?ticket=1')),
        isNull,
      );
      expect(AssistLinks.targetFor(Uri.parse('https://chat/abc')), isNull);
      expect(AssistLinks.targetFor(Uri.parse('sparky://chat')), isNull);
    });
  });
}
