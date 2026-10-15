import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/device_actions.dart';
import 'package:app/core/constants/media_apps.dart';
import 'package:app/core/constants/playlist.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/playlist_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/actions/device_action_runner.dart';
import 'package:app/features/chat/widgets/rich/playlist_card.dart';
import 'package:app/features/chat/widgets/rich/playlist_preview.dart';
import 'package:app/features/chat/widgets/rich/widget_registry.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'assist_circle_actions_test.dart' show FakeRunner;
import 'assist_overlay_test.dart' show FakeChat;

const _source = '''
title: Songs like Kesariya
- Tum Hi Ho | Arijit Singh
- Kesariya | Arijit Singh
- Raataan Lambiyan | Jubin Nautiyal
- Obscure Thing | Nobody
''';

const _ytm = 'com.google.android.apps.youtube.music';
const _spotify = 'com.spotify.music';

class FakeApi extends PlaylistApi {
  FakeApi({this.playAllUrl, this.fail = false});

  final String? playAllUrl;
  final bool fail;
  int enrichCalls = 0;
  int playAllCalls = 0;

  @override
  Future<List<PlaylistTrack>> enrich(List<PlaylistSong> songs) async {
    enrichCalls++;
    if (fail) throw Exception('offline');
    return [
      for (var i = 0; i < songs.length; i++)
        PlaylistTrack(
          title: songs[i].title,
          artist: songs[i].artist,
          // The last song is unknown to iTunes: title and artist only.
          art: i == songs.length - 1 ? null : 'https://art/$i.jpg',
          durationMs: i == songs.length - 1 ? null : 240000 + i * 15000,
          previewUrl: i == songs.length - 1 ? null : 'https://prev/$i.m4a',
          album: 'Album $i',
          year: 2013,
        ),
    ];
  }

  @override
  Future<PlaylistPlayAll> playAll(List<PlaylistSong> songs) async {
    playAllCalls++;
    return PlaylistPlayAll(playAllUrl);
  }
}

/// A preview engine that plays nothing: the test drives its signals.
class FakeEngine implements PreviewEngine {
  FakeEngine(this.log);
  final List<String> log;
  void Function(PreviewSignal)? emit;
  String? url;
  bool stopped = false;

  @override
  Future<void> start(String url, void Function(PreviewSignal) onSignal) async {
    this.url = url;
    emit = onSignal;
    log.add('start $url');
  }

  @override
  Future<void> stop() async {
    stopped = true;
    log.add('stop $url');
  }
}

Uint8List _cover(int r, int g, int b) {
  final im = img.Image(width: 60, height: 60);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodePng(im));
}

