import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/device_actions.dart';
import 'package:app/core/constants/media_apps.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/actions/action_card.dart';
import 'package:app/features/actions/device_action.dart';
import 'package:app/features/actions/device_action_runner.dart';
import 'package:app/features/actions/open_in_chips.dart';
import 'package:app/features/chat/widgets/markdown/citation_chip.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assist_circle_actions_test.dart' show FakeRunner;
import 'assist_overlay_test.dart' show FakeChat;

const ytmPackage = 'com.google.android.apps.youtube.music';
const ytmLink =
    '{"type":"url","url":"https://music.youtube.com/watch?v=abcDEF12345",'
    '"app":"YouTube Music","package":"$ytmPackage"}';

const sources = [
  Citation(
    id: 'W1',
    title: 'I Met Her Again - Maan Panu - YouTube',
    url: 'https://www.youtube.com/watch?v=abcDEF12345',
    site: 'youtube.com',
  ),
  Citation(
    id: 'W2',
    title: 'I Met Her Again | JioSaavn',
    url: 'https://www.jiosaavn.com/song/i-met-her-again/ABC',
    site: 'jiosaavn.com',
  ),
  Citation(
    id: 'W3',
    title: 'Maan Panu - Wikipedia',
    url: 'https://en.wikipedia.org/wiki/Maan_Panu',
    site: 'wikipedia.org',
  ),
  Citation(
    id: 'W4',
    title: 'I Met Her Again - Spotify',
    url: 'https://open.spotify.com/track/7xyz123ABC',
    site: 'open.spotify.com',
  ),
];

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
  });

  tearDown(() => DeviceActionRunner.debugSupported = null);

  Widget host(Widget child, {bool dark = false}) => AppScope(
    settings: settings,
    usage: UsageController(UsageApi('http://test')),
    api: FakeChat(),
    baseUrl: 'http://test',
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  group('url action for an app', () {
    test('names the app, by package, name or host', () {
      final a = DeviceAction.parse(ytmLink)!;
      expect(a.mediaApp, MediaApps.youtubeMusic);
      expect(a.title, MediaAppStrings.openIn('YouTube Music'));
      expect(a.kicker, MediaAppStrings.kicker);
      final byHost = DeviceAction.parse(
        '{"type":"url","url":"https://open.spotify.com/track/abc"}',
      )!;
      expect(byHost.mediaApp, MediaApps.spotify);
      expect(byHost.inApp()[DeviceActionWire.package], 'com.spotify.music');
      expect(byHost.inBrowser()[DeviceActionWire.package], isNull);
      expect(byHost.storePage()![DeviceActionWire.store], 'com.spotify.music');
      final plain = DeviceAction.parse(
        '{"type":"url","url":"https://example.com/a"}',
      )!;
      expect(plain.mediaApp, isNull);
      expect(plain.title, 'example.com');
    });

    testWidgets('installed: Open runs the link in the app', (tester) async {
      final runner = FakeRunner(ActionOutcome.done, {ytmPackage});
      await tester.pumpWidget(
        host(ActionCard(source: ytmLink, runner: runner)),
      );
      await tester.pump();
      expect(runner.checks.single, [ytmPackage]);
      expect(
        find.text(MediaAppStrings.openIn('YouTube Music')),
        findsOneWidget,
      );
      expect(find.text(MediaAppStrings.openInBrowser), findsNothing);
      await tester.tap(find.text(MediaAppStrings.open));
      await tester.pump();
      expect(runner.runs.single[DeviceActionWire.package], ytmPackage);
      expect(find.text(DeviceActionStrings.opened), findsOneWidget);
    });

    testWidgets('not installed: browser or store, never a dead button', (
      tester,
    ) async {
      final runner = FakeRunner();
      await tester.pumpWidget(
        host(ActionCard(source: ytmLink, runner: runner)),
      );
      await tester.pump();
      expect(
        find.text(MediaAppStrings.notInstalled('YouTube Music')),
        findsOneWidget,
      );
      expect(find.text(DeviceActionStrings.confirm), findsNothing);
      expect(find.text(MediaAppStrings.getApp), findsOneWidget);
      await tester.tap(find.text(MediaAppStrings.openInBrowser));
      await tester.pump();
      final run = runner.runs.single;
      expect(
        run[DeviceActionWire.url],
        'https://music.youtube.com/watch?v=abcDEF12345',
      );
      expect(run[DeviceActionWire.package], isNull);
    });

    testWidgets('not installed: Get the app opens the store page', (
      tester,
    ) async {
      final runner = FakeRunner();
      await tester.pumpWidget(
        host(ActionCard(source: ytmLink, runner: runner)),
      );
      await tester.pump();
      await tester.tap(find.text(MediaAppStrings.getApp));
      await tester.pump();
      final run = runner.runs.single;
      expect(run[DeviceActionWire.store], ytmPackage);
      expect(run[DeviceActionWire.url], MediaAppWire.storePage(ytmPackage));
    });

    testWidgets('no link was found: the app search deep link is a card too', (
      tester,
    ) async {
      final runner = FakeRunner(ActionOutcome.done, {ytmPackage});
      const search =
          '{"type":"url","url":"https://music.youtube.com/search?q=I%20Met%20Her%20Again",'
          '"app":"YouTube Music","package":"$ytmPackage"}';
      await tester.pumpWidget(host(ActionCard(source: search, runner: runner)));
      await tester.pump();
      await tester.tap(find.text(MediaAppStrings.open));
      await tester.pump();
      expect(runner.runs.single[DeviceActionWire.url], contains('/search?q='));
      expect(runner.runs.single[DeviceActionWire.package], ytmPackage);
    });
  });

  group('Open in chips', () {
    test('one chip per known app, at most three, unknown sites skipped', () {
      final links = OpenInChips.linksOf(sources);
      expect(
        [for (final (a, _) in links) a],
        [MediaApps.youtube, MediaApps.jiosaavn, MediaApps.spotify],
      );
      expect(OpenInChips.linksOf(const []), isEmpty);
      // A bare home page is not worth a chip.
      expect(MediaApps.youtube.owns('https://www.youtube.com/'), isFalse);
      expect(
        MediaApps.maps.owns('https://www.google.com/maps/place/Taj+Mahal'),
        isTrue,
      );
    });

    testWidgets('tap opens straight away: in the app, else the browser', (
      tester,
    ) async {
      final runner = FakeRunner(ActionOutcome.done, {
        MediaApps.youtube.package,
      });
      await tester.pumpWidget(
        host(OpenInChips(citations: sources, runner: runner)),
      );
      await tester.pump();
      expect(find.text(MediaAppStrings.openIn('YouTube')), findsOneWidget);
      expect(find.text(MediaAppStrings.inBrowser('JioSaavn')), findsOneWidget);
      await tester.tap(find.text(MediaAppStrings.openIn('YouTube')));
      await tester.pump();
      expect(
        runner.runs.last[DeviceActionWire.package],
        MediaApps.youtube.package,
      );
      await tester.tap(find.text(MediaAppStrings.inBrowser('JioSaavn')));
      await tester.pump();
      expect(runner.runs.last[DeviceActionWire.package], isNull);
      expect(
        runner.runs.last[DeviceActionWire.url],
        'https://www.jiosaavn.com/song/i-met-her-again/ABC',
      );
    });

    testWidgets('nothing on platforms without actions', (tester) async {
      DeviceActionRunner.debugSupported = false;
      await tester.pumpWidget(
        host(OpenInChips(citations: sources, runner: FakeRunner())),
      );
      expect(find.text(MediaAppStrings.openIn('YouTube')), findsNothing);
    });

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('chips and a not-installed card ($theme)', (tester) async {
        tester.view.physicalSize = const Size(412, 915) * 2.6;
        tester.view.devicePixelRatio = 2.6;
        addTearDown(tester.view.reset);
        final runner = FakeRunner(ActionOutcome.done, {
          MediaApps.youtube.package,
          MediaApps.spotify.package,
        });
        await tester.pumpWidget(
          host(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OpenInChips(citations: sources, runner: runner),
                const SizedBox(height: 16),
                ActionCard(source: ytmLink, runner: runner),
              ],
            ),
            dark: dark,
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/open_in_app_$theme.png'),
        );
      });
    }
  });

  group('citation spacing', () {
    test('dropped tags leave no space before punctuation (phone strings)', () {
      expect(
        prepareCitations(
          'released in India [W1]. You can open it on YouTube Music [W3].',
          const [],
        ),
        'released in India. You can open it on YouTube Music.',
      );
      expect(
        prepareCitations(
          'a [W1], b [W2]; c [W3]: d [W4]! e [W5]? (f [W6])',
          const [],
        ),
        'a, b; c: d! e? (f)',
      );
    });

    test('kept chips sit against the punctuation; other text is untouched', () {
      expect(prepareCitations('India [W1] .', sources), 'India [W1].');
      expect(prepareCitations('India [W1].', sources), 'India [W1].');
      expect(prepareCitations('Is it ? Yes .', sources), 'Is it ? Yes .');
      expect(
        prepareCitations('```\ncode [W9] .\n```', const []),
        '```\ncode [W9] .\n```',
      );
    });
  });

  group('request', () {
    test('the last answers\' web links go with an action request', () {
      final first = ChatMessage(role: Role.assistant, content: 'a')
        ..citations = sources;
      final links = recentSourceLinks([
        ChatMessage(role: Role.user, content: 'what is this'),
        first,
        ChatMessage(role: Role.user, content: 'Open on youtube music'),
      ]);
      expect(links.first, {
        'url': 'https://www.youtube.com/watch?v=abcDEF12345',
        'title': 'I Met Her Again - Maan Panu - YouTube',
      });
      expect(links, hasLength(4));
    });
  });
}
