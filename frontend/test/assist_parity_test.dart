import 'dart:async';

import 'package:app/assist/assist_bridge.dart';
import 'package:app/assist/assist_controller.dart';
import 'package:app/assist/screen_text.dart';
import 'package:app/core/constants/smart_toggles.dart';
import 'package:app/core/haptics.dart';
import 'package:app/data/ai_model.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/conversation.dart';
import 'package:app/data/conversations_api.dart';
import 'package:app/data/docs_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/chat/chat_controller.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Records every request flag, as the server would see it.
class _Recorder extends ChatApi {
  _Recorder([this.script = const []]);

  final List<List<ChatEvent>> script;
  final calls = <Map<String, Object?>>[];
  final reports = <(SuggestKind, String)>[];

  @override
  Future<List<AiModel>> fetchModels() async => const [
    AiModel(id: 'gpt-x', name: 'GPT X', provider: 'openai'),
  ];

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
  }) async* {
    calls.add({
      'history': [for (final m in history) '${m.role.name}:${m.content}'],
      'modelId': modelId,
      'webMode': webMode,
      'knowledge': knowledge,
      'mode': mode,
      'profile': profile,
      'context': context,
      'roundTable': roundTable,
      'smartSuggestions': smartSuggestions,
      'suppressSuggest': Set.of(suppressSuggest),
      'apps': apps,
    });
    final i = calls.length - 1;
    final events = i < script.length
        ? script[i]
        : const [DeltaEvent('ok'), DoneEvent(model: 'gpt-x')];
    for (final e in events) {
      yield e;
    }
    // A scripted turn without an end stays open (still answering).
    if (events.lastOrNull is! DoneEvent) await Completer<void>().future;
  }

  @override
  Future<void> reportSuggestion(
    SuggestKind kind,
    String outcome, {
    String? conversationId,
  }) async => reports.add((kind, outcome));
}

class _Conversations extends ConversationsApi {
  _Conversations() : super('http://test');

  @override
  Future<ConversationSummary> save(String id, List<ChatMessage> m) async =>
      ConversationSummary(
        id: id,
        title: 'Chat',
        preview: '',
        messageCount: m.length,
        updatedAt: DateTime.now(),
      );
}

class _Bridge implements AssistBridge {
  @override
  Stream<AssistShow> get shows => const Stream.empty();
  @override
  Future<AssistShow?> ready() async => null;
  @override
  Future<void> shown() async {}
  @override
  Future<void> close() async {}
  @override
  Future<ScreenContext?> screenContext() async => null;
  @override
  Future<bool> openApp([String? link]) async => true;
  @override
  Future<void> assistantSettings() async {}
}

class _Docs extends DocsApi {
  final requests = <Map<String, dynamic>>[];

  @override
  Future<String> create(DocRequest request) async {
    requests.add(request.toJson());
    return 'doc-1';
  }
}

Future<void> _drain() => Future<void>.delayed(const Duration(milliseconds: 20));

Future<SettingsController> _settings({bool custom = false}) async {
  SharedPreferences.setMockInitialValues({});
  final s = await SettingsController.load();
  if (custom) {
    s
      ..setDefaultWebSearch(false)
      ..setDefaultKnowledge(true)
      ..setDefaultRoundTable(true)
      ..setSmartSuggestions(false)
      ..setModelChoice('gpt-x')
      ..setMode('review')
      ..setName('Nick')
      ..setTone('friendly');
  }
  return s;
}

/// What the app's chat sends for "hi" with these settings.
Future<Map<String, Object?>> _appSends(SettingsController s) async {
  final api = _Recorder();
  final chat = ChatController(api, s, _Conversations());
  await chat.loadModels();
  chat.send('hi');
  await _drain();
  chat.dispose();
  return api.calls.single;
}

