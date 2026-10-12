import 'package:app/core/constants/voice.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/chat/voice/voice_controller.dart';
import 'package:app/features/chat/voice/voice_engine.dart';
import 'package:app/features/chat/voice/voice_locale.dart';
import 'package:app/features/chat/voice/voice_permission.dart';
import 'package:app/features/chat/widgets/chat_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted engine: the test plays the recognizer.
class FakeEngine implements VoiceEngine {
  FakeEngine(this.id, {this.batch = false, this.ready = true});

  @override
  final String id;
  @override
  final bool batch;
  bool ready;
  VoiceListener? listener;
  String? locale;
  int started = 0, stopped = 0, cancelled = 0;

  /// What [stop] reports, like a recognizer finishing.
  String? finalOnStop;

  @override
  Future<bool> available() async => ready;

  @override
  Future<void> start(String locale, VoiceListener listener) async {
    started++;
    this.locale = locale;
    this.listener = listener;
  }

  @override
  Future<void> stop() async {
    stopped++;
    final text = finalOnStop;
    if (text != null) listener?.onFinal(text);
  }

  @override
  Future<void> cancel() async => cancelled++;

  @override
  void dispose() {}
}

class FakePermission implements VoicePermission {
  FakePermission(this.state, {this.afterRequest});
  VoicePermissionState state;
  VoicePermissionState? afterRequest;
  int requests = 0, opened = 0;

  @override
  Future<VoicePermissionState> check() async => state;

  @override
  Future<VoicePermissionState> request() async {
    requests++;
    return state = afterRequest ?? state;
  }

  @override
  Future<void> openSettings() async => opened++;
}

VoiceController make(
  FakeEngine device, {
  FakeEngine? server,
  FakePermission? permission,
  bool accurate = false,
}) => VoiceController(
  onDevice: device,
  server: server,
  permission: permission ?? FakePermission(VoicePermissionState.granted),
  locale: () => 'en-IN',
  highAccuracy: () => accurate,
);

