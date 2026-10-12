import 'dart:async';

import 'package:app/assist/assist_bridge.dart';
import 'package:app/assist/assist_controller.dart';
import 'package:app/assist/assist_overlay.dart';
import 'package:app/assist/screen_text.dart';
import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/assist.dart';
import 'package:app/core/constants/smart_toggles.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/conversation.dart';
import 'package:app/data/conversations_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/chat/voice/voice_controller.dart';
import 'package:app/features/chat/voice/voice_engine.dart';
import 'package:app/features/chat/voice/voice_permission.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---- fakes -----------------------------------------------------------------

class FakeBridge implements AssistBridge {
  final _shows = StreamController<AssistShow>.broadcast();
  ScreenContext? screen;
  int closed = 0, shownCalls = 0, settingsOpened = 0;
  final opened = <String?>[];

  @override
  Stream<AssistShow> get shows => _shows.stream;
  @override
  Future<AssistShow?> ready() async => null;
  @override
  Future<void> shown() async => shownCalls++;
  @override
  Future<void> close() async => closed++;
  @override
  Future<ScreenContext?> screenContext() async => screen;
  @override
  Future<bool> openApp([String? link]) async {
    opened.add(link);
    return true;
  }

  @override
  Future<void> assistantSettings() async => settingsOpened++;
}

class FakeChat extends ChatApi {
  final requests =
      <({List<ChatMessage> history, Map<String, Object>? screen})>[];
  StreamController<ChatEvent>? live;

  @override
  Stream<ChatEvent> streamChat(
    http.Client client,
    List<ChatMessage> history, {
    String? modelId,
    WebMode webMode = WebMode.auto,
    required bool knowledge,
    required String mode,
    Map<String, String> profile = const {},
    String? context,
    bool roundTable = false,
    String? conversationId,
    bool smartSuggestions = true,
    Set<SuggestKind> suppressSuggest = const {},
    List<Map<String, String>> apps = const [],
    Map<String, Object>? screen,
  }) {
    requests.add((history: List.of(history), screen: screen));
    live = StreamController<ChatEvent>();
    return live!.stream;
  }
}

class FakeConversations extends ConversationsApi {
  FakeConversations() : super('http://test');
  final saved = <String, List<ChatMessage>>{};

  @override
  Future<ConversationSummary> save(
    String id,
    List<ChatMessage> messages,
  ) async {
    saved[id] = List.of(messages);
    return ConversationSummary.fromJson({
      'id': id,
      'title': 'Flight',
      'createdAt': '2026-10-13T10:00:00Z',
      'updatedAt': '2026-10-13T10:00:00Z',
    });
  }
}

class _Engine implements VoiceEngine {
  @override
  String get id => 'device';
  @override
  bool get batch => false;
  @override
  Future<bool> available() async => true;
  @override
  Future<void> start(String locale, VoiceListener listener) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  void dispose() {}
}

class _Granted implements VoicePermission {
  @override
  Future<VoicePermissionState> check() async => VoicePermissionState.granted;
  @override
  Future<VoicePermissionState> request() async => VoicePermissionState.granted;
  @override
  Future<void> openSettings() async {}
}

// ---- harness ---------------------------------------------------------------

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

/// Golden with real soft shadows (tests draw them as solid bands by default).
Future<void> _golden(WidgetTester tester, String file) async {
  debugDisableShadows = false;
  try {
    for (final e in find.byType(DecoratedBox).evaluate()) {
      e.renderObject?.markNeedsPaint();
    }
    for (final e in find.byType(Container).evaluate()) {
      e.renderObject?.markNeedsPaint();
    }
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
  } finally {
    debugDisableShadows = true;
  }
}

/// A plausible app behind the overlay (a travel email), so the goldens show
/// the scrim and cards over real content.
class _BehindApp extends StatelessWidget {
  const _BehindApp();

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1F1F1F);
    const muted = Color(0xFF5F6368);
    Widget line(double w, {Color c = const Color(0xFFE3E3E3)}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 10,
      width: w,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(5),
      ),
    );
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'SpaceGrotesk', color: ink),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your flight to Lisbon',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'TAP Air Portugal · Booking ref K7Q2LM',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TP 1351  ·  Fri 24 Oct',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 6),
                    Text('LHR 06:45  →  LIS 09:25'),
                    SizedBox(height: 6),
                    Text('Terminal 2 · Gate closes 06:25'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              line(320),
              line(280),
              line(300),
              line(180),
              const SizedBox(height: 16),
              line(300),
              line(260),
              line(310),
              line(120),
            ],
          ),
        ),
      ),
    );
  }
}

