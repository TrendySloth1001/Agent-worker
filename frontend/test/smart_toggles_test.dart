import 'dart:async';

import 'package:app/core/constants/docs.dart';
import 'package:app/core/constants/smart_toggles.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/conversation.dart';
import 'package:app/data/conversations_api.dart';
import 'package:app/features/chat/chat_controller.dart';
import 'package:app/features/chat/composer_state.dart';
import 'package:app/features/chat/widgets/chat_input.dart';
import 'package:app/features/chat/widgets/suggest_prompt.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _Call {
  _Call(this.webMode, this.knowledge, this.suppress, this.smart);
  final WebMode webMode;
  final bool knowledge;
  final Set<SuggestKind> suppress;
  final bool smart;
}

class _FakeChat extends ChatApi {
  _FakeChat(this.script);

  /// Events for each request, in order.
  final List<List<ChatEvent>> script;
  final calls = <_Call>[];
  final reports = <(SuggestKind, String)>[];

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
    calls.add(_Call(webMode, knowledge, suppressSuggest, smartSuggestions));
    final i = calls.length - 1;
    for (final e in script[i < script.length ? i : script.length - 1]) {
      yield e;
    }
  }

  @override
  Future<void> reportSuggestion(
    SuggestKind kind,
    String outcome, {
    String? conversationId,
  }) async => reports.add((kind, outcome));
}

class _FakeConversations extends ConversationsApi {
  _FakeConversations() : super('http://localhost:1');

  @override
  Future<ConversationSummary> save(
    String id,
    List<ChatMessage> messages, {
    String? origin,
  }) async => ConversationSummary(
    id: id,
    title: 'Chat',
    preview: '',
    messageCount: messages.length,
    updatedAt: DateTime.now(),
  );
}

const _kbSuggestion = SuggestToggleEvent(
  SuggestKind.kb,
  reason: 'matches your knowledge base',
  sampleTitles: ['Trip plan', 'Budget', 'Visa'],
);

Future<void> _drain() => Future<void>.delayed(const Duration(milliseconds: 20));

Future<(ChatController, _FakeChat)> _controller(
  List<List<ChatEvent>> script, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final settings = await SettingsController.load();
  final api = _FakeChat(script);
  final c = ChatController(api, settings, _FakeConversations());
  addTearDown(c.dispose);
  return (c, api);
}

List<ChatEvent> _reply(String text, [List<ChatEvent> extra = const []]) => [
  StartEvent(),
  ...extra,
  DeltaEvent(text),
  const DoneEvent(model: 'm'),
];

Widget _input({
  WebMode web = WebMode.auto,
  VoidCallback? onWeb,
  SuggestToggleEvent? suggestion,
  VoidCallback? onAccept,
  VoidCallback? onDismiss,
}) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: ChatInput(
        onSend: (_, _) {},
        onStop: () {},
        isStreaming: false,
        webMode: web,
        knowledge: false,
        onToggleWebSearch: onWeb ?? () {},
        onToggleKnowledge: () {},
        onToggleDoc: () {},
        suggestion: suggestion,
        onAcceptSuggestion: onAccept,
        onDismissSuggestion: onDismiss,
      ),
    ),
  ),
);

