import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/constants/app_sizes.dart';
import 'package:app/core/constants/wait_copy.dart';
import 'package:app/data/ai_model.dart';
import 'package:app/features/chat/wait_status.dart';
import 'package:app/features/chat/widgets/model_info_sheet.dart';
import 'package:app/features/chat/widgets/wait_status_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';

const _id = 'groq:openai/gpt-oss-120b';
const _model = AiModel(
  id: _id,
  name: 'GPT-OSS 120B',
  provider: 'groq',
  maker: 'OpenAI',
  about: 'A strong all-rounder for reasoning, writing and code.',
  contextTokens: 128000,
  speed: 'balanced',
);

Widget _wait(WaitStep step, {String? prompt, bool reduce = false}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Scaffold(
        body: Center(
          child: WaitStatusLine(step: step, prompt: prompt, usedWords: {}),
        ),
      ),
    );

void main() {
  testWidgets('user view: friendly details, no raw id', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: ModelInfoSheet(modelId: _id, name: 'GPT-OSS 120B', model: _model),
      ),
    );
    expect(find.text('GPT-OSS 120B'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.textContaining('all-rounder'), findsOneWidget);
    expect(find.textContaining('pages'), findsOneWidget);
    expect(find.text('Balanced speed and depth'), findsOneWidget);
    expect(find.text(_id), findsNothing);
    expect(find.text(ModelInfoStrings.modelId), findsNothing);
  });

  testWidgets('owner view also shows the raw model id', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: ModelInfoSheet(
          modelId: _id,
          name: 'GPT-OSS 120B',
          model: _model,
          owner: true,
        ),
      ),
    );
    expect(find.text(_id), findsOneWidget);
  });

  testWidgets('a model without details still opens calmly', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: ModelInfoSheet(modelId: _id, name: 'GPT-OSS'),
      ),
    );
    expect(find.text(ModelInfoStrings.noInfo), findsOneWidget);
  });

  testWidgets('wait line crossfades between steps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _wait(
          const WaitStep(WaitKind.phase, text: WaitStrings.searching),
        ),
      ),
    );
    expect(find.text(WaitStrings.searching), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _wait(
          const WaitStep(WaitKind.phase, text: WaitStrings.readingFiles),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-fade: both lines exist.
    expect(find.text(WaitStrings.searching), findsOneWidget);
    expect(find.text(WaitStrings.readingFiles), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(WaitStrings.searching), findsNothing);
    expect(find.text(WaitStrings.readingFiles), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('picking shows the candidate logos and cycles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _wait(
          const WaitStep(
            WaitKind.picking,
            text: WaitStrings.picking,
            logoIds: [_id, 'ollama:gemma4:31b'],
          ),
        ),
      ),
    );
    expect(find.text(WaitStrings.picking), findsOneWidget);
    await tester.pump(AppDurations.waitCycle);
    expect(find.text(WaitStrings.picking), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('think steps show a word and rotate it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _wait(const WaitStep(WaitKind.think), prompt: 'solve this sum'),
      ),
    );
    String word() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => s.endsWith('…'));
    final first = word();
    expect(first.length, lessThanOrEqualTo(22));
    for (var i = 0; i < 4; i++) {
      await tester.pump(AppDurations.waitCycle);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(word(), isNot(first));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion keeps one still word', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _wait(const WaitStep(WaitKind.think), reduce: true),
      ),
    );
    String word() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => s.endsWith('…'));
    final first = word();
    await tester.pump(const Duration(seconds: 10));
    expect(word(), first);
    await tester.pumpWidget(const SizedBox());
  });
}
