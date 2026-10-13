import 'package:app/core/constants/voice.dart';
import 'package:app/core/constants/voice_fix.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/transcript_fix_api.dart';
import 'package:app/features/chat/voice/transcript_fixer.dart';
import 'package:app/features/chat/voice/voice_controller.dart';
import 'package:app/features/chat/voice/voice_engine.dart';
import 'package:app/features/chat/voice/voice_fix_field.dart';
import 'package:app/features/chat/voice/voice_permission.dart';
import 'package:app/features/chat/widgets/chat_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';

final _composer = GlobalKey();

class _Engine implements VoiceEngine {
  VoiceListener? listener;
  String? finalOnStop;
  double? confidence;

  @override
  String get id => 'device';
  @override
  bool get batch => false;
  @override
  Future<bool> available() async => true;
  @override
  Future<void> start(String locale, VoiceListener listener) async =>
      this.listener = listener;
  @override
  Future<void> stop() async {
    final t = finalOnStop;
    if (t != null) listener?.onFinal(t, confidence);
  }

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

/// Plays the server: a canned reply after [delay]; null is a timeout.
class _FakeApi extends TranscriptFixApi {
  _FakeApi({this.reply, this.delay = Duration.zero});
  ServerFix? reply;
  Duration delay;
  int calls = 0;
  List<VoiceTurn> context = const [];
  List<double> localMs = const [];
  String sent = '';

  @override
  Future<ServerFix?> fix({
    required String text,
    List<VoiceTurn> context = const [],
    String? language,
    bool exact = false,
    List<String> vocab = const [],
    bool confident = false,
    List<double> localMs = const [],
    Duration timeout = VoiceFixConfig.llmTimeout,
  }) async {
    calls++;
    sent = text;
    this.context = context;
    this.localMs = localMs;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return reply;
  }

