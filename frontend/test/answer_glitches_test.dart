import 'package:app/core/constants/media_apps.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/features/actions/device_action.dart';
import 'package:app/features/actions/open_in_chips.dart';
import 'package:app/features/chat/widgets/markdown/app_markdown.dart';
import 'package:app/features/chat/widgets/markdown/citation_chip.dart';
import 'package:app/features/chat/widgets/markdown/timeline_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real-phone glitches of the assistant overlay's answers (sparky 1.5.3).
const _cites = [
  Citation(
    id: 'W3',
    title: 'Chillhop Essentials',
    url: 'https://www.youtube.com/playlist?list=PLOzDu-MXXLliO9fBNZOQTBDddoA3FzZUo',
    site: 'youtube.com',
  ),
  Citation(
    id: 'W4',
    title: 'Lofi Girl - chill beats to code/relax to',
    url: 'https://music.youtube.com/watch?v=jfKfPfyJRdk',
    site: 'music.youtube.com',
  ),
];

Future<List<String>> _rendered(WidgetTester tester, String md) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AppMarkdown(data: md, citations: _cites, streaming: false),
        ),
      ),
    ),
  );
  await tester.pump();
  return [
    for (final r in tester.widgetList<RichText>(find.byType(RichText)))
      r.text.toPlainText(),
  ];
}

void main() {
  group('citation inside / next to inline code', () {
    test('a code span of only tags is unwrapped', () {
      expect(untickCitations('Chillhop — `[W3]`'), 'Chillhop — [W3]');
      expect(untickCitations('a `[W3] [W4]` b'), 'a [W3] [W4] b');
      expect(untickCitations('a `[W3, W4]` b'), 'a [W3, W4] b');
    });

    test('an unpaired backtick in a cited line is dropped', () {
      expect(untickCitations('Chillhop Essentials — ` [W3]'),
          'Chillhop Essentials — [W3]');
      expect(untickCitations('Chillhop Essentials — `[W3]'),
          'Chillhop Essentials — [W3]');
      expect(untickCitations('Chillhop Essentials [W3] `'),
          'Chillhop Essentials [W3]');
      expect(untickCitations('Run `npm i` now [W3]`'), 'Run `npm i` now [W3]');
    });

    test('real code spans and uncited lines are untouched', () {
      expect(untickCitations('Use `Timer` here [W3]'), 'Use `Timer` here [W3]');
      expect(untickCitations('a lone ` here'), 'a lone ` here');
      expect(untickCitations('```dart'), '```dart');
      expect(
        prepareCitations('```\nx = `[W3]\n```', _cites),
        '```\nx = `[W3]\n```',
      );
    });

    testWidgets('the "Also worth queuing up next" item renders cleanly', (
      tester,
    ) async {
      const answer =
          'Lofi Girl is the classic pick [W4].\n\n'
          '**Also worth queuing up next**\n\n'
          '- **Chillhop Essentials** — ` [W3]\n';
      final texts = await _rendered(tester, answer);
      final item = texts.firstWhere((t) => t.startsWith('Chillhop'));
      expect(item, isNot(contains('`')));
      expect(item, isNot(contains('[W3]')));
      // The tag became a chip (a placeholder in the text).
      expect(item, contains('￼'));
    });

    testWidgets('a backticked tag is a chip, not raw `[W3]` code', (
      tester,
    ) async {
      final texts = await _rendered(
        tester,
        '- **Chillhop Essentials** — `[W3]`\n- **Jazz Vibes** — mellow',
      );
      expect(texts.join(' '), isNot(contains('[W3]')));
    });
  });

  testWidgets('a one-item list gets a plain dot, not a lone black square', (
    tester,
  ) async {
    await _rendered(tester, '**Also worth queuing up next**\n\n- Chillhop');
    final boxes = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(TimelineList),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    expect(
      boxes.any((d) => d.shape == BoxShape.circle && d.color != null),
      isTrue,
    );
    expect(
      boxes.any((d) => d.shape == BoxShape.rectangle && d.color != null),
      isFalse,
    );
  });

  group('Open-in chips vs action cards', () {
    const card =
        'Here it is.\n\n```sparky-action\n'
        '{"type":"url","url":"https://music.youtube.com/watch?v=jfKfPfyJRdk",'
        '"app":"YouTube Music","package":"com.google.android.apps.youtube.music"}'
        '\n```';

    test('no "Open in YouTube Music" chip when a card opens it', () {
      expect(OpenInChips.cardApps(card), {MediaApps.youtubeMusic});
      final all = OpenInChips.linksOf(_cites);
      expect(all.map((l) => l.$1), contains(MediaApps.youtubeMusic));
      final shown = OpenInChips.linksOf(_cites, content: card);
      expect(shown.map((l) => l.$1), isNot(contains(MediaApps.youtubeMusic)));
      // Other apps keep their chip.
      expect(shown.map((l) => l.$1), contains(MediaApps.youtube));
    });

    test('a broken or non-app action block hides nothing', () {
      expect(OpenInChips.cardApps('```sparky-action\n{oops\n```'), isEmpty);
      expect(
        OpenInChips.cardApps(
          '```sparky-action\n{"type":"alarm","time":"07:00"}\n```',
        ),
        isEmpty,
      );
      expect(OpenInChips.linksOf(_cites, content: 'plain'), hasLength(2));
    });
  });

  group('YouTube thumbnails on the card', () {
    test('live streams (watch?v= and /live/<id>) and embeds have an id', () {
      for (final url in [
        'https://www.youtube.com/watch?v=jfKfPfyJRdk',
        'https://www.youtube.com/live/jfKfPfyJRdk?si=x',
        'https://music.youtube.com/watch?v=jfKfPfyJRdk&list=RDjfKfPfyJRdk',
        'https://www.youtube.com/embed/jfKfPfyJRdk',
      ]) {
        expect(
          MediaAppWire.youtubeId.firstMatch(url)?.group(1),
          'jfKfPfyJRdk',
          reason: url,
        );
      }
    });

    test('a live link without an image still gets its thumbnail', () {
      final a = DeviceAction.parse(
        '{"type":"url","url":"https://www.youtube.com/live/jfKfPfyJRdk",'
        '"app":"YouTube","title":"Lofi Girl - chill beats to code/relax to"}',
      )!;
      expect(a.linkImage, 'https://i.ytimg.com/vi/jfKfPfyJRdk/hqdefault.jpg');
    });
  });
}
