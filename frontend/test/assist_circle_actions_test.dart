import 'dart:async';
import 'dart:io';

import 'package:app/assist/assist_bridge.dart';
import 'package:app/assist/assist_controller.dart';
import 'package:app/assist/assist_overlay.dart';
import 'package:app/assist/circle/circle_crop.dart';
import 'package:app/assist/circle/circle_geometry.dart';
import 'package:app/assist/circle/circle_view.dart';
import 'package:app/assist/screen_text.dart';
import 'package:app/assist/share_payload.dart';
import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/assist.dart';
import 'package:app/core/constants/circle_search.dart';
import 'package:app/core/constants/device_actions.dart';
import 'package:app/core/constants/media_apps.dart';
import 'package:app/core/constants/smart_toggles.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/actions/action_card.dart';
import 'package:app/features/actions/device_action.dart';
import 'package:app/features/actions/device_action_runner.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/chat/attachments_controller.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'assist_overlay_test.dart'
    show FakeBridge, FakeChat, FakeConversations, FakeFiles;

// ---- fakes -------------------------------------------------------------------

class FakeCropper implements CircleCropper {
  @override
  Future<bool> isBlank(String path) async => false;

  FakeCropper(this.path);
  final String path;
  final calls = <(Rect, Size)>[];

  @override
  Future<String?> crop(String screenshot, Rect selection, Size view) async {
    calls.add((selection, view));
    return path;
  }
}

/// A cropper whose cut-out is a blank (black) capture.
class BlankCropper extends FakeCropper {
  BlankCropper(super.path);

  @override
  Future<bool> isBlank(String path) async => true;
}

/// A cropper whose cut-outs finish only when the test says so.
class GatedCropper implements CircleCropper {
  @override
  Future<bool> isBlank(String path) async => false;

  final calls = <Rect>[];
  final gates = <Completer<String?>>[];

  @override
  Future<String?> crop(String screenshot, Rect selection, Size view) {
    calls.add(selection);
    final gate = Completer<String?>();
    gates.add(gate);
    return gate.future;
  }
}

/// A cropper that fails like a broken decode in the isolate.
class ThrowingCropper implements CircleCropper {
  @override
  Future<bool> isBlank(String path) async => false;

  int calls = 0;

  @override
  Future<String?> crop(String screenshot, Rect selection, Size view) async {
    calls++;
    throw StateError('decode failed');
  }
}

class FakeRunner implements DeviceActionRunner {
  FakeRunner([this.outcome = ActionOutcome.done, this.installed = const {}]);
  final ActionOutcome outcome;

  /// Installed packages; any other is reported as not installed.
  final Set<String> installed;
  final runs = <DeviceAction>[];
  final checks = <List<String>>[];

  @override
  Future<ActionOutcome> run(DeviceAction action) async {
    runs.add(action);
    return outcome;
  }

  @override
  Future<Map<String, bool>> appAvailability(List<String> packages) async {
    checks.add(packages);
    return {for (final p in packages) p: installed.contains(p)};
  }
}

// ---- a plausible shop page as the frozen screenshot -----------------------------

