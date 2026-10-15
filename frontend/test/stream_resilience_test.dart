import 'dart:async';
import 'dart:io';

import 'package:app/assist/assist_bridge.dart';
import 'package:app/assist/assist_controller.dart';
import 'package:app/assist/screen_text.dart';
import 'package:app/assist/share_payload.dart';
import 'package:app/core/constants/app_strings.dart';
import 'package:app/core/constants/assist.dart';
import 'package:app/core/constants/smart_toggles.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/ai_model.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/conversation.dart';
import 'package:app/data/conversations_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/chat/chat_controller.dart';
import 'package:app/features/chat/stream_retry.dart';
import 'package:app/features/chat/widgets/interrupted_note.dart';
import 'package:app/features/chat/widgets/message_bubble.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// How a scripted stream ends after its events.
enum _End { done, drop, eof, refused }

/// Each call streams the next script entry; records the history it got.
class _Scripted extends ChatApi {
  _Scripted(this.script);

  final List<(List<String>, _End)> script;
  final histories = <List<String>>[];

  @override
  Future<List<AiModel>> fetchModels() async => const [];

  @override
  Future<void> reportSuggestion(
    SuggestKind kind,
    String outcome, {
    String? conversationId,
  }) async {}

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
    Map<String, Object>? deviceActions,
    Map<String, String> locationHints = const {},
    bool approxLocation = true,
  }) async* {
    histories.add([for (final m in history) '${m.role.name}:${m.content}']);
    final i = histories.length - 1;
    final (deltas, end) = i < script.length
        ? script[i]
        : (const ['fresh answer'], _End.done);
    for (final d in deltas) {
      yield DeltaEvent(d);
    }
    switch (end) {
      case _End.done:
        yield const DoneEvent(model: 'auto');
      case _End.drop:
        throw const SocketException('Connection reset by peer');
      case _End.eof:
        return;
      case _End.refused:
        throw const ApiException('Daily limit reached.', status: 429);
    }
  }
}

class _Conversations extends ConversationsApi {
  _Conversations([this.failures = const []]) : super('http://test');

  /// What the next saves throw (then they succeed).
  final List<Object> failures;
  final origins = <String?>[];
  int calls = 0;

  @override
  Future<ConversationSummary> save(
    String id,
    List<ChatMessage> m, {
    String? origin,
  }) async {
    final i = calls++;
    if (i < failures.length) throw failures[i];
    origins.add(origin);
    return ConversationSummary(
      id: id,
      title: 'Chat',
      preview: '',
      messageCount: m.length,
      updatedAt: DateTime.now(),
    );
  }
}

class _Bridge implements AssistBridge {
  final opened = <String?>[];
  @override
  Stream<AssistShow> get shows => const Stream.empty();
  @override
  Stream<SharedPayload> get shared => const Stream.empty();
  @override
  Stream<void> get hides => const Stream.empty();
  @override
  Future<AssistShow?> ready() async => null;
  @override
  Future<void> shown() async {}
  @override
  Future<void> close() async {}
  @override
  Future<ScreenContext?> screenContext() async => null;
  @override
  Future<bool> openApp([String? link]) async {
    opened.add(link);
    return true;
  }

  @override
  Future<void> assistantSettings() async {}
  @override
  Future<void> allowMicInApp() async {}
}

