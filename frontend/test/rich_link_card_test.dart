import 'dart:io';

import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/device_actions.dart';
import 'package:app/core/constants/media_apps.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/actions/action_card.dart';
import 'package:app/features/actions/device_action.dart';
import 'package:app/features/actions/device_action_runner.dart';
import 'package:app/features/actions/open_in_chips.dart';
import 'package:app/features/chat/widgets/markdown/app_markdown.dart';
import 'package:app/features/chat/widgets/markdown/citation_chip.dart';
import 'package:app/features/chat/widgets/source_chips.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assist_circle_actions_test.dart' show FakeRunner;
import 'assist_overlay_test.dart' show FakeChat;

/// A YouTube-style 4:3 thumbnail with black bars (zoomed away by the card).
final _cover = MemoryImage(
  File('test/fixtures/yt_thumb.png').readAsBytesSync(),
);

const _ytm = 'com.google.android.apps.youtube.music';

/// The card the backend sends for "Open on youtube music" (with a cover).
const _withImage =
    '{"type":"url","url":"https://music.youtube.com/watch?v=Zx9Yv8W7u6T",'
    '"app":"YouTube Music","package":"$_ytm","title":"Rab Diyan Rab Jaane",'
    '"subtitle":"Gurnam Bhullar",'
    '"image":"https://i.ytimg.com/vi/Zx9Yv8W7u6T/hqdefault.jpg"}';

/// No cover found (the app's search page): the logo fills the slot.
const _noImage =
    '{"type":"url","url":"https://open.spotify.com/search/Rab%20Diyan",'
    '"app":"Spotify","package":"com.spotify.music",'
    '"title":"Rab Diyan Rab Jaane","subtitle":"Gurnam Bhullar"}';

