import 'package:app/core/constants/wait_copy.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/features/chat/wait_status.dart';
import 'package:flutter_test/flutter_test.dart';

String? _names(String id) => switch (id) {
  'groq:openai/gpt-oss-120b' => 'GPT-OSS 120B',
  'ollama:gemma4:31b' => 'Gemma 4 31B',
  'nvidia:z-ai/glm-5.3-flash' => 'GLM 5.3 Flash',
  'ollama:nemotron-3-ultra' => 'Nemotron 3 Ultra',
  _ => null,
};

ChatMessage _waiting() => ChatMessage(role: Role.assistant, isStreaming: true);

void main() {
  test('events parse candidates and attempt', () {
    final start = ChatEvent.parse(
      'start',
      '{"requestId":"r","candidates":["a:b","c:d"]}',
    );
    expect((start as StartEvent).candidates, ['a:b', 'c:d']);
    final model = ChatEvent.parse('model', '{"model":"a:b","attempt":2}');
    expect((model as ModelEvent).attempt, 2);
    expect(
      (ChatEvent.parse('model', '{"model":"a:b"}') as ModelEvent).attempt,
      1,
    );
  });

  test('nothing yet shows a playful word', () {
    expect(resolveWait(_waiting(), nameOf: _names).kind, WaitKind.think);
  });

  test('start shows the candidates, at most three, one per name', () {
    final m = _waiting()
      ..waitLast = 'start'
      ..waitCandidates = [
        'groq:openai/gpt-oss-120b',
        'ollama:gemma4:31b',
        'nvidia:z-ai/glm-5.3-flash',
        'ollama:nemotron-3-ultra',
      ];
    final s = resolveWait(m, nameOf: _names);
    expect(s.kind, WaitKind.picking);
    expect(s.text, WaitStrings.picking);
    expect(s.logoIds, hasLength(3));
  });

  test('model shows its friendly name, never the raw id', () {
    final m = _waiting()
      ..waitLast = 'model'
      ..modelId = 'ollama:gemma4:31b';
    final s = resolveWait(m, nameOf: _names);
    expect(s.kind, WaitKind.model);
    expect(s.text, 'Going with Gemma 4 31B');
    expect(s.text, isNot(contains('ollama')));
  });

  test('a later attempt reads as switching, never as a failure', () {
    final m = _waiting()
      ..waitLast = 'model'
      ..waitAttempt = 2
      ..modelId = 'ollama:gemma4:31b';
    final s = resolveWait(m, nameOf: _names);
    expect(s.kind, WaitKind.switching);
    expect(s.text, 'Switching to Gemma 4 31B…');
    expect(s.text.toLowerCase(), isNot(contains('fail')));
  });

  test('an unknown model name never leaks the id', () {
    final m = _waiting()
      ..waitLast = 'model'
      ..waitAttempt = 2
      ..modelId = 'groq:mystery/x';
    expect(resolveWait(m, nameOf: _names).text, WaitStrings.switching);
    m.waitAttempt = 1;
    expect(resolveWait(m, nameOf: _names).kind, WaitKind.think);
  });

  test('phases map to friendly copy', () {
    const expected = {
      'processing_files': WaitStrings.readingFiles,
      'analyzing_image': WaitStrings.lookingAtImage,
      'retrieving': WaitStrings.checkingNotes,
      'searching': WaitStrings.searching,
      'round_table': WaitStrings.roundTable,
      'queued': WaitStrings.queued,
    };
    for (final e in expected.entries) {
      final m = _waiting()
        ..waitLast = 'status'
        ..status = e.key;
      final s = resolveWait(m, nameOf: _names);
      expect(s.kind, WaitKind.phase, reason: e.key);
      expect(s.text, e.value, reason: e.key);
    }
  });

  test('generating and unknown phases fall back to the playful word', () {
    for (final phase in ['generating', 'something_new']) {
      final m = _waiting()
        ..waitLast = 'status'
        ..status = phase;
      expect(resolveWait(m, nameOf: _names).kind, WaitKind.think);
    }
  });
}