class _Harness {
  _Harness(this.settings);

  final SettingsController settings;
  final bridge = FakeBridge();
  final chat = FakeChat();
  final conversations = FakeConversations();
  late final controller = AssistController(
    bridge: bridge,
    api: chat,
    conversations: conversations,
    settings: settings,
  );
  final voice = VoiceController(onDevice: _Engine(), permission: _Granted());

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
          const Positioned.fill(child: _BehindApp()),
          Positioned.fill(
            child: AssistOverlay(controller: controller, voice: voice),
          ),
        ],
      ),
    ),
  );
}

const _screen = ScreenContext(
  text: 'Your flight to Lisbon\nTP 1351 · Fri 24 Oct\nLHR 06:45 → LIS 09:25',
  app: 'Gmail',
  package: 'com.google.android.gm',
  structureArrived: true,
);

const _answer =
    'Your flight **TP 1351** leaves London Heathrow at **06:45** on '
    'Friday 24 October and lands in Lisbon at 09:25.\n\n'
    '- Terminal 2, the gate closes at 06:25\n'
    '- Booking reference: `K7Q2LM`\n\n'
    'Plan to reach the airport by about 04:45.';

void main() {
  late SettingsController settings;
  final auth = AuthController.instance;

  setUpAll(() async {
    await _fonts();
    Haptics.enabled = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsController.load();
    Haptics.enabled = false;
    auth.status = AuthStatus.signedIn;
  });

  tearDown(() => auth.status = AuthStatus.restoring);

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('idle pill with the screen chip ($theme)', (tester) async {
      _phone(tester);
      final h = _Harness(settings);
      h.controller.reset(
        const AssistShow(source: AssistSource.session, screen: true),
      );
      await tester.pumpWidget(h.app(dark: dark));
      await tester.pump();
      expect(find.text(AssistStrings.askHint), findsOneWidget);
      expect(find.text(AssistStrings.shareScreen), findsOneWidget);
      await _golden(tester, 'goldens/assist_idle_$theme.png');
    });

    testWidgets('typing with the screen shared ($theme)', (tester) async {
      _phone(tester);
      final h = _Harness(settings);
      h.bridge.screen = _screen;
      h.controller.reset(
        const AssistShow(source: AssistSource.session, screen: true),
      );
      await tester.pumpWidget(h.app(dark: dark));
      await tester.tap(find.text(AssistStrings.shareScreen));
      await tester.pump();
      await tester.pump();
      expect(find.text(AssistStrings.screenSharedFrom('Gmail')), findsOne);
      // Text only (no screenshot): a hint explains how to add one.
      expect(find.text(AssistStrings.screenTextOnly), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'When do I need to leave?',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _golden(tester, 'goldens/assist_typing_$theme.png');
    });

    testWidgets('answer streaming ($theme)', (tester) async {
      _phone(tester);
      final h = _Harness(settings);
      h.bridge.screen = _screen;
      h.controller.reset(
        const AssistShow(source: AssistSource.session, screen: true),
      );
      await tester.pumpWidget(h.app(dark: dark));
      await tester.tap(find.text(AssistStrings.shareScreen));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'When do I need to leave?',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      h.chat.live!.add(const DeltaEvent('Your flight **TP 1351** leaves '));
      h.chat.live!.add(const DeltaEvent('London Heathrow at **06:45** on'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('When do I need to leave?'), findsOneWidget);
      await _golden(tester, 'goldens/assist_streaming_$theme.png');
      h.controller.stop();
    });

    testWidgets('answer done, expanded ($theme)', (tester) async {
      _phone(tester);
      final h = _Harness(settings);
      h.controller.reset(
        const AssistShow(source: AssistSource.session, screen: true),
      );
      await tester.pumpWidget(h.app(dark: dark));
      await tester.enterText(
        find.byType(TextField),
        'When do I need to leave?',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      h.chat.live!
        ..add(const DeltaEvent(_answer))
        ..add(const DoneEvent());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(AssistStrings.openInSparky), findsOneWidget);
      await _golden(tester, 'goldens/assist_answer_$theme.png');
    });

    testWidgets('backdrop: open wave mid-way ($theme)', (tester) async {
      _phone(tester);
      final h = _Harness(settings);
      h.controller.reset(const AssistShow(source: AssistSource.session));
      await tester.pumpWidget(h.app(dark: dark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await _golden(tester, 'goldens/assist_backdrop_wave_$theme.png');
    });

    testWidgets('backdrop: idle glow ($theme)', (tester) async {
      _phone(tester);
      final h = _Harness(settings);
      h.controller.reset(const AssistShow(source: AssistSource.session));
      await tester.pumpWidget(h.app(dark: dark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2400));
      await _golden(tester, 'goldens/assist_backdrop_idle_$theme.png');
    });

    testWidgets('backdrop: thinking shimmer ($theme)', (tester) async {
      _phone(tester);
      final h = _Harness(settings);
      h.controller.reset(const AssistShow(source: AssistSource.session));
      await tester.pumpWidget(h.app(dark: dark));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), 'What is on my plate?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Half way through a shimmer pass (t = 2.25 s).
      await tester.pump(const Duration(milliseconds: 750));
      await _golden(tester, 'goldens/assist_backdrop_thinking_$theme.png');
      h.controller.stop();
    });

    testWidgets('signed out ($theme)', (tester) async {
      _phone(tester);
      auth.status = AuthStatus.signedOut;
      final h = _Harness(settings);
      h.controller.reset(const AssistShow(source: AssistSource.session));
      await tester.pumpWidget(h.app(dark: dark));
      await tester.pump();
      expect(find.text(AssistStrings.signInTitle), findsOneWidget);
      expect(find.text(AssistStrings.askHint), findsNothing);
      await _golden(tester, 'goldens/assist_signed_out_$theme.png');
    });
  }

  testWidgets('screen goes out only after the tap, with the question', (
    tester,
  ) async {
    _phone(tester);
    final h = _Harness(settings);
    h.bridge.screen = _screen;
    h.controller.reset(
      const AssistShow(source: AssistSource.session, screen: true),
    );
    await tester.pumpWidget(h.app(dark: false));

    // Without the tap: no screen in the request.
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(h.chat.requests.single.screen, isNull);
    h.chat.live!
      ..add(const DeltaEvent('Hello!'))
      ..add(const DoneEvent());
    await tester.pump();

    // New opening, tap to share, ask: the screen travels with it.
    h.controller.reset(
      const AssistShow(source: AssistSource.session, screen: true),
    );
    await tester.pump();
    await tester.tap(find.text(AssistStrings.shareScreen));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'what is this?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(h.chat.requests.last.screen, {
      'text': _screen.text,
      'app': 'Gmail',
      'package': 'com.google.android.gm',
    });
    expect(h.chat.requests.last.history.single.content, 'what is this?');
    h.controller.stop();
  });

  testWidgets('no session: no screen chip', (tester) async {
    _phone(tester);
    final h = _Harness(settings);
    h.controller.reset(const AssistShow(source: AssistSource.tryIt));
    await tester.pumpWidget(h.app(dark: false));
    expect(find.text(AssistStrings.shareScreen), findsNothing);
  });

  testWidgets('nothing readable: hint with a settings link', (tester) async {
    _phone(tester);
    final h = _Harness(settings);
    h.bridge.screen = null;
    h.controller.reset(
      const AssistShow(source: AssistSource.session, screen: true),
    );
    await tester.pumpWidget(h.app(dark: false));
    await tester.tap(find.text(AssistStrings.shareScreen));
    await tester.pump();
    expect(find.text(AssistStrings.screenNothing), findsOneWidget);
    await tester.tap(find.text(AssistStrings.screenSettings));
    expect(h.bridge.settingsOpened, 1);
  });

  testWidgets('Open in sparky saves the chat and opens it in the app', (
    tester,
  ) async {
    _phone(tester);
    final h = _Harness(settings);
    h.controller.reset(const AssistShow(source: AssistSource.session));
    await tester.pumpWidget(h.app(dark: false));
    await tester.enterText(find.byType(TextField), 'When do I leave?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    h.chat.live!
      ..add(const DeltaEvent('At 04:45.'))
      ..add(const DoneEvent());
    await tester.pump();
    await tester.tap(find.text(AssistStrings.openInSparky));
    await tester.pump();
    final id = h.controller.conversationId!;
    expect(h.conversations.saved[id]!.map((m) => m.content), [
      'When do I leave?',
      'At 04:45.',
    ]);
    expect(h.bridge.opened.single, 'sparky://chat/$id');
  });

  testWidgets('tapping outside closes; signed out opens the app', (
    tester,
  ) async {
    _phone(tester);
    final h = _Harness(settings);
    h.controller.reset(const AssistShow(source: AssistSource.session));
    await tester.pumpWidget(h.app(dark: false));
    await tester.tapAt(const Offset(200, 120));
    expect(h.bridge.closed, 1);

    auth.status = AuthStatus.signedOut;
    auth.notifyListeners();
    await tester.pump();
    await tester.tap(find.text(AssistStrings.signInAction));
    await tester.pump();
    expect(h.bridge.opened.single, isNull);
  });
}