Future<void> _fonts() async {
  for (final (family, files) in [
    ('SpaceGrotesk', ['SpaceGrotesk.ttf']),
    ('SpaceMono', ['SpaceMono-Regular.ttf', 'SpaceMono-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
}

const _citations = [
  Citation(
    id: 'W1',
    title: 'Rab Diyan Rab Jaane | Spotify',
    url: 'https://open.spotify.com/track/4abcDEF123',
    site: 'open.spotify.com',
  ),
  Citation(
    id: 'W2',
    title: 'Rab Diyan Rab Jaane | Spotify',
    url: 'https://open.spotify.com/track/4abcDEF123?si=x',
    site: 'open.spotify.com',
  ),
  Citation(
    id: 'W3',
    title: 'Rab Diyan Rab Jaane - Chartex',
    url: 'https://chartex.com/song/rab-diyan',
    site: 'chartex.com',
  ),
  Citation(
    id: 'W4',
    title: 'Rab Diyan Rab Jaane (Official Video) - YouTube',
    url: 'https://www.youtube.com/watch?v=Zx9Yv8W7u6T',
    site: 'youtube.com',
  ),
];

void main() {
  late SettingsController settings;

  setUpAll(() async {
    await _fonts();
    Haptics.enabled = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsController.load();
    ActionCard.resetOutcomes();
    DeviceActionRunner.debugSupported = true;
    // A local cover stands in for the network one.
    LinkCardHeader.imageFor = (_) => _cover;
  });

  tearDown(() {
    DeviceActionRunner.debugSupported = null;
    LinkCardHeader.imageFor = NetworkImage.new;
  });

  Widget host(Widget child, {bool dark = false}) => AppScope(
    settings: settings,
    usage: UsageController(UsageApi('http://test')),
    api: FakeChat(),
    baseUrl: 'http://test',
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );

  group('rich link card', () {
    test(
      'title, subtitle and cover; the card-only keys never reach Kotlin',
      () {
        final a = DeviceAction.parse(_withImage)!;
        expect(a.linkTitle, 'Rab Diyan Rab Jaane');
        expect(a.linkSubtitle, 'Gurnam Bhullar');
        expect(a.linkImage, startsWith('https://i.ytimg.com/'));
        expect(a.details, isEmpty);
        final channel = a.toChannel();
        expect(channel[DeviceActionWire.url], contains('music.youtube.com'));
        expect(channel.containsKey(DeviceActionWire.title), isFalse);
        expect(channel.containsKey(DeviceActionWire.image), isFalse);
        // Without a title the site's host names it; never the bare link.
        final plain = DeviceAction.parse(
          '{"type":"url","url":"https://www.example.com/a/b?c=1",'
          '"image":"http://insecure.example/x.jpg"}',
        )!;
        expect(plain.linkTitle, 'example.com');
        expect(plain.linkImage, isNull);
      },
    );

    testWidgets('never shows the bare URL; the button names the app', (
      tester,
    ) async {
      final runner = FakeRunner(ActionOutcome.done, {_ytm});
      await tester.pumpWidget(
        host(ActionCard(source: _withImage, runner: runner)),
      );
      await tester.pump();
      expect(find.textContaining('https://'), findsNothing);
      expect(find.text('Rab Diyan Rab Jaane'), findsOneWidget);
      expect(find.text('Gurnam Bhullar'), findsOneWidget);
      expect(find.text('YOUTUBE MUSIC'), findsOneWidget);
      await tester.tap(find.text(MediaAppStrings.openIn('YouTube Music')));
      await tester.pump();
      expect(runner.runs.single[DeviceActionWire.package], _ytm);
    });

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('cover, logo and not-installed variants ($theme)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(412, 915) * 2.6;
        tester.view.devicePixelRatio = 2.6;
        addTearDown(tester.view.reset);
        final installed = FakeRunner(ActionOutcome.done, {
          _ytm,
          'com.spotify.music',
        });
        await tester.pumpWidget(
          host(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ActionCard(source: _withImage, runner: installed),
                ActionCard(source: _noImage, runner: installed),
                // Not installed: browser or store.
                ActionCard(
                  source: _withImage.replaceFirst('Zx9', 'Ab1'),
                  runner: FakeRunner(),
                ),
              ],
            ),
            dark: dark,
          ),
        );
        await tester.runAsync(
          () => precacheImage(_cover, tester.element(find.byType(Scaffold))),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/rich_link_card_$theme.png'),
        );
      });
    }
  });

  test('the installed media apps go with a chat request, by key', () async {
    InstalledMediaApps.reset();
    final runner = FakeRunner(ActionOutcome.done, {
      MediaApps.spotify.package,
      _ytm,
    });
    expect(InstalledMediaApps.cached, isNull);
    expect(await InstalledMediaApps.keys(runner: runner), [
      'youtube_music',
      'spotify',
    ]);
    final body = deviceActionsRequest(null, InstalledMediaApps.cached);
    expect(body[DeviceActionWire.installedApps], ['youtube_music', 'spotify']);
    expect(
      deviceActionsRequest().containsKey(DeviceActionWire.installedApps),
      isFalse,
    );
    InstalledMediaApps.reset();
  });

  group('chips', () {
    test('source chips: one per site (no Spotify twice)', () {
      final chips = SourceChips.distinct(_citations, {'W2'});
      expect([for (final (c, _) in chips) c.id], ['W1', 'W3', 'W4']);
      // Cited through its second page.
      expect(chips.first.$2, isTrue);
    });

    test('open-in chips: installed first, at most two, no browser twin', () {
      final links = OpenInChips.linksOf(_citations);
      expect(
        [for (final (a, _) in links) a],
        [MediaApps.spotify, MediaApps.youtube],
      );
      // Before the phone answers, the links as found.
      expect(OpenInChips.visible(links, const {}), links);
      final music = OpenInChips.linksOf([
        ..._citations,
        const Citation(
          id: 'W5',
          title: 'JioSaavn',
          url: 'https://www.jiosaavn.com/song/rab-diyan/X',
          site: 'jiosaavn.com',
        ),
      ]);
      final shown = OpenInChips.visible(music, {
        MediaApps.spotify.package: false,
        MediaApps.youtube.package: true,
        MediaApps.jiosaavn.package: true,
      });
      // JioSaavn (installed, music) hides "Spotify in browser"; YouTube is installed too.
      expect(
        [for (final (a, _) in shown) a],
        [MediaApps.youtube, MediaApps.jiosaavn],
      );
    });
  });

  group('answer text', () {
    Future<void> pumpAnswer(
      WidgetTester tester,
      String text, {
      bool dark = false,
    }) async {
      tester.view.physicalSize = const Size(412, 300) * 2.6;
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          AppMarkdown(data: text, citations: _citations, streaming: false),
          dark: dark,
        ),
      );
      await tester.pump();
    }

    testWidgets('a bare link becomes a site chip, not raw text', (
      tester,
    ) async {
      await pumpAnswer(
        tester,
        'Listen at https://www.jiosaavn.com/song/rab-diyan/X, or see '
        '[the video](https://www.youtube.com/watch?v=Zx9Yv8W7u6T).',
      );
      expect(find.textContaining('https://'), findsNothing);
      final chips = tester.widgetList<CitationChip>(find.byType(CitationChip));
      expect(chips.map((c) => c.citation.url), [
        'https://www.jiosaavn.com/song/rab-diyan/X',
      ]);
      expect(find.textContaining('the video'), findsOneWidget);
    });

    testWidgets('punctuation hugs a citation chip', (tester) async {
      await pumpAnswer(
        tester,
        'Stream it on Spotify [W1] . Or YouTube [W4]\u00a0. Or Chartex [W3].',
      );
      // The space the model left before the period is gone.
      final para = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText())
          .join('|');
      expect(para, isNot(contains(' .')));
      expect(para, isNot(contains('\u00a0.')));
      // The period starts right where the chip's pill ends (no trailing room).
      final pad = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(CitationChip).first,
              matching: find.byType(Padding),
            )
            .first,
      );
      expect((pad.padding as EdgeInsets).right, 0);
    });

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('chips in prose ($theme)', (tester) async {
        await pumpAnswer(
          tester,
          'You can stream **Rab Diyan Rab Jaane** on Spotify [W1]. The video '
          'is on YouTube [W4], and lyrics are at '
          'https://www.lyricsmint.com/gurnam-bhullar/rab-diyan.',
          dark: dark,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/chips_in_prose_$theme.png'),
        );
      });
    }
  });
}