final _covers = [
  MemoryImage(_cover(214, 80, 60)),
  MemoryImage(_cover(60, 120, 200)),
  MemoryImage(_cover(90, 170, 110)),
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
  late List<String> engineLog;
  late List<FakeEngine> engines;
  late PreviewController preview;

  setUpAll(() async {
    await _fonts();
    Haptics.enabled = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsController.load();
    DeviceActionRunner.debugSupported = true;
    InstalledMediaApps.reset();
    PlaylistCard.resetCache();
    PlaylistCard.imageFor = (url) {
      final n = int.tryParse(
        RegExp(r'/(\d+)\.jpg').firstMatch(url)?.group(1) ?? '',
      );
      return _covers[(n ?? 0) % _covers.length];
    };
    engineLog = [];
    engines = [];
    preview = PreviewController(
      engine: () {
        final e = FakeEngine(engineLog);
        engines.add(e);
        return e;
      },
    );
  });

  tearDown(() {
    DeviceActionRunner.debugSupported = null;
    PlaylistCard.imageFor = NetworkImage.new;
    InstalledMediaApps.reset();
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

  Future<void> pumpCard(
    WidgetTester tester, {
    FakeApi? api,
    FakeRunner? runner,
    String source = _source,
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      host(
        PlaylistCard(
          source: source,
          api:
              api ??
              FakeApi(playAllUrl: 'https://yt/watch_videos?video_ids=a,b'),
          preview: preview,
          runner: runner ?? FakeRunner(ActionOutcome.done, {_spotify, _ytm}),
        ),
        dark: dark,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('parsing', () {
    test('title, app and songs; junk lines ignored; capped', () {
      final s = PlaylistSpec.parse(
        'title: Mix\napp: Apple Music\n- A | B\n2. C | D\nplain text\n- E |',
      )!;
      expect(s.title, 'Mix');
      expect(s.appKey, 'apple_music');
      expect(s.songs, [
        const PlaylistSong('A', 'B'),
        const PlaylistSong('C', 'D'),
        const PlaylistSong('E', ''),
      ]);
      expect(PlaylistSpec.parse('title: none'), isNull);
      final many = List.generate(30, (i) => '- S$i | A').join('\n');
      expect(
        PlaylistSpec.parse(many)!.songs,
        hasLength(PlaylistSizes.maxSongs),
      );
    });

    test('registered as a rich widget', () {
      final w = buildRichWidget(PlaylistWire.fence, _source, streaming: false);
      expect(w, isA<PlaylistCard>());
      expect(
        buildRichWidget(PlaylistWire.fence, _source, streaming: true),
        isNot(isA<PlaylistCard>()),
      );
    });

    test('search deep links per music app', () {
      expect(
        MediaApps.spotify.searchUrl('Tum Hi Ho Arijit Singh'),
        'https://open.spotify.com/search/Tum%20Hi%20Ho%20Arijit%20Singh',
      );
      expect(
        MediaApps.youtubeMusic.searchUrl('a b'),
        'https://music.youtube.com/search?q=a%20b',
      );
      for (final k in PlaylistWire.appOrder) {
        expect(
          MediaApps.all.firstWhere((a) => a.key == k).searchTemplate,
          contains('{q}'),
        );
      }
    });

    test('duration text', () {
      expect(
        const PlaylistTrack(
          title: 'a',
          artist: 'b',
          durationMs: 262000,
        ).duration,
        '4:22',
      );
      expect(const PlaylistTrack(title: 'a', artist: 'b').duration, '');
    });
  });

  group('card', () {
    testWidgets('renders header, rows, durations; unknown song keeps its row', (
      tester,
    ) async {
      await pumpCard(tester);
      expect(find.text('Songs like Kesariya'), findsOneWidget);
      expect(find.text('4 SONGS · 13 MIN'), findsOneWidget);
      expect(find.text('Tum Hi Ho'), findsOneWidget);
      expect(find.text('Obscure Thing'), findsOneWidget);
      expect(find.text('Nobody'), findsOneWidget);
      expect(find.text('4:00'), findsOneWidget);
      // 3 previews (the unknown song has none), 4 open buttons.
      expect(
        find.bySemanticsLabel(RegExp('^Play 30 second preview')),
        findsNWidgets(3),
      );
      expect(
        find.bySemanticsLabel(RegExp('^Open .* in YouTube Music')),
        findsNWidgets(4),
      );
    });

    testWidgets(
      'offline: rows still show title and artist, no previews, no Play all',
      (tester) async {
        await pumpCard(tester, api: FakeApi(fail: true));
        expect(find.text('Tum Hi Ho'), findsOneWidget);
        expect(find.text('Arijit Singh'), findsNWidgets(2));
        expect(
          find.bySemanticsLabel(RegExp('^Play 30 second preview')),
          findsNothing,
        );
        expect(find.text(PlaylistStrings.playAll), findsNothing);
      },
    );

    testWidgets('bad source falls back to the raw text', (tester) async {
      await pumpCard(tester, source: 'nothing useful');
      expect(find.text('nothing useful'), findsOneWidget);
    });

    testWidgets(
      'Play all: shown only with a link, opens it in the YouTube app',
      (tester) async {
        await pumpCard(tester, api: FakeApi());
        expect(find.text(PlaylistStrings.playAll), findsNothing);

        await tester.pumpWidget(const SizedBox());
        PlaylistCard.resetCache();
        InstalledMediaApps.reset();
        final runner = FakeRunner(ActionOutcome.done, {
          MediaApps.youtube.package,
        });
        await pumpCard(tester, runner: runner);
        expect(find.text(PlaylistStrings.playAll), findsOneWidget);
        await tester.tap(find.text(PlaylistStrings.playAll));
        await tester.pump();
        expect(runner.runs, hasLength(1));
        expect(
          runner.runs.single[DeviceActionWire.url],
          'https://yt/watch_videos?video_ids=a,b',
        );
        expect(
          runner.runs.single[DeviceActionWire.package],
          MediaApps.youtube.package,
        );
      },
    );

    testWidgets(
      'open in app: the installed music app, a search for "title artist"',
      (tester) async {
        final runner = FakeRunner(ActionOutcome.done, {_spotify});
        await pumpCard(tester, runner: runner);
        await tester.tap(find.bySemanticsLabel('Open Tum Hi Ho in Spotify'));
        await tester.pump();
        expect(
          runner.runs.single[DeviceActionWire.url],
          'https://open.spotify.com/search/Tum%20Hi%20Ho%20Arijit%20Singh',
        );
        expect(runner.runs.single[DeviceActionWire.package], _spotify);
      },
    );

    testWidgets(
      'open in app: the app the user named wins; none installed opens the browser',
      (tester) async {
        final runner = FakeRunner(ActionOutcome.done, {_ytm});
        await pumpCard(
          tester,
          runner: runner,
          source: 'app: spotify\n$_source',
        );
        await tester.tap(find.bySemanticsLabel('Open Kesariya in Spotify'));
        await tester.pump();
        // Spotify is named but not installed: no package, so the link opens in the browser.
        expect(
          runner.runs.single[DeviceActionWire.url],
          startsWith('https://open.spotify.com/search/'),
        );
        expect(
          runner.runs.single.fields.containsKey(DeviceActionWire.package),
          isFalse,
        );
      },
    );

    testWidgets('long press copies "title — artist"', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpCard(tester);
      await tester.longPress(find.text('Kesariya'));
      await tester.pump();
      expect(copied, 'Kesariya — Arijit Singh');
      expect(find.text(PlaylistStrings.copied), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(PlaylistStrings.copied), findsNothing);
    });

    testWidgets(
      'server results are asked for once per source (rebuilds use the cache)',
      (tester) async {
        final api = FakeApi(playAllUrl: 'https://yt/x');
        await pumpCard(tester, api: api);
        await tester.pumpWidget(const SizedBox());
        await pumpCard(tester, api: api);
        expect(api.enrichCalls, 1);
        expect(api.playAllCalls, 1);
        expect(find.text(PlaylistStrings.playAll), findsOneWidget);
      },
    );
  });

  group('preview', () {
    testWidgets(
      'state machine: idle -> loading -> playing -> stopped; one at a time',
      (tester) async {
        await pumpCard(tester);
        Finder play(String t) =>
            find.bySemanticsLabel('Play 30 second preview of $t');

        await tester.tap(play('Tum Hi Ho'));
        await tester.pump();
        expect(engineLog, ['start https://prev/0.m4a']);
        expect(preview.phase, PreviewPhase.loading);
        expect(
          find.bySemanticsLabel('Loading preview of Tum Hi Ho'),
          findsOneWidget,
        );

        engines.single.emit!(
          const PreviewSignal(
            position: Duration(seconds: 6),
            total: Duration(seconds: 30),
            playing: true,
          ),
        );
        await tester.pump();
        expect(preview.phase, PreviewPhase.playing);
        expect(preview.progress, closeTo(0.2, 0.001));
        expect(
          find.bySemanticsLabel('Stop preview of Tum Hi Ho'),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Another row: the first stops, the second starts.
        await tester.tap(play('Kesariya'));
        await tester.pump();
        expect(engineLog, [
          'start https://prev/0.m4a',
          'stop https://prev/0.m4a',
          'start https://prev/1.m4a',
        ]);
        expect(
          find.bySemanticsLabel('Stop preview of Tum Hi Ho'),
          findsNothing,
        );
        expect(
          find.bySemanticsLabel('Play 30 second preview of Tum Hi Ho'),
          findsOneWidget,
        );

        // Tapping the playing row stops it.
        engines.last.emit!(
          const PreviewSignal(
            position: Duration(seconds: 1),
            total: Duration(seconds: 30),
            playing: true,
          ),
        );
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('Stop preview of Kesariya'));
        await tester.pump();
        expect(preview.activeId, isNull);
        expect(engines.last.stopped, isTrue);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('the end of the preview resets the row; a failure too', (
      tester,
    ) async {
      await pumpCard(tester);
      await tester.tap(
        find.bySemanticsLabel('Play 30 second preview of Tum Hi Ho'),
      );
      await tester.pump();
      engines.single.emit!(
        const PreviewSignal(
          position: Duration(seconds: 30),
          total: Duration(seconds: 30),
          playing: true,
          ended: true,
        ),
      );
      await tester.pump();
      expect(preview.phase, PreviewPhase.idle);
      expect(preview.failed, isFalse);

      await tester.tap(
        find.bySemanticsLabel('Play 30 second preview of Kesariya'),
      );
      await tester.pump();
      engines.last.emit!(const PreviewSignal(failed: true));
      await tester.pump();
      expect(preview.phase, PreviewPhase.idle);
      expect(preview.failed, isTrue);
    });

    testWidgets('leaving the screen stops the preview', (tester) async {
      await pumpCard(tester);
      await tester.tap(
        find.bySemanticsLabel('Play 30 second preview of Tum Hi Ho'),
      );
      await tester.pump();
      expect(preview.activeId, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(preview.activeId, isNull);
      expect(engines.single.stopped, isTrue);
    });

    test('a card leaving does not cut off another card\'s preview', () async {
      final c = PreviewController(engine: () => FakeEngine([]));
      await c.toggle('pl1:0', 'https://p/a.m4a');
      await c.stopOwned('pl2:');
      expect(c.activeId, 'pl1:0');
      await c.stopOwned('pl1:');
      expect(c.activeId, isNull);
    });
  });

  group('golden', () {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('playlist card $theme', (tester) async {
        tester.view.physicalSize = const Size(412 * 2, 560 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await pumpCard(tester, dark: dark);
        // Row 2 is mid-preview (a ring at 40 %).
        await tester.tap(
          find.bySemanticsLabel('Play 30 second preview of Kesariya'),
        );
        await tester.pump();
        engines.single.emit!(
          const PreviewSignal(
            position: Duration(seconds: 12),
            total: Duration(seconds: 30),
            playing: true,
          ),
        );
        await tester.pump();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/playlist_card_$theme.png'),
        );
      });
    }
  });
}