  @override
  Future<List<String>> vocab() async => const ['Nikhil'];
}

VoiceController _make(
  _Engine engine,
  _FakeApi api, {
  bool enabled = true,
  List<VoiceTurn> Function()? context,
}) => VoiceController(
  onDevice: engine,
  permission: _Granted(),
  locale: () => 'en-IN',
  fixer: TranscriptFixer(
    api: api,
    enabled: () => enabled,
    exact: () => false,
    context: context,
  ),
);

void main() {
  group('controller', () {
    test('shows the local fix at once, then the model fix as final', () async {
      final engine = _Engine()..finalOnStop = 'um send a male to the team';
      final api = _FakeApi(
        reply: const ServerFix('Send a mail to the team.', 'llm'),
      );
      final c = _make(
        engine,
        api,
        context: () => [
          (role: 'user', content: 'one'),
          (role: 'assistant', content: 'two'),
          (role: 'user', content: 'three'),
        ],
      );
      final seen = <(String, bool)>[];
      await c.start((t, f) => seen.add((t, f)));
      await c.stop();
      expect(seen.first, ('Send a male to the team.', false));
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ('Send a mail to the team.', true));
      expect(api.sent, 'Send a male to the team.');
      expect(api.context.map((t) => t.content), ['two', 'three']);
      expect(c.lastFix!.source, 'llm');
      expect(c.lastFix!.raw, 'um send a male to the team');
      expect(c.lastFix!.edits, 2);
      expect(c.phase, VoicePhase.idle);
      c.dispose();
    });

    test('a timed-out model keeps the local text', () async {
      final engine = _Engine()..finalOnStop = 'check the data base logs today';
      final api = _FakeApi();
      final c = _make(engine, api);
      final seen = <(String, bool)>[];
      await c.start((t, f) => seen.add((t, f)));
      await c.stop();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ('Check the database logs today.', true));
      expect(c.lastFix!.source, 'local');
      expect(api.calls, 1);
      expect(api.localMs, hasLength(1));
      c.dispose();
    });

    test('short commands and confident results skip the model', () async {
      final engine = _Engine()..finalOnStop = 'open settings';
      final api = _FakeApi(reply: const ServerFix('x', 'llm'));
      final c = _make(engine, api);
      final seen = <(String, bool)>[];
      await c.start((t, f) => seen.add((t, f)));
      await c.stop();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ('Open settings', true));

      engine
        ..finalOnStop = 'turn on the lights'
        ..confidence = 0.99;
      await c.start((t, f) => seen.add((t, f)));
      await c.stop();
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ('Turn on the lights.', true));
      expect(api.calls, 0);
      c.dispose();
    });

    test('auto-fix off delivers exactly what was heard', () async {
      final engine = _Engine()..finalOnStop = 'um the the build is broken';
      final api = _FakeApi(reply: const ServerFix('x', 'llm'));
      final c = _make(engine, api, enabled: false);
      final seen = <(String, bool)>[];
      await c.start((t, f) => seen.add((t, f)));
      await c.stop();
      expect(seen, [('um the the build is broken', true)]);
      expect(c.lastFix, isNull);
      expect(api.calls, 0);
      c.dispose();
    });

    test('cancel while fixing drops the result', () async {
      final engine = _Engine()
        ..finalOnStop = 'please summarize the long thread';
      final api = _FakeApi(
        reply: const ServerFix('Please summarize the long thread.', 'llm'),
        delay: const Duration(milliseconds: 50),
      );
      final c = _make(engine, api);
      final seen = <(String, bool)>[];
      await c.start((t, f) => seen.add((t, f)));
      await c.stop();
      expect(c.fixing, isTrue);
      await c.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(seen.where((s) => s.$2), isEmpty);
      c.dispose();
    });
  });

  group('undo chip', () {
    Future<void> pump(
      WidgetTester tester,
      VoiceController voice, {
      ThemeData? theme,
      Size size = const Size(412, 915),
      double ratio = 1,
    }) async {
      tester.view.physicalSize = size * ratio;
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme ?? AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: RepaintBoundary(
                key: _composer,
                child: ChatInput(
                  onSend: (_, _) {},
                  onStop: () {},
                  isStreaming: false,
                  knowledge: false,
                  onToggleWebSearch: () {},
                  onToggleKnowledge: () {},
                  voice: voice,
                ),
              ),
            ),
          ),
        ),
      );
    }

    TextEditingController field(WidgetTester t) =>
        t.widget<TextField>(find.byType(TextField)).controller!;

    Future<void> dictate(WidgetTester tester, _Engine engine) async {
      await tester.tap(find.bySemanticsLabel(VoiceStrings.mic));
      await tester.pump();
      engine.listener!.onPartial('remind me to call nikil at five pm');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(VoiceStrings.finish));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shows the fix, highlights it and undoes it', (tester) async {
      final engine = _Engine()
        ..finalOnStop = 'um remind me to call nikil at five pm';
      final api = _FakeApi(
        reply: const ServerFix('Remind me to call Nikhil at 5 PM.', 'llm'),
        delay: const Duration(milliseconds: 10),
      );
      final c = _make(engine, api);
      await pump(tester, c);
      await dictate(tester, engine);

      expect(field(tester).text, 'Remind me to call Nikhil at 5 PM.');
      expect(find.text(VoiceFixStrings.undo), findsOneWidget);
      expect(find.text(VoiceFixStrings.fixed(3)), findsOneWidget);
      final ctl = field(tester) as VoiceFixTextController;
      final span = ctl.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        withComposing: false,
      );
      final marked = <String>[
        for (final s in span.children!.cast<TextSpan>())
          if (s.style?.backgroundColor != null) s.text!,
      ];
      expect(marked, ['Nikhil', '5']);

      await tester.tap(find.text(VoiceFixStrings.undo));
      await tester.pump();
      expect(field(tester).text, 'um remind me to call nikil at five pm');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(VoiceFixStrings.undo), findsNothing);
      c.dispose();
    });

    testWidgets('editing the text or time passing ends the offer', (
      tester,
    ) async {
      final engine = _Engine()
        ..finalOnStop = 'um remind me to call nikil at five pm';
      final c = _make(engine, _FakeApi());
      await pump(tester, c);
      await dictate(tester, engine);
      expect(find.text(VoiceFixStrings.undo), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'something else');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(VoiceFixStrings.undo), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await dictate(tester, engine);
      expect(find.text(VoiceFixStrings.undo), findsOneWidget);
      await tester.pump(VoiceFixConfig.undoFor);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(VoiceFixStrings.undo), findsNothing);
      c.dispose();
    });

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('golden ($name)', (tester) async {
        await tester.runAsync(loadAppFonts);
        final engine = _Engine()
          ..finalOnStop = 'um remind me to call nikil at five pm';
        final c = _make(
          engine,
          _FakeApi(
            reply: const ServerFix('Remind me to call Nikhil at 5 PM.', 'llm'),
          ),
        );
        await pump(tester, c, theme: theme, ratio: 2.6);
        await dictate(tester, engine);
        await tester.pump(const Duration(milliseconds: 100));
        await expectLater(
          find.byKey(_composer),
          matchesGoldenFile('goldens/voice_fix_$name.png'),
        );
        c.dispose();
      });
    }
  });
}
