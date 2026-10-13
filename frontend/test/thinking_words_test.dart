import 'package:app/core/constants/thinking_words.dart';
import 'package:app/core/thinking_words.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same seed and prompt give the same line', () {
    final a = ThinkingWords.next(seed: 7, prompt: 'plan a trip', used: {});
    final b = ThinkingWords.next(seed: 7, prompt: 'plan a trip', used: {});
    expect(a, b);
  });

  test('seedOf is stable and differs per text', () {
    expect(ThinkingWords.seedOf('hello'), ThinkingWords.seedOf('hello'));
    expect(ThinkingWords.seedOf('hello'), isNot(ThinkingWords.seedOf('world')));
  });

  test('prompts map to topics', () {
    expect(
      ThinkingWords.topicOf('Fix this Flutter bug in my function'),
      'code',
    );
    expect(ThinkingWords.topicOf('solve this equation for x'), 'math');
    expect(ThinkingWords.topicOf('plan a trip, book a hotel'), 'travel');
    expect(ThinkingWords.topicOf('a quick dinner recipe'), 'food');
    expect(ThinkingWords.topicOf('write an essay outline'), 'writing');
    expect(ThinkingWords.topicOf('who are you'), ThinkingBank.general);
    expect(ThinkingWords.topicOf(null), ThinkingBank.general);
  });

  test('a topical prompt gets a topical line first', () {
    final line = ThinkingWords.next(
      seed: 1,
      prompt: 'solve this equation',
      used: {},
    );
    final stems = ThinkingBank.stems['math']!;
    expect(
      stems.any((s) => line.toLowerCase().contains(s.toLowerCase())),
      true,
    );
  });

  test('every line is short and ends with an ellipsis', () {
    for (final topic in ThinkingBank.stems.keys) {
      final pool = ThinkingWords.pool(topic);
      expect(pool, isNotEmpty);
      for (final l in pool) {
        expect(l.length, lessThanOrEqualTo(ThinkingBank.maxLength), reason: l);
        expect(l.endsWith(ThinkingBank.ellipsis), true, reason: l);
      }
    }
  });

  test('lines do not repeat until the pool runs out', () {
    final used = <String>{};
    final seen = <String>[];
    final size = ThinkingWords.pool('code').length;
    for (var i = 0; i < size; i++) {
      seen.add(
        ThinkingWords.next(seed: 3, prompt: 'debug my code', used: used),
      );
    }
    expect(seen.toSet().length, size);
    // Then it starts over instead of failing.
    expect(
      ThinkingWords.next(seed: 3, prompt: 'debug my code', used: used),
      isNotEmpty,
    );
  });

  test('stems build real words', () {
    final all = ThinkingWords.pool(ThinkingBank.general).join(' ');
    expect(all, contains('Pondering'));
    expect(all, contains('Untangling'));
    expect(ThinkingWords.pool('math').join(' '), contains('Crunching numbers'));
  });
}
