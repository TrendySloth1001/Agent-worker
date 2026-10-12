import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/data/suggest_api.dart';
import 'package:app/features/chat/autocomplete/autocomplete_controller.dart';
import 'package:app/features/chat/autocomplete/local_words.dart';

void main() {
  group('LocalWords', () {
    test('suggests what usually follows a word', () {
      final w = LocalWords()
        ..learn('please explain this code')
        ..learn('please explain the idea')
        ..learn('please review it');
      expect(w.suggest('please '), ['explain', 'review']);
    });

    test('completes a half-typed word', () {
      final w = LocalWords()..learn('refactor the repository');
      expect(w.suggest('refactor the rep'), ['repository']);
    });

    test('survives a storage round trip', () {
      final w = LocalWords()..learn('hello brave world');
      final again = LocalWords(w.toStorage());
      expect(again.suggest('hello '), ['brave']);
    });

    test('ignores broken storage', () {
      expect(LocalWords('not json').isEmpty, isTrue);
    });
  });

  group('AutocompleteController', () {
    late List<String> asked;
    late int cancelled;
    late Completer<Completion> pending;

    AutocompleteController make() {
      asked = [];
      cancelled = 0;
      return AutocompleteController(
        local: LocalWords()..learn('write a short story'),
        debounce: const Duration(milliseconds: 20),
        fetch: (text, id) {
          asked.add(text);
          pending = Completer<Completion>();
          return CompleteCall(pending.future, () => cancelled++);
        },
      );
    }

    test('skips short text and links', () async {
      final c = make();
      c.update('hi');
      c.update('see https://exa');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(asked, isEmpty);
      c.dispose();
    });

    test('debounces, then shows the server answer', () async {
      final c = make();
      c.update('How do I');
      c.update('How do I bak');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(asked, ['How do I bak']);
      pending.complete(
        const Completion(completion: 'e a cake?', nextWords: ['bake']),
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.ghost, 'e a cake?');
      expect(c.words, ['bake']);
      c.dispose();
    });

    test('drops an answer for text that changed', () async {
      final c = make();
      c.update('Write a sto');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      c.update('Write a stor');
      pending.complete(const Completion(completion: 'ry'));
      await Future<void>.delayed(Duration.zero);
      expect(c.ghost, isEmpty);
      expect(cancelled, 1);
      c.dispose();
    });

    test('typing the ghost text keeps the rest', () async {
      final c = make();
      c.update('Can you expl');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      pending.complete(const Completion(completion: 'ain it?'));
      await Future<void>.delayed(Duration.zero);
      c.update('Can you expla');
      expect(c.ghost, 'in it?');
      c.dispose();
    });

    test('uses local words before the server answers', () {
      final c = make();
      c.update('write a ');
      expect(c.words, ['short']);
      c.dispose();
    });

    test(
      'accept appends the ghost; a word replaces the partial word',
      () async {
        final c = make();
        final field = TextEditingController(text: 'Can you expl');
        c.update(field.text);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        pending.complete(const Completion(completion: 'ain it?'));
        await Future<void>.delayed(Duration.zero);
        expect(c.accept(field), isTrue);
        expect(field.text, 'Can you explain it?');
        field.text = 'Can you expl';
        c.insertWord(field, 'explain');
        expect(field.text, 'Can you explain ');
        c.dispose();
      },
    );
  });
}