void main() {
  group('WEB chip tri-state', () {
    test('cycles auto, on, off and back', () {
      expect(WebMode.auto.next, WebMode.on);
      expect(WebMode.on.next, WebMode.off);
      expect(WebMode.off.next, WebMode.auto);
      expect(WebMode.fromWire('on'), WebMode.on);
      expect(WebMode.fromWire('nonsense'), WebMode.auto);
    });

    testWidgets('shows the state subtly and taps through', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var taps = 0;
      await tester.pumpWidget(_input(onWeb: () => taps++));
      expect(find.text('WEB ${SmartStrings.webAuto}'), findsOneWidget);
      await tester.tap(find.text('WEB ${SmartStrings.webAuto}'));
      expect(taps, 1);
      await tester.pumpWidget(_input(web: WebMode.on));
      expect(find.text('WEB'), findsOneWidget);
      await tester.pumpWidget(_input(web: WebMode.off));
      expect(find.text('WEB ${SmartStrings.webOff}'), findsOneWidget);
    });

    test('controller cycles, new chats start from the setting', () async {
      final (c, _) = await _controller([]);
      expect(c.webMode, WebMode.auto);
      c.cycleWebMode();
      expect(c.webMode, WebMode.on);
      c.cycleWebMode();
      expect(c.webMode, WebMode.off);
      expect(c.webSearch, isFalse);
      c.newChat();
      expect(c.webMode, WebMode.auto);
      final (off, _) = await _controller(
        [],
        prefs: {'default_web_search': false},
      );
      expect(off.webMode, WebMode.off);
    });
  });

  group('suggestion prompt', () {
    testWidgets('KB: titles, Use KB and Not now', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var accepted = 0, dismissed = 0;
      await tester.pumpWidget(
        _input(
          suggestion: _kbSuggestion,
          onAccept: () => accepted++,
          onDismiss: () => dismissed++,
        ),
      );
      expect(find.text(SmartStrings.kbTitle), findsOneWidget);
      expect(
        find.text('3 of your documents look relevant: Trip plan, Budget, Visa'),
        findsOneWidget,
      );
      await tester.tap(find.text(SmartStrings.kbUse));
      await tester.tap(find.text(SmartStrings.notNow));
      expect((accepted, dismissed), (1, 1));
    });

    testWidgets('Doc: Write as Doc and Answer in chat', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var accepted = 0, dismissed = 0;
      await tester.pumpWidget(
        _input(
          suggestion: const SuggestToggleEvent(
            SuggestKind.doc,
            proposedTitle: 'Solar energy',
          ),
          onAccept: () => accepted++,
          onDismiss: () => dismissed++,
        ),
      );
      expect(find.text(SmartStrings.docTitle), findsOneWidget);
      await tester.tap(find.text(SmartStrings.docWrite));
      await tester.tap(find.text(SmartStrings.docChat));
      expect((accepted, dismissed), (1, 1));
    });

    testWidgets('nothing renders without a suggestion', (tester) async {
      await tester.pumpWidget(_input());
      expect(find.byType(SuggestPrompt), findsNothing);
    });

    test('events parse', () {
      final e = ChatEvent.parse(
        'suggest_toggle',
        '{"kind":"kb","reason":"r","sampleTitles":["A","B"]}',
      );
      expect(e, isA<SuggestToggleEvent>());
      expect((e as SuggestToggleEvent).sampleTitles, ['A', 'B']);
      expect(ChatEvent.parse('suggest_toggle', '{"kind":"x"}'), isNull);
      final t = ChatEvent.parse('tools', '{"web":true,"webMode":"auto"}');
      expect((t as ToolsEvent).web && t.auto, isTrue);
    });
  });

  group('controller flow', () {
    test('Use KB turns KB on and resends, replacing the reply', () async {
      final (c, api) = await _controller([
        _reply('short answer', [_kbSuggestion]),
        _reply('answer from your notes'),
      ]);
      c.send('what did we budget for the trip');
      await _drain();
      expect(c.suggestion?.kind, SuggestKind.kb);
      expect(api.calls.single.knowledge, isFalse);
      c.acceptSuggestion();
      await _drain();
      expect(c.suggestion, isNull);
      expect(c.knowledge, isTrue);
      expect(api.calls.last.knowledge, isTrue);
      // Asked once already in this chat: the resend is told not to ask again.
      expect(api.calls.last.suppress, {SuggestKind.kb});
      expect(c.messages.map((m) => m.content), [
        'what did we budget for the trip',
        'answer from your notes',
      ]);
      expect(api.reports, [(SuggestKind.kb, 'accepted')]);
    });

    test('Not now dismisses and is reported', () async {
      final (c, api) = await _controller([
        _reply('hi', [_kbSuggestion]),
      ]);
      c.send('what did we budget');
      await _drain();
      c.dismissSuggestion();
      expect(c.suggestion, isNull);
      expect(c.knowledge, isFalse);
      expect(api.reports, [(SuggestKind.kb, 'dismissed')]);
      c.send('and the visa?');
      await _drain();
      expect(api.calls.last.suppress, {SuggestKind.kb});
    });

    test('a smart-suggestions setting that is off ignores the event', () async {
      final (c, api) = await _controller(
        [
          _reply('hi', [_kbSuggestion]),
        ],
        prefs: {'smart_suggestions': false},
      );
      c.send('what did we budget');
      await _drain();
      expect(c.suggestion, isNull);
      expect(api.calls.single.smart, isFalse);
    });

    test('a new message clears an unanswered suggestion', () async {
      final (c, _) = await _controller([
        _reply('a', [_kbSuggestion]),
        _reply('b'),
      ]);
      c.send('one');
      await _drain();
      expect(c.suggestion, isNotNull);
      c.send('two');
      expect(c.suggestion, isNull);
    });

    test('an automatic search is marked on the reply', () async {
      final (c, _) = await _controller([
        _reply('news', [const ToolsEvent(web: true, auto: true)]),
        _reply('news', [const ToolsEvent(web: true, auto: false)]),
      ]);
      c.send('latest on x');
      await _drain();
      expect(c.messages.last.meta[SmartConfig.searchedKey], isTrue);
      c.send('again');
      await _drain();
      expect(c.messages.last.meta[SmartConfig.searchedKey], isNull);
    });
  });

  group('persistence', () {
    test('ComposerState round-trips through the store', () async {
      SharedPreferences.setMockInitialValues({});
      final store = ComposerStore();
      expect(await store.read('a'), isNull);
      const state = ComposerState(
        web: WebMode.off,
        knowledge: true,
        doc: true,
        docLength: DocConfig.lengthLong,
        suppressed: {SuggestKind.kb, SuggestKind.doc},
      );
      await store.write('a', state);
      await store.write(
        'b',
        const ComposerState(web: WebMode.on, knowledge: false),
      );
      expect(await store.read('a'), state);
      expect((await store.read('b'))?.web, WebMode.on);
    });

    test('bad data falls back to defaults', () {
      final s = ComposerState.fromJson({
        'web': 'x',
        'docLength': 'huge',
        'suppressed': ['kb', 'zz'],
      });
      expect(s.web, WebMode.auto);
      expect(s.docLength, DocConfig.defaultLength);
      expect(s.suppressed, {SuggestKind.kb});
    });

    test(
      'toggles are saved per chat and restored when it is reopened',
      () async {
        final (c, _) = await _controller([
          _reply('hi', [_kbSuggestion]),
        ]);
        c.cycleWebMode(); // on
        c.toggleKnowledge();
        c.send('hello');
        await _drain();
        final id = c.conversationId!;
        c.newChat();
        expect(c.webMode, WebMode.auto);
        expect(c.knowledge, isFalse);
        c.adopt(
          ConversationSummary(
            id: id,
            title: 'Chat',
            preview: '',
            messageCount: 2,
            updatedAt: DateTime.now(),
          ),
          [ChatMessage(role: Role.user, content: 'hello')],
        );
        await _drain();
        expect(c.webMode, WebMode.on);
        expect(c.knowledge, isTrue);
        // The suggestion already offered is remembered too.
        expect((await ComposerStore().read(id))?.suppressed, {SuggestKind.kb});
      },
    );
  });
}