AssistController _overlay(
  SettingsController s,
  _Recorder api, {
  DocsApi? docs,
}) => AssistController(
  bridge: _Bridge(),
  api: api,
  conversations: _Conversations(),
  settings: s,
  docs: docs,
)..reset(const AssistShow(source: AssistSource.assist));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Haptics.enabled = false;
    AuthController.instance.status = AuthStatus.signedIn;
  });

  tearDown(() => AuthController.instance.status = AuthStatus.restoring);

  for (final custom in [false, true]) {
    final name = custom ? 'every setting changed' : 'defaults';
    test('overlay sends the same flags as the app: $name', () async {
      final s = await _settings(custom: custom);
      final app = await _appSends(s);

      final api = _Recorder();
      final c = _overlay(s, api);
      await c.loadModels();
      expect(await c.send('hi'), isTrue);
      await _drain();
      expect(api.calls.single, app);
      if (custom) {
        expect(app['modelId'], 'gpt-x');
        expect(app['webMode'], WebMode.off);
        expect(app['knowledge'], isTrue);
        expect(app['roundTable'], isTrue);
        expect(app['smartSuggestions'], isFalse);
        expect(app['mode'], 'review');
        expect((app['profile']! as Map)['name'], 'Nick');
      }
    });
  }

  test('toggles change the request like the app chips do', () async {
    final s = await _settings();
    final api = _Recorder();
    final c = _overlay(s, api);
    c
      ..cycleWebMode()
      ..toggleKnowledge()
      ..toggleRoundTable();
    await c.send('hi');
    await _drain();
    final call = api.calls.single;
    expect(call['webMode'], WebMode.auto.next);
    expect(call['knowledge'], isTrue);
    expect(call['roundTable'], isTrue);

    // A new opening starts from the settings again.
    c.reset(const AssistShow(source: AssistSource.assist));
    expect(c.webMode, WebMode.auto);
    expect(c.knowledge, isFalse);
    expect(c.roundTable, isFalse);
  });

  test('Use KB? asks again with the KB on and is not offered twice', () async {
    final s = await _settings();
    final api = _Recorder([
      [
        const DeltaEvent('From the web…'),
        const SuggestToggleEvent(SuggestKind.kb, reason: 'your notes'),
        const DoneEvent(),
      ],
    ]);
    final c = _overlay(s, api);
    await c.send('my trip plan?');
    await _drain();
    expect(c.suggestion?.kind, SuggestKind.kb);

    c.acceptSuggestion();
    await _drain();
    expect(api.reports.single, (SuggestKind.kb, 'accepted'));
    expect(api.calls, hasLength(2));
    expect(api.calls.last['knowledge'], isTrue);
    expect(api.calls.last['suppressSuggest'], {SuggestKind.kb});
    expect(api.calls.last['history'], ['user:my trip plan?']);
    expect(c.messages.map((m) => m.content), ['my trip plan?', 'ok']);
  });

  test('Round Table progress lands on the reply', () async {
    final s = await _settings();
    final api = _Recorder([
      [const TableEvent(phase: 'researching', etaMs: 30000)],
    ]);
    final c = _overlay(s, api)..toggleRoundTable();
    await c.send('compare these');
    await _drain();
    expect(api.calls.single['roundTable'], isTrue);
    expect(c.messages.last.tablePhase, 'researching');

    // Answer fast: one model, same question.
    c.answerFast();
    await _drain();
    expect(api.calls.last['roundTable'], isFalse);
    expect(c.messages.last.content, 'ok');
  });

  test('DOC writes a document with the same toggles', () async {
    final s = await _settings(custom: true);
    final api = _Recorder();
    final docs = _Docs();
    final c = _overlay(s, api, docs: docs)..toggleDoc();
    await c.send('a report on heat pumps');
    await _drain();
    expect(api.calls, isEmpty);
    expect(docs.requests.single['prompt'], 'a report on heat pumps');
    expect(docs.requests.single['knowledge'], isTrue);
    expect(docs.requests.single['webSearch'], isFalse);
    expect((c.messages.last.meta['doc']! as Map)['id'], 'doc-1');
    expect(c.sending, isFalse);
  });
}
