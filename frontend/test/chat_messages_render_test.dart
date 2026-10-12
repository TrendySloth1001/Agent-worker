import 'package:app/data/chat_message.dart';
import 'package:app/features/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';

/// Chat bubbles with real-looking content at 360dp, light/dark/1.3x.
void main() {
  for (final (name, theme, scale) in renderCases) {
    testWidgets('chat bubbles render at 360dp ($name)', (tester) async {
      final user = ChatMessage(
        role: Role.user,
        content:
            'How do I debounce a search field in Flutter without a package?',
      );
      final reply = ChatMessage(
        role: Role.assistant,
        modelId: 'auto',
        content:
            'Use a `Timer` and cancel it on every keystroke.\n\n'
            '```dart\nTimer? _t;\nvoid onChanged(String v) {\n'
            '  _t?.cancel();\n  _t = Timer(const Duration(milliseconds: 300), () => search(v));\n}\n```\n\n'
            '- Cancel in `dispose`\n- Keep the delay near 300 ms\n\n'
            '| Option | Cost |\n|---|---|\n| Timer | none |\n| rxdart | extra dependency |',
      );
      final failed = ChatMessage(
        role: Role.assistant,
        isError: true,
        content: 'The model did not answer. Try again.',
      );
      await pumpScreen(
        tester,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MessageBubble(message: user, label: ''),
              const SizedBox(height: 16),
              MessageBubble(
                message: reply,
                label: 'Auto',
                question: user.content,
              ),
              const SizedBox(height: 16),
              MessageBubble(message: failed, label: 'Auto'),
            ],
          ),
        ),
        theme: theme,
        textScale: scale,
        height: 1100,
      );
      expect(find.textContaining('debounce'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