/// Lets the stream events and short timers run.
Future<void> _settle(WidgetTester tester, [Duration d = Duration.zero]) async {
  await tester.pump(d);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Duration get _firstWait => StreamRetry.delays.first;
Duration get _allWaits => StreamRetry.delays.fold(Duration.zero, (a, b) => a + b);

void main() {
  late SettingsController settings;

  setUp(() async {
    Haptics.enabled = false;
    AuthController.instance.status = AuthStatus.signedIn;
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsController.load();
  });

  tearDown(() => AuthController.instance.status = AuthStatus.restoring);

  group('StreamRetry', () {
    test('drops, gateway errors and restarts retry; refusals do not', () {
      expect(StreamRetry.retryable(null), isTrue);
      expect(StreamRetry.retryable(const SocketException('x')), isTrue);
      expect(StreamRetry.retryable(http.ClientException('x')), isTrue);
      expect(StreamRetry.retryable(TimeoutException('idle')), isTrue);
      expect(
        StreamRetry.retryable(const ApiException('x', status: 502)),
        isTrue,
      );
      expect(
        StreamRetry.retryable(
          const ApiException('x', status: 503, code: 'restarting'),
        ),
        isTrue,
      );
      expect(
        StreamRetry.retryable(const ApiException('x', status: 429)),
        isFalse,
      );
      expect(
        StreamRetry.retryable(
          const ApiException('x', status: 503, code: 'all_models_failed'),
        ),
        isFalse,
      );
      expect(StreamRetry.retryable(const FormatException('x')), isFalse);
      expect(StreamRetry.delay(0), StreamRetry.delays.first);
      expect(StreamRetry.delay(StreamRetry.delays.length), isNull);
    });
  });

  group('overlay', () {
    AssistController overlay(_Scripted api, [_Conversations? conv]) =>
        AssistController(
          bridge: _Bridge(),
          api: api,
          conversations: conv ?? _Conversations(),
          settings: settings,
        )..reset(const AssistShow(source: AssistSource.assist));

    testWidgets('a drop mid-answer keeps the partial text and retries once', (
      tester,
    ) async {
      final api = _Scripted([
        (['Lofi Girl\n\n- Chillhop'], _End.drop),
        (['Lofi Girl\n\n- Chillhop Essentials\n- Jazz Vibes'], _End.done),
      ]);
      final c = overlay(api);
      expect(await c.send('Music to code to?'), isTrue);
      await _settle(tester);

      final reply = c.messages.last;
      expect(reply.content, 'Lofi Girl\n\n- Chillhop');
      expect(reply.status, StreamRetry.reconnectingPhase);
      expect(reply.isStreaming, isTrue);
      expect(reply.error, isNull);
      expect(api.histories, hasLength(1));

      await _settle(tester, _firstWait);
      expect(api.histories, hasLength(2));
      // The same turn again, without the broken partial answer.
      expect(api.histories[1], api.histories[0]);
      expect(reply.content, 'Lofi Girl\n\n- Chillhop Essentials\n- Jazz Vibes');
      expect(reply.isStreaming, isFalse);
      expect(reply.interrupted, isFalse);
      expect(c.messages.where((m) => m.role == Role.assistant), hasLength(1));
      c.dispose();
    });

    testWidgets(
      'retries spent: "Answer interrupted · Retry", never an error line',
      (tester) async {
        final api = _Scripted([
          (['Partial'], _End.drop),
          (const [], _End.eof),
          (const [], _End.drop),
          (['Whole answer'], _End.done),
        ]);
        final c = overlay(api);
        await c.send('Hi');
        await _settle(tester);
        await _settle(tester, _allWaits);
        expect(api.histories, hasLength(1 + StreamRetry.delays.length));

        final reply = c.messages.last;
        expect(reply.interrupted, isTrue);
        expect(reply.isError, isFalse);
        expect(reply.error, isNull);
        expect(reply.content, 'Partial');
        expect(c.streaming, isFalse);

        c.retry();
        await _settle(tester);
        expect(reply.content, 'Whole answer');
        expect(reply.interrupted, isFalse);
        c.dispose();
      },
    );

    testWidgets('a refusal is not retried', (tester) async {
      final api = _Scripted([(const [], _End.refused)]);
      final c = overlay(api);
      await c.send('Hi');
      await _settle(tester, _allWaits);
      expect(api.histories, hasLength(1));
      expect(c.messages.last.isError, isTrue);
      expect(c.messages.last.interrupted, isFalse);
      c.dispose();
    });

    testWidgets('stop during the wait cancels the retry', (tester) async {
      final api = _Scripted([(['Part'], _End.drop)]);
      final c = overlay(api);
      await c.send('Hi');
      await _settle(tester);
      c.stop();
      await _settle(tester, _allWaits);
      expect(api.histories, hasLength(1));
      expect(c.messages.last.content, 'Part');
      c.dispose();
    });

    testWidgets('Open in sparky: a refused save is retried without the tag', (
      tester,
    ) async {
      settings.setAssistSaveHistory(false);
      final conv = _Conversations([
        const ApiException('Something went wrong.', status: 500),
      ]);
      final bridge = _Bridge();
      final c = AssistController(
        bridge: bridge,
        api: _Scripted(const []),
        conversations: conv,
        settings: settings,
      )..reset(const AssistShow(source: AssistSource.assist));
      await c.send('Hi');
      await _settle(tester);
      final opened = c.openInSparky();
      await _settle(tester);
      expect(await opened, isTrue);
      expect(conv.calls, 2);
      expect(conv.origins.single, isNull);
      expect(bridge.opened.single, startsWith(AssistConfig.chatLinkPrefix));
      expect(c.notice, isNull);
      c.dispose();
    });

    testWidgets('Open in sparky: a pending or failed autosave saves first', (
      tester,
    ) async {
      // The autosave after the answer failed (network); Open retries it.
      final conv = _Conversations([const ApiException('offline')]);
      final bridge = _Bridge();
      final c = AssistController(
        bridge: bridge,
        api: _Scripted(const []),
        conversations: conv,
        settings: settings,
      )..reset(const AssistShow(source: AssistSource.assist));
      await c.send('Hi');
      await _settle(tester);
      expect(conv.calls, 1);
      final opened = c.openInSparky();
      await _settle(tester);
      expect(await opened, isTrue);
      expect(conv.origins.single, ConversationSummary.originAssistant);
      expect(bridge.opened, hasLength(1));
      c.dispose();
    });

    testWidgets('Open in sparky: only a phone that is offline gets a message', (
      tester,
    ) async {
      settings.setAssistSaveHistory(false);
      final conv = _Conversations([
        const ApiException('offline'),
        const ApiException('offline'),
      ]);
      final bridge = _Bridge();
      final c = AssistController(
        bridge: bridge,
        api: _Scripted(const []),
        conversations: conv,
        settings: settings,
      )..reset(const AssistShow(source: AssistSource.assist));
      await c.send('Hi');
      await _settle(tester);
      final opened = c.openInSparky();
      await _settle(tester, AssistConfig.openRetryDelay);
      expect(await opened, isFalse);
      expect(conv.calls, 2);
      expect(c.notice, AssistStrings.openOffline);
      expect(bridge.opened, isEmpty);
      c.dispose();
    });
  });

  group('chat', () {
    testWidgets('a drop mid-answer retries and keeps one reply', (
      tester,
    ) async {
      final api = _Scripted([
        (['Half of'], _End.eof),
        (['The whole answer.'], _End.done),
      ]);
      final chat = ChatController(api, settings, _Conversations());
      chat.send('Explain it');
      await _settle(tester);
      final reply = chat.messages.last;
      expect(reply.content, 'Half of');
      expect(reply.status, StreamRetry.reconnectingPhase);
      expect(chat.isSending, isTrue);

      await _settle(tester, _firstWait);
      expect(api.histories[1], api.histories[0]);
      expect(reply.content, 'The whole answer.');
      expect(reply.error, isNull);
      expect(chat.messages.where((m) => m.role == Role.assistant), hasLength(1));
      chat.dispose();
    });

    testWidgets('retries spent: the note, then Retry resumes in place', (
      tester,
    ) async {
      final api = _Scripted([
        (['Half'], _End.drop),
        (const [], _End.drop),
        (const [], _End.drop),
        (['Done now.'], _End.done),
      ]);
      final chat = ChatController(api, settings, _Conversations());
      chat.send('Explain it');
      await _settle(tester);
      await _settle(tester, _allWaits);
      final reply = chat.messages.last;
      expect(reply.interrupted, isTrue);
      expect(reply.error, isNull);
      expect(reply.content, 'Half');
      expect(chat.isSending, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MessageBubble(
              message: reply,
              label: 'Auto',
              onRegenerate: chat.regenerate,
            ),
          ),
        ),
      );
      expect(find.byType(InterruptedNote), findsOneWidget);
      expect(find.text(AppStrings.answerInterrupted), findsOneWidget);
      expect(find.text(AppStrings.errorNetwork), findsNothing);
      expect(find.text(AppStrings.errorInterrupted), findsNothing);

      await tester.tap(find.text(AppStrings.answerRetry));
      await _settle(tester);
      expect(reply.content, 'Done now.');
      expect(chat.messages.where((m) => m.role == Role.assistant), hasLength(1));
      chat.dispose();
    });

    testWidgets('nothing arrived and retries spent: a calm note, not red', (
      tester,
    ) async {
      final api = _Scripted([
        for (var i = 0; i <= StreamRetry.delays.length; i++)
          (const <String>[], _End.drop),
      ]);
      final chat = ChatController(api, settings, _Conversations());
      chat.send('Explain it');
      await _settle(tester);
      await _settle(tester, _allWaits);
      final reply = chat.messages.last;
      expect(reply.isError, isTrue);
      expect(reply.interrupted, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MessageBubble(
              message: reply,
              label: 'Auto',
              onRegenerate: chat.regenerate,
            ),
          ),
        ),
      );
      expect(find.byType(InterruptedNote), findsOneWidget);
      // One Retry (the note's), not a second one in the action row.
      expect(find.text(AppStrings.answerRetry), findsOneWidget);
      chat.dispose();
    });
  });
}