Uint8List _shopScreenshot() {
  final im = img.Image(width: 412, height: 915);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(
    im,
    x1: 0,
    y1: 0,
    x2: 412,
    y2: 64,
    color: img.ColorRgb8(245, 245, 245),
  );
  img.drawString(
    im,
    'Sneaker Shop',
    font: img.arial24,
    x: 20,
    y: 20,
    color: img.ColorRgb8(30, 30, 30),
  );
  // The product photo: a shoe on a pale tile.
  img.fillRect(
    im,
    x1: 20,
    y1: 90,
    x2: 392,
    y2: 400,
    color: img.ColorRgb8(238, 240, 243),
    radius: 18,
  );
  img.fillRect(
    im,
    x1: 90,
    y1: 250,
    x2: 330,
    y2: 320,
    color: img.ColorRgb8(215, 25, 33),
    radius: 30,
  );
  img.fillCircle(
    im,
    x: 140,
    y: 250,
    radius: 52,
    color: img.ColorRgb8(215, 25, 33),
  );
  img.fillRect(
    im,
    x1: 90,
    y1: 312,
    x2: 340,
    y2: 332,
    color: img.ColorRgb8(250, 250, 250),
    radius: 8,
  );
  img.fillCircle(
    im,
    x: 150,
    y: 240,
    radius: 14,
    color: img.ColorRgb8(250, 250, 250),
  );
  img.drawString(
    im,
    'Air Runner 90',
    font: img.arial24,
    x: 20,
    y: 420,
    color: img.ColorRgb8(30, 30, 30),
  );
  img.drawString(
    im,
    '129.00',
    font: img.arial24,
    x: 20,
    y: 456,
    color: img.ColorRgb8(90, 90, 90),
  );
  for (var i = 0; i < 6; i++) {
    img.fillRect(
      im,
      x1: 20,
      y1: 510 + i * 26,
      x2: 20 + 340 - (i % 3) * 60,
      y2: 520 + i * 26,
      color: img.ColorRgb8(226, 226, 226),
      radius: 5,
    );
  }
  img.fillRect(
    im,
    x1: 20,
    y1: 700,
    x2: 392,
    y2: 752,
    color: img.ColorRgb8(20, 20, 20),
    radius: 26,
  );
  img.drawString(
    im,
    'Add to bag',
    font: img.arial24,
    x: 150,
    y: 714,
    color: img.ColorRgb8(255, 255, 255),
  );
  return Uint8List.fromList(img.encodePng(im));
}

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

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  tester.view.padding = const FakeViewPadding(top: 24 * 2.6, bottom: 16 * 2.6);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Past the pause that ends a selection (strokes merge until then), settled.
Future<void> _select(WidgetTester tester) async {
  await tester.pump(CircleConfig.strokeMerge);
  await _settle(tester);
}

Future<void> _golden(WidgetTester tester, String file) async {
  debugDisableShadows = false;
  try {
    for (final e in find.byType(Container).evaluate()) {
      e.renderObject?.markNeedsPaint();
    }
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
  } finally {
    debugDisableShadows = true;
  }
}

class _Harness {
  _Harness(this.settings, this.shot, this.cropPath, [this.customCropper]);

  final SettingsController settings;
  final Uint8List shot;
  final String cropPath;
  final CircleCropper? customCropper;
  final bridge = FakeBridge();
  final chat = FakeChat();
  late final cropper = FakeCropper(cropPath);
  late final controller = AssistController(
    bridge: bridge,
    api: chat,
    conversations: FakeConversations(),
    settings: settings,
    attachments: AttachmentsController(files: FakeFiles()),
    cropper: customCropper ?? cropper,
  );
  late final image = MemoryImage(shot);

  Widget app({required bool dark}) => AppScope(
    settings: settings,
    usage: UsageController(UsageApi('http://test')),
    api: chat,
    baseUrl: 'http://test',
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Stack(
        children: [
          Positioned.fill(
            child: Image(image: image, fit: BoxFit.fill),
          ),
          Positioned.fill(
            child: AssistOverlay(
              controller: controller,
              circleImage: (_) => image,
            ),
          ),
        ],
      ),
    ),
  );
}

ScreenContext _screen(String shot) => ScreenContext(
  text: 'Sneaker Shop\nAir Runner 90\n129.00',
  app: 'Shop',
  package: 'com.example.shop',
  screenshotPath: shot,
  structureArrived: true,
  // Screen pixels: the screen is 2x the overlay's logical size.
  screenSize: const Size(824, 1830),
  nodes: const [
    ScreenNode('Sneaker Shop', bounds: Rect.fromLTRB(40, 40, 400, 90)),
    ScreenNode('Air Runner 90', bounds: Rect.fromLTRB(40, 840, 400, 890)),
    ScreenNode('129.00', bounds: Rect.fromLTRB(40, 910, 200, 950)),
    ScreenNode('Add to bag', bounds: Rect.fromLTRB(40, 1400, 784, 1504)),
  ],
);