void main() {
  group('locale', () {
    test('follows the device unless a reply language is set', () {
      expect(voiceLocaleFor(language: '', device: 'en_IN'), 'en-IN');
      expect(voiceLocaleFor(language: 'Hindi', device: 'en-IN'), 'hi-IN');
      expect(voiceLocaleFor(language: 'hi-IN', device: 'en-US'), 'hi-IN');
      expect(voiceLocaleFor(language: 'English', device: 'en-GB'), 'en-GB');
      expect(voiceLocaleFor(language: 'Klingon', device: 'en-IN'), 'en-IN');
    });

    test('picks the recognizer locale: exact, same language, else null', () {
      const ids = ['en_US', 'en_IN', 'hi_IN', 'fr_FR'];
      expect(pickRecognizerLocale('en-IN', ids), 'en_IN');
      expect(pickRecognizerLocale('hi-IN', ids), 'hi_IN');
      expect(pickRecognizerLocale('en-GB', ids), 'en_US');
      expect(pickRecognizerLocale('ja-JP', ids), isNull);
    });
  });

  group('controller', () {
    test('streams partials and delivers the final text', () async {
      final device = FakeEngine('device')..finalOnStop = 'hello world';
      final c = make(device);
      final seen = <(String, bool)>[];
      await c.start((t, f) => seen.add((t, f)));
      expect(c.phase, VoicePhase.listening);
      expect(device.locale, 'en-IN');
      device.listener!.onPartial('hello');
      device.listener!.onLevel(0.8);
      expect(c.levels.last, 0.8);
      await c.stop();
      expect(c.phase, VoicePhase.idle);
      expect(seen, [('hello', false), ('hello world', true)]);
      c.dispose();
    });

    test('cancel drops the text', () async {
      final device = FakeEngine('device');
      final c = make(device);
      var calls = 0;
      await c.start((_, _) => calls++);
      device.listener!.onPartial('draft');
      await c.cancel();
      device.listener!.onFinal('late');
      expect(c.phase, VoicePhase.idle);
      expect(device.cancelled, 1);
      expect(calls, 1);
      c.dispose();
    });

    test('falls back to the server when on-device is unavailable', () async {
      final device = FakeEngine('device', ready: false);
      final server = FakeEngine('server', batch: true);
      final c = make(device, server: server);
      await c.start((_, _) {});
      expect(c.engineId, 'server');
      expect(device.started, 0);
      c.dispose();
    });

    test('falls back to the server when on-device errors', () async {
      final device = FakeEngine('device');
      final server = FakeEngine('server', batch: true);
      final c = make(device, server: server);
      await c.start((_, _) {});
      device.listener!.onError(VoiceFailure.failed);
      await Future<void>.delayed(Duration.zero);
      expect(c.phase, VoicePhase.listening);
      expect(c.engineId, 'server');
      expect(server.started, 1);
      c.dispose();
    });

    test('high accuracy goes straight to the server', () async {
      final device = FakeEngine('device');
      final server = FakeEngine('server', batch: true);
      final c = make(device, server: server, accurate: true);
      await c.start((_, _) {});
      expect(c.engineId, 'server');
      expect(device.started, 0);
      c.dispose();
    });

    test('no engine at all is an error', () async {
      final c = make(FakeEngine('device', ready: false));
      await c.start((_, _) {});
      expect(c.phase, VoicePhase.error);
      expect(c.failure, VoiceFailure.unavailable);
      c.dispose();
    });

    test('permission: denied asks once, blocked is reported', () async {
      final denied = FakePermission(
        VoicePermissionState.denied,
        afterRequest: VoicePermissionState.denied,
      );
      var c = make(FakeEngine('device'), permission: denied);
      await c.start((_, _) {});
      expect(denied.requests, 1);
      expect(c.failure, VoiceFailure.permissionDenied);
      c.dispose();

      c = make(
        FakeEngine('device'),
        permission: FakePermission(
          VoicePermissionState.denied,
          afterRequest: VoicePermissionState.blocked,
        ),
      );
      await c.start((_, _) {});
      expect(c.failure, VoiceFailure.permissionBlocked);
      c.dispose();
    });

    test('an empty transcript is a "no speech" error', () async {
      final device = FakeEngine('device')..finalOnStop = '';
      final c = make(device);
      await c.start((_, _) {});
      await c.stop();
      expect(c.failure, VoiceFailure.noSpeech);
      c.dispose();
    });
  });

  group('composer', () {
    Future<void> pump(
      WidgetTester tester,
      VoiceController voice, {
      Size size = const Size(360, 640),
      ThemeData? theme,
      bool autoSend = false,
      void Function(String)? onSend,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInput(
                onSend: (text, _) => onSend?.call(text),
                onStop: () {},
                isStreaming: false,
                knowledge: false,
                onToggleWebSearch: () {},
                onToggleKnowledge: () {},
                voice: voice,
                sendVoiceAutomatically: autoSend,
              ),
            ),
          ),
        ),
      );
    }

    Finder mic() => find.bySemanticsLabel(VoiceStrings.mic);
    String field(WidgetTester t) =>
        t.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('idle: mic instead of send; hidden without voice', (
      tester,
    ) async {
      final c = make(FakeEngine('device'));
      await pump(tester, c);
      expect(mic(), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      expect(mic(), findsNothing);
      c.dispose();
    });

    testWidgets('listening, partial text, then stopped keeps text unsent', (
      tester,
    ) async {
      final device = FakeEngine('device')..finalOnStop = 'buy milk today';
      final c = make(device);
      final sent = <String>[];
      await pump(tester, c, onSend: sent.add);

      await tester.tap(mic());
      await tester.pump();
      expect(find.text(VoiceStrings.listening), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.bySemanticsLabel(VoiceStrings.finish), findsOneWidget);

      device.listener!.onPartial('buy milk');
      device.listener!.onLevel(0.6);
      await tester.pump(const Duration(seconds: 2));
      expect(field(tester), 'buy milk');
      expect(find.text('0:02'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(VoiceStrings.finish));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(field(tester), 'buy milk today');
      expect(find.text(VoiceStrings.listening), findsNothing);
      expect(sent, isEmpty);
      expect(tester.takeException(), isNull);
      c.dispose();
    });

    testWidgets('cancel clears the dictated text', (tester) async {
      final device = FakeEngine('device');
      final c = make(device);
      await pump(tester, c);
      await tester.tap(mic());
      await tester.pump();
      device.listener!.onPartial('never mind');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(field(tester), 'never mind');
      await tester.tap(find.bySemanticsLabel(VoiceStrings.cancel));
      await tester.pump();
      expect(field(tester), '');
      expect(c.phase, VoicePhase.idle);
      c.dispose();
    });

    testWidgets('auto-send sends when dictation ends', (tester) async {
      final device = FakeEngine('device')..finalOnStop = 'send this';
      final c = make(device);
      final sent = <String>[];
      await pump(tester, c, autoSend: true, onSend: sent.add);
      await tester.tap(mic());
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(VoiceStrings.finish));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent, ['send this']);
      expect(field(tester), '');
      c.dispose();
    });

    testWidgets('server engine shows TRANSCRIBING until the text arrives', (
      tester,
    ) async {
      final server = FakeEngine('server', batch: true);
      final c = make(FakeEngine('device'), server: server, accurate: true);
      await pump(tester, c);
      await tester.tap(mic());
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(VoiceStrings.finish));
      await tester.pump();
      expect(find.text(VoiceStrings.transcribing), findsOneWidget);
      server.listener!.onFinal('from whisper');
      await tester.pump();
      expect(field(tester), 'from whisper');
      expect(find.text(VoiceStrings.transcribing), findsNothing);
      c.dispose();
    });

    testWidgets('error: message, retry and dismiss', (tester) async {
      final device = FakeEngine('device');
      final c = make(device);
      await pump(tester, c);
      await tester.tap(mic());
      await tester.pump();
      device.listener!.onError(VoiceFailure.noSpeech);
      await tester.pump();
      expect(find.text(VoiceStrings.noSpeech), findsOneWidget);
      expect(find.text(VoiceStrings.retry), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(VoiceStrings.dismiss));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(VoiceStrings.noSpeech), findsNothing);
      c.dispose();
    });

    testWidgets('blocked microphone offers the app settings', (tester) async {
      final perm = FakePermission(VoicePermissionState.blocked);
      final c = make(FakeEngine('device'), permission: perm);
      await pump(tester, c);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(find.text(VoiceStrings.blocked), findsOneWidget);
      await tester.tap(find.text(VoiceStrings.openSettings));
      await tester.pump();
      expect(perm.opened, 1);
      c.dispose();
    });

    testWidgets('denied permission shows the rationale first', (tester) async {
      final perm = FakePermission(
        VoicePermissionState.denied,
        afterRequest: VoicePermissionState.granted,
      );
      final device = FakeEngine('device');
      final c = make(device, permission: perm);
      await pump(tester, c);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(find.text(VoiceStrings.rationaleTitle), findsOneWidget);
      expect(perm.requests, 0);
      await tester.tap(find.text(VoiceStrings.rationaleAllow));
      await tester.pumpAndSettle();
      expect(perm.requests, 1);
      expect(c.phase, VoicePhase.listening);
      await c.cancel();
      c.dispose();
    });

    for (final (name, theme, size) in [
      ('light 360', AppTheme.light, const Size(360, 640)),
      ('dark 360', AppTheme.dark, const Size(360, 640)),
      ('dark landscape', AppTheme.dark, const Size(800, 360)),
    ]) {
      testWidgets('listening fits without overflow ($name)', (tester) async {
        final device = FakeEngine('device');
        final c = make(device);
        await pump(tester, c, size: size, theme: theme);
        await tester.tap(mic());
        await tester.pump();
        device.listener!.onPartial(
          'a fairly long sentence that keeps going and going',
        );
        for (var i = 0; i < 30; i++) {
          device.listener!.onLevel(i / 30);
        }
        await tester.pump(const Duration(seconds: 65));
        expect(find.text('1:05'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await c.cancel();
        c.dispose();
      });
    }
  });
}