/// A loop around the shoe and its name (overlay coordinates).
const _loop = [
  Offset(200, 190),
  Offset(300, 200),
  Offset(360, 290),
  Offset(340, 400),
  Offset(250, 480),
  Offset(120, 470),
  Offset(40, 390),
  Offset(50, 260),
  Offset(120, 195),
  Offset(210, 188),
];

void main() {
  late SettingsController settings;
  late String shotPath, cropPath;
  late Uint8List shot;
  final auth = AuthController.instance;

  setUpAll(() async {
    await _fonts();
    Haptics.enabled = false;
    shot = _shopScreenshot();
    final dir = Directory.systemTemp.createTempSync('circle');
    shotPath = '${dir.path}/screen.jpg';
    cropPath = '${dir.path}/circle-1.jpg';
    File(shotPath).writeAsBytesSync(shot);
    File(cropPath).writeAsBytesSync(shot);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsController.load();
    auth.status = AuthStatus.signedIn;
    ActionCard.resetOutcomes();
    DeviceActionRunner.debugSupported = true;
  });

  tearDown(() {
    auth.status = AuthStatus.restoring;
    DeviceActionRunner.debugSupported = null;
    DeviceActionRunner.instance = ChannelDeviceActionRunner();
  });

  Future<_Harness> open(
    WidgetTester tester, {
    required bool dark,
    CircleCropper? cropper,
  }) async {
    _phone(tester);
    final h = _Harness(settings, shot, cropPath, cropper);
    h.bridge.screen = _screen(shotPath);
    h.controller.reset(
      const AssistShow(source: AssistSource.session, screen: true),
    );
    await tester.pumpWidget(h.app(dark: dark));
    await tester.runAsync(
      () => precacheImage(h.image, tester.element(find.byType(AssistOverlay))),
    );
    await tester.pump();
    return h;
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('circle: drawing on the frozen screen ($theme)', (
      tester,
    ) async {
      final h = await open(tester, dark: dark);
      await tester.tap(find.text(CircleStrings.chip));
      await _settle(tester);
      expect(h.controller.circle, CirclePhase.selecting);
      expect(find.text(CircleStrings.hint), findsOneWidget);
      final g = await tester.startGesture(_loop.first);
      for (final p in _loop.skip(1)) {
        await g.moveTo(p);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _golden(tester, 'goldens/assist_circle_drawing_$theme.png');
      await g.up();
      await _select(tester);
      expect(h.cropper.calls, hasLength(1));
      h.controller.stop();
    });

    testWidgets('circle: answer with quick chips ($theme)', (tester) async {
      final h = await open(tester, dark: dark);
      await h.controller.startCircle();
      await tester.pump();
      final g = await tester.startGesture(_loop.first);
      for (final p in _loop.skip(1)) {
        await g.moveTo(p);
      }
      await g.up();
      await _select(tester);
      expect(h.controller.circle, CirclePhase.results);
      h.chat.live!
        ..add(
          const DeltaEvent(
            'That looks like the **Air Runner 90**, a retro running shoe in '
            'red with a white sole. It sells for about **129.00** at most '
            'shops; the shop on screen has it in stock.',
          ),
        )
        ..add(const DoneEvent());
      await _settle(tester);
      for (final chip in [
        CircleStrings.search,
        CircleStrings.explain,
        CircleStrings.translate,
      ]) {
        expect(find.text(chip), findsOneWidget);
      }
      await _golden(tester, 'goldens/assist_circle_result_$theme.png');
    });

    testWidgets('action card in an answer ($theme)', (tester) async {
      _phone(tester);
      final h = _Harness(settings, shot, cropPath);
      h.controller.reset(const AssistShow(source: AssistSource.session));
      await tester.pumpWidget(h.app(dark: dark));
      await tester.runAsync(
        () =>
            precacheImage(h.image, tester.element(find.byType(AssistOverlay))),
      );
      await tester.enterText(find.byType(TextField), 'Dentist tomorrow at 3');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      h.chat.live!
        ..add(
          const DeltaEvent(
            'Here is the appointment. Check it and tap Confirm.\n\n'
            '```sparky-action\n'
            '{"type":"event","title":"Dentist","start":"2026-10-14T15:00",'
            '"end":"2026-10-14T15:30","location":"Smile Clinic, High St",'
            '"notes":"Bring the insurance card"}\n'
            '```',
          ),
        )
        ..add(const DoneEvent());
      await _settle(tester);
      expect(find.text(DeviceActionStrings.confirm), findsOneWidget);
      await _golden(tester, 'goldens/assist_action_card_$theme.png');
    });
  }

  testWidgets('circle sends the cut-out, the selection text, web on', (
    tester,
  ) async {
    final h = await open(tester, dark: false);
    await h.controller.startCircle();
    await h.controller.circleSelect(
      const Rect.fromLTRB(10, 400, 300, 480),
      const Size(412, 915),
    );
    await tester.pump();
    await _settle(tester);
    final req = h.chat.requests.single;
    expect(req.history.last.content, CircleStrings.searchPrompt);
    expect(req.history.last.attachments.single.name, CircleConfig.cropName);
    expect(req.screen![AssistWire.text], 'Air Runner 90\n129.00');
    // The server is told the picture is the crop, not the whole screen.
    expect(req.screen![AssistWire.selection], true);
    expect(h.chat.flags.single.web, WebMode.on);
    h.chat.live!
      ..add(const DeltaEvent('A shoe.'))
      ..add(const DoneEvent());
    await _settle(tester);
    // Explain reuses the uploaded cut-out.
    await tester.tap(find.text(CircleStrings.explain));
    await _settle(tester);
    expect(h.chat.requests, hasLength(2));
    expect(
      h.chat.requests.last.history.last.attachments.single.name,
      CircleConfig.cropName,
    );
    expect(
      h.chat.requests.last.history.last.content,
      CircleStrings.explainPrompt,
    );
    h.controller.stop();
  });

  testWidgets('every quick action sends the current selection crop', (
    tester,
  ) async {
    final h = await open(tester, dark: false);
    await h.controller.startCircle();
    await h.controller.circleSelect(
      const Rect.fromLTRB(10, 400, 300, 480),
      const Size(412, 915),
    );
    await _settle(tester);
    h.chat.live!
      ..add(const DeltaEvent('A shoe.'))
      ..add(const DoneEvent());
    await _settle(tester);
    await tester.tap(find.text(CircleStrings.translate));
    await _settle(tester);
    final last = h.chat.requests.last;
    expect(last.history.last.content, contains('Translate the text'));
    expect(last.history.last.attachments.single.name, CircleConfig.cropName);
    expect(last.screen![AssistWire.selection], true);
    expect(last.screen![AssistWire.text], 'Air Runner 90\n129.00');
    h.controller.stop();
  });

  testWidgets(
    'a blank capture shows a placeholder and never reaches the model',
    (tester) async {
      final h = await open(
        tester,
        dark: false,
        cropper: BlankCropper(cropPath),
      );
      await h.controller.startCircle();
      await h.controller.circleSelect(
        const Rect.fromLTRB(10, 600, 300, 700),
        const Size(412, 915),
      );
      await _settle(tester);
      expect(h.controller.circleBlank, true);
      expect(h.chat.requests, isEmpty);
      expect(find.text(CircleStrings.blankCaptureNote), findsWidgets);
      expect(find.text(CircleStrings.blankAnswer), findsOneWidget);
      // A quick action says so again instead of inventing a translation.
      await tester.tap(find.text(CircleStrings.translate));
      await _settle(tester);
      expect(h.chat.requests, isEmpty);
    },
  );

  testWidgets('a blank capture with text asks about the text only', (
    tester,
  ) async {
    final h = await open(tester, dark: false, cropper: BlankCropper(cropPath));
    await h.controller.startCircle();
    await h.controller.circleSelect(
      const Rect.fromLTRB(10, 400, 300, 480),
      const Size(412, 915),
    );
    await _settle(tester);
    await tester.tap(find.text(CircleStrings.explain));
    await _settle(tester);
    final q = h.chat.requests.last.history.last;
    expect(q.attachments, isEmpty);
    expect(q.content, contains('Air Runner 90'));
    expect(q.content, contains(CircleStrings.explainPrompt));
    h.controller.stop();
  });

  testWidgets('chip row starts fully visible and the thumbnail is clean', (
    tester,
  ) async {
    final h = await open(tester, dark: false);
    await h.controller.startCircle();
    await h.controller.circleSelect(
      const Rect.fromLTRB(10, 400, 300, 480),
      const Size(412, 915),
    );
    await _settle(tester);
    final chip = tester.getTopLeft(find.text(CircleStrings.search));
    expect(chip.dx, greaterThanOrEqualTo(AssistSizes.sheetPadding));
    expect(find.byType(Image), findsWidgets);
    h.controller.stop();
  });

  test('a black picture counts as blank, a real one does not', () async {
    final dir = Directory.systemTemp.createTempSync('blank');
    final black = File('${dir.path}/black.jpg')
      ..writeAsBytesSync(
        img.encodeJpg(img.Image(width: 80, height: 80), quality: 80),
      );
    expect(await isBlankImage(black.path), true);
    final real = File('${dir.path}/real.jpg')
      ..writeAsBytesSync(
        img.encodeJpg(
          img.fill(
            img.Image(width: 80, height: 80),
            color: img.ColorRgb8(200, 30, 30),
          ),
          quality: 80,
        ),
      );
    expect(await isBlankImage(real.path), false);
  });

  // The real-phone bug: circled album art, then "Open on youtube music".
  const songSources = [
    Citation(
      id: 'W1',
      title: 'I Met Her Again - Maan Panu - YouTube',
      url: 'https://www.youtube.com/watch?v=abcDEF12345',
      site: 'youtube.com',
    ),
    Citation(
      id: 'W2',
      title: 'I Met Her Again - Apple Music',
      url: 'https://music.apple.com/in/album/i-met-her-again/1234567',
      site: 'music.apple.com',
    ),
    Citation(
      id: 'W3',
      title: 'I Met Her Again - Gaana',
      url: 'https://gaana.com/song/i-met-her-again',
      site: 'gaana.com',
    ),
  ];
  const songAnswer =
      'This is the cover of **I Met Her Again** by **Maan Panu**, a Punjabi '
      'song released in India [W1]. You can stream it on YouTube, Apple '
      'Music and Gaana [W2][W3].';
  const openBlock =
      'Ready to open in YouTube Music.\n\n'
      '```sparky-action\n'
      '{"type":"url","url":"https://music.youtube.com/watch?v=abcDEF12345",'
      '"app":"YouTube Music","package":"com.google.android.apps.youtube.music"}\n'
      '```';

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('follow-up sends no selection; open card + chips ($theme)', (
      tester,
    ) async {
      final runner = FakeRunner(ActionOutcome.done, {
        MediaApps.youtubeMusic.package,
        MediaApps.youtube.package,
      });
      DeviceActionRunner.instance = runner;
      final h = await open(tester, dark: dark);
      await h.controller.startCircle();
      await h.controller.circleSelect(
        const Rect.fromLTRB(10, 400, 300, 480),
        const Size(412, 915),
      );
      await _settle(tester);
      h.chat.live!
        ..add(const SourcesEvent(songSources))
        ..add(const DeltaEvent(songAnswer))
        ..add(const DoneEvent());
      await _settle(tester);
      expect(find.text(MediaAppStrings.openIn('YouTube')), findsOneWidget);
      // Installed apps first, at most two chips.
      expect(
        find.text(MediaAppStrings.inBrowser('Apple Music')),
        findsOneWidget,
      );
      expect(find.text(MediaAppStrings.inBrowser('Gaana')), findsNothing);

      await tester.enterText(find.byType(TextField), 'Open on youtube music');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(h.chat.requests, hasLength(2));
      final follow = h.chat.requests.last;
      expect(follow.history.last.content, 'Open on youtube music');
      // History only: the cut-out and its screen text went with the first ask.
      expect(follow.history.last.attachments, isEmpty);
      expect(follow.screen, isNull);
      expect(
        follow.history.first.attachments.single.name,
        CircleConfig.cropName,
      );

      h.chat.live!
        ..add(const DeltaEvent(openBlock))
        ..add(const DoneEvent());
      await _settle(tester);
      expect(
        find.text(MediaAppStrings.openIn('YouTube Music')),
        findsOneWidget,
      );
      await _golden(tester, 'goldens/assist_open_in_app_$theme.png');
      await tester.tap(find.text(MediaAppStrings.openIn('YouTube Music')));
      await tester.pump();
      final run = runner.runs.last;
      expect(run.type, DeviceActionType.url);
      expect(
        run[DeviceActionWire.package],
        'com.google.android.apps.youtube.music',
      );
    });
  }

  testWidgets('"Ask…" sends the cut-out with the next question', (
    tester,
  ) async {
    final h = await open(tester, dark: false);
    await h.controller.startCircle();
    await h.controller.circleSelect(
      const Rect.fromLTRB(10, 400, 300, 480),
      const Size(412, 915),
    );
    await _settle(tester);
    h.chat.live!
      ..add(const DeltaEvent('A shoe.'))
      ..add(const DoneEvent());
    await _settle(tester);
    await h.controller.circleQuick(CircleQuick.ask);
    await h.controller.send('Is it waterproof?');
    await _settle(tester);
    final req = h.chat.requests.last;
    expect(req.history.last.attachments.single.name, CircleConfig.cropName);
    expect(req.screen, isNotNull);
    h.controller.stop();
  });

  testWidgets('no screenshot: the hint to turn on "Use screenshot"', (
    tester,
  ) async {
    final h = await open(tester, dark: false);
    h.bridge.screen = const ScreenContext(
      text: 'Only text',
      structureArrived: true,
    );
    await h.controller.startCircle();
    await tester.pump();
    expect(h.controller.circle, CirclePhase.off);
    expect(find.text(CircleStrings.needsScreenshot), findsOneWidget);
    expect(find.text(AssistStrings.screenSettings), findsOneWidget);
  });

  testWidgets('long-press on the pill starts circle mode', (tester) async {
    final h = await open(tester, dark: false);
    // The field keeps its own long-press (text selection); the rest of the
    // pill starts circle mode.
    await tester.longPress(find.bySemanticsLabel(AssistStrings.attach));
    await _settle(tester);
    expect(h.controller.circle, CirclePhase.selecting);
    expect(find.byType(CircleView), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(CircleStrings.cancel));
    await tester.pump();
    expect(h.controller.circle, CirclePhase.off);
  });

  testWidgets('shortcut without a session explains instead', (tester) async {
    _phone(tester);
    final h = _Harness(settings, shot, cropPath);
    h.controller.reset(
      const AssistShow(source: AssistSource.shortcut, circle: true),
    );
    await tester.pumpWidget(h.app(dark: false));
    await tester.pump();
    expect(find.text(CircleStrings.needsSession), findsOneWidget);
    expect(find.text(CircleStrings.chip), findsNothing);
  });

  testWidgets('shared text and files land in the pill', (tester) async {
    _phone(tester);
    final h = _Harness(settings, shot, cropPath);
    h.controller.reset(const AssistShow(source: AssistSource.share));
    await tester.pumpWidget(h.app(dark: false));
    // The app wires the stream; here the test hands it over like assistMain.
    h.controller.receiveShared(
      SharedPayload(
        text: 'https://example.com/article',
        subject: 'A good read',
        files: [SharedFile(path: shotPath, name: 'photo.png')],
      ),
    );
    await _settle(tester);
    expect(h.controller.attachments.items.single.name, 'photo.png');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'A good read\nhttps://example.com/article');
  });

  group('action card', () {
    Widget card(
      String source, {
      DeviceActionRunner? runner,
      bool dark = false,
    }) => AppScope(
      settings: settings,
      usage: UsageController(UsageApi('http://test')),
      api: FakeChat(),
      baseUrl: 'http://test',
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: ActionCard(source: source, runner: runner),
        ),
      ),
    );

    const alarm = '{"type":"alarm","time":"07:30","label":"Gym"}';

    testWidgets('Confirm runs it once through the bridge', (tester) async {
      final runner = FakeRunner();
      await tester.pumpWidget(card(alarm, runner: runner));
      expect(
        find.text(DeviceActionStrings.alarmTitle('07:30')),
        findsOneWidget,
      );
      await tester.tap(find.text(DeviceActionStrings.confirm));
      await tester.pump();
      expect(runner.runs.single.toChannel()['hour'], 7);
      expect(find.text(DeviceActionStrings.alarmDone), findsOneWidget);
      expect(find.text(DeviceActionStrings.confirm), findsNothing);
      // Rebuilt (scrolled away and back): still done, not offered again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(card(alarm, runner: runner));
      expect(find.text(DeviceActionStrings.alarmDone), findsOneWidget);
      expect(runner.runs, hasLength(1));
    });

    testWidgets('Cancel never touches the bridge', (tester) async {
      final runner = FakeRunner();
      await tester.pumpWidget(card(alarm, runner: runner));
      await tester.tap(find.text(DeviceActionStrings.cancel));
      await tester.pump();
      expect(runner.runs, isEmpty);
      expect(find.text(DeviceActionStrings.cancelled), findsOneWidget);
    });

    testWidgets('a failure says why', (tester) async {
      await tester.pumpWidget(
        card(
          '{"type":"app","name":"Nowhere"}',
          runner: FakeRunner(ActionOutcome.notFound),
        ),
      );
      await tester.tap(find.text(DeviceActionStrings.confirm));
      await tester.pump();
      expect(find.text(DeviceActionStrings.notFound), findsOneWidget);
    });

    testWidgets('actions off in Settings: no Confirm', (tester) async {
      settings.setAssistActions(false);
      final runner = FakeRunner();
      await tester.pumpWidget(card(alarm, runner: runner));
      expect(find.text(DeviceActionStrings.confirm), findsNothing);
      expect(find.text(DeviceActionStrings.off), findsOneWidget);
    });

    testWidgets('an unreadable block shows as code', (tester) async {
      await tester.pumpWidget(card('{"type":"teleport"}'));
      expect(find.text(DeviceActionStrings.confirm), findsNothing);
    });
  });

  group('circle: strokes, cancels and failures', () {
    /// One finger stroke through [points], lifted at the end.
    Future<void> stroke(WidgetTester tester, List<Offset> points) async {
      final g = await tester.startGesture(points.first);
      for (final p in points.skip(1)) {
        await g.moveTo(p);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump();
    }

    // The phone's three adb swipes, in overlay coordinates.
    const s1 = [Offset(269, 519), Offset(330, 560), Offset(400, 615)];
    const s2 = [Offset(400, 615), Offset(380, 660), Offset(365, 704)];
    const s3 = [Offset(365, 704), Offset(310, 660), Offset(262, 615)];
    const gap = Duration(milliseconds: 300);

    testWidgets('three quick strokes become one selection, then a search', (
      tester,
    ) async {
      final h = await open(tester, dark: false);
      await h.controller.startCircle();
      await tester.pump();
      await stroke(tester, s1);
      await tester.pump(gap);
      await stroke(tester, s2);
      await tester.pump(gap);
      await stroke(tester, s3);
      await tester.pump(gap);
      // Still within the pause: nothing cut out yet, all strokes kept.
      expect(h.cropper.calls, isEmpty);
      expect(h.controller.circle, CirclePhase.selecting);
      await _select(tester);
      expect(h.cropper.calls, hasLength(1));
      final sel = h.cropper.calls.single.$1;
      // The union of all three strokes.
      expect(sel, const Rect.fromLTRB(262, 519, 400, 704));
      expect(h.controller.circle, CirclePhase.results);
      expect(h.chat.requests, hasLength(1));
      expect(find.text(CircleStrings.reading), findsNothing);
      h.controller.stop();
    });

    testWidgets('a stroke while cutting out cancels it and selects anew', (
      tester,
    ) async {
      final gated = GatedCropper();
      final h = await open(tester, dark: false, cropper: gated);
      await h.controller.startCircle();
      await tester.pump();
      await stroke(tester, _loop);
      await _select(tester);
      expect(h.controller.circle, CirclePhase.cropping);
      expect(find.text(CircleStrings.reading), findsOneWidget);
      // Drawing again drops the running cut-out at once.
      await stroke(tester, s1);
      expect(h.controller.circle, CirclePhase.selecting);
      expect(find.text(CircleStrings.reading), findsNothing);
      await _select(tester);
      expect(gated.calls, hasLength(2));
      expect(h.controller.circle, CirclePhase.cropping);
      // The old cut-out finishing late changes nothing.
      gated.gates.first.complete(cropPath);
      await tester.pump();
      expect(h.controller.circle, CirclePhase.cropping);
      expect(h.chat.requests, isEmpty);
      gated.gates.last.complete(cropPath);
      await _select(tester);
      expect(h.controller.circle, CirclePhase.results);
      expect(
        h.controller.circleSelection,
        padToMin(
          const Rect.fromLTRB(269, 519, 400, 615),
          view: const Size(412, 915),
        ),
      );
      expect(h.chat.requests, hasLength(1));
      h.controller.stop();
    });

    testWidgets('drawing again after an answer re-selects and re-asks', (
      tester,
    ) async {
      final h = await open(tester, dark: false);
      await h.controller.startCircle();
      await tester.pump();
      await stroke(tester, _loop);
      await _select(tester);
      expect(h.controller.circle, CirclePhase.results);
      expect(h.controller.sending, isTrue);
      await stroke(tester, const [
        Offset(60, 120),
        Offset(200, 140),
        Offset(300, 200),
      ]);
      await _select(tester);
      expect(h.cropper.calls, hasLength(2));
      expect(h.controller.circle, CirclePhase.results);
      expect(h.chat.requests, hasLength(2));
      h.controller.stop();
    });

    testWidgets('a failed cut-out offers a retry, not a spinner', (
      tester,
    ) async {
      final failing = ThrowingCropper();
      final h = await open(tester, dark: false, cropper: failing);
      await h.controller.startCircle();
      await tester.pump();
      await stroke(tester, _loop);
      await _select(tester);
      expect(failing.calls, 1);
      expect(h.controller.circle, CirclePhase.selecting);
      expect(find.text(CircleStrings.cropFailed), findsOneWidget);
      expect(find.text(CircleStrings.reading), findsNothing);
      expect(h.chat.requests, isEmpty);
      // Trying again is possible right away.
      await stroke(tester, s1);
      await _select(tester);
      expect(failing.calls, 2);
    });

    testWidgets('a cut-out that never finishes times out with a retry', (
      tester,
    ) async {
      final gated = GatedCropper();
      final h = await open(tester, dark: false, cropper: gated);
      await h.controller.startCircle();
      await tester.pump();
      await stroke(tester, _loop);
      await _select(tester);
      expect(h.controller.circle, CirclePhase.cropping);
      await tester.pump(CircleConfig.cropTimeout);
      await tester.pump();
      expect(h.controller.circle, CirclePhase.selecting);
      expect(find.text(CircleStrings.cropFailed), findsOneWidget);
      expect(find.text(CircleStrings.reading), findsNothing);
      // Finishing after the deadline is ignored.
      gated.gates.single.complete(cropPath);
      await tester.pump();
      expect(h.controller.circle, CirclePhase.selecting);
      expect(h.chat.requests, isEmpty);
    });

    testWidgets('back while cutting out leaves circle mode', (tester) async {
      final gated = GatedCropper();
      final h = await open(tester, dark: false, cropper: gated);
      await h.controller.startCircle();
      await tester.pump();
      await stroke(tester, _loop);
      await _select(tester);
      expect(h.controller.circle, CirclePhase.cropping);
      await tester.tap(find.bySemanticsLabel(CircleStrings.cancel));
      await tester.pump();
      expect(h.controller.circle, CirclePhase.off);
      gated.gates.single.complete(cropPath);
      await tester.pump();
      expect(h.controller.circle, CirclePhase.off);
    });
  });
}
