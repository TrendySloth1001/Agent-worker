import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/app_prefs.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/ai_model.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/telemetry.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/chat/widgets/message_bubble.dart';
import 'package:app/features/chat/widgets/round_table_panel.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/telemetry/telemetry_grouping.dart';
import 'package:app/features/settings/telemetry/telemetry_widgets.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:app/features/settings/widgets/model_choice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shot.dart';

/// The backend registry, as `/models` serves it.
const _models = [
  AiModel(
    id: 'groq:openai/gpt-oss-120b',
    name: 'GPT-OSS 120B',
    provider: 'groq',
  ),
  AiModel(
    id: 'nvidia:nvidia/nemotron-3-ultra-550b-a55b',
    name: 'Nemotron 3 Ultra',
    provider: 'nvidia',
  ),
  AiModel(id: 'groq:qwen/qwen3.8-27b', name: 'Qwen 3.8 27B', provider: 'groq'),
  AiModel(id: 'ollama:gemma4:31b', name: 'Gemma 4 31B', provider: 'ollama'),
  AiModel(
    id: 'nvidia:z-ai/glm-5.3-flash',
    name: 'GLM 5.3 Flash',
    provider: 'nvidia',
  ),
  AiModel(
    id: 'openrouter:google/gemma-4-31b-it:free',
    name: 'Gemma 4 31B',
    provider: 'openrouter',
  ),
  AiModel(
    id: 'nvidia:meta/llama-3.2-11b-vision-instruct',
    name: 'Llama 3.2 11B Vision',
    provider: 'nvidia',
  ),
];

class _FakeApi extends ChatApi {
  @override
  Future<List<AiModel>> fetchModels() async => _models;
}

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget body, {
  double height = 915,
  SettingsController? settings,
}) async {
  tester.view.physicalSize = Size(412 * 2.6, height * 2.6);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Scaffold(body: SafeArea(child: body)),
  );
  await tester.pumpWidget(
    settings == null
        ? app
        : AppScope(
            settings: settings,
            usage: UsageController(UsageApi('http://localhost:1')),
            api: _FakeApi(),
            baseUrl: 'http://localhost:1',
            child: app,
          ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await _settleSvgs(tester);
}

/// SVG assets decode off the test clock.
Future<void> _settleSvgs(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

ChatMessage _reply(String model, String text) =>
    ChatMessage(role: Role.assistant, modelId: model, content: text);

Map<String, dynamic> _tel(String provider, String model, String name, int n) =>
    {
      'id': '$provider:$model',
      'provider': provider,
      'model': model,
      'name': name,
      'requests': n,
      'ok': n - n ~/ 20,
      'failed': n ~/ 20,
      'unknown': 0,
      'failureRate': (n ~/ 20) / n,
      'tokensIn': 3200 * n,
      'tokensOut': 480 * n,
      'latencyP50': 400 + n * 7 % 900,
      'latencyP95': 2400,
      'ttftP50': 320,
      'ttftAvg': 410,
      'latencyAvg': 900,
      'failuresByCode': <String, int>{},
    };

void main() {
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    final theme = dark ? AppTheme.dark : AppTheme.light;

    testWidgets('answer labels ($mode)', (tester) async {
      final replies = [
        (
          'Gemma 4 31B',
          _reply(
            'ollama:gemma4:31b',
            'Use a `Timer` and cancel it on every keystroke; 300 ms feels instant.',
          ),
        ),
        (
          'GPT-OSS 120B',
          _reply(
            'groq:openai/gpt-oss-120b',
            'A **debounce** waits for the input to settle before searching.',
          ),
        ),
        (
          'Nemotron 3 Ultra',
          _reply(
            'nvidia:nvidia/nemotron-3-ultra-550b-a55b',
            'Cancel the timer in `dispose` so it never fires late.',
          ),
        ),
        (
          'Qwen 3.8 27B',
          _reply(
            'groq:qwen/qwen3.8-27b',
            'Keep the delay between 250 and 400 ms.',
          ),
        ),
        (
          'GLM 5.3 Flash',
          _reply(
            'nvidia:z-ai/glm-5.3-flash',
            'Or use `rxdart`, at the cost of a dependency.',
          ),
        ),
        (
          'Llama 3.2 11B Vision',
          _reply(
            'nvidia:meta/llama-3.2-11b-vision-instruct',
            'The screenshot shows a search bar with a spinner.',
          ),
        ),
      ];
      await _pump(
        tester,
        theme,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (label, m) in replies) ...[
              MessageBubble(message: m, label: label),
              const SizedBox(height: 12),
            ],
            MessageBubble(
              message: ChatMessage(
                role: Role.assistant,
                isError: true,
                content: 'The model did not answer. Try again.',
              ),
              label: 'Assistant',
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/model_logos_answers_$mode.png'),
      );
    });

    testWidgets('model picker ($mode)', (tester) async {
      SharedPreferences.setMockInitialValues({
        AppPrefs.modelChoice: 'ollama:gemma4:31b',
      });
      final settings = await SettingsController.load();
      await _pump(
        tester,
        theme,
        const Column(children: [SpecificModelTile()]),
        settings: settings,
      );
      await tester.tap(find.byType(SpecificModelTile));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await _settleSvgs(tester);
      expect(find.text('Qwen 3.8 27B'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/model_logos_picker_$mode.png'),
      );
    });

    testWidgets('telemetry models ($mode)', (tester) async {
      final now = DateTime.now();
      final rows = [
        _tel('groq', 'openai/gpt-oss-120b', 'GPT-OSS 120B', 412),
        _tel('ollama', 'gpt-oss:120b', 'GPT-OSS 120B', 96),
        _tel(
          'nvidia',
          'nvidia/nemotron-3-ultra-550b-a55b',
          'Nemotron 3 Ultra',
          188,
        ),
        _tel('ollama', 'gemma4:31b', 'Gemma 4 31B', 140),
        _tel('groq', 'qwen/qwen3.8-27b', 'Qwen 3.8 27B', 77),
        _tel('nvidia', 'z-ai/glm-5.3-flash', 'GLM 5.3 Flash', 41),
        _tel(
          'nvidia',
          'meta/llama-3.2-11b-vision-instruct',
          'meta/llama-3.2-11b-vision-instruct',
          20,
        ),
      ];
      final groups = groupModels([
        for (final r in rows) ModelTelemetry.fromJson(r, now),
      ]).groups;
      await _pump(
        tester,
        theme,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ModelColumns(),
            for (final g in groups)
              ModelRow(group: g, open: false, onTap: () {}, now: now),
          ],
        ),
        height: 640,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/model_logos_telemetry_$mode.png'),
      );
    });

    testWidgets('round table seats ($mode)', (tester) async {
      TableSeat seat(
        String s,
        String model,
        String name,
        String status,
        String sum,
      ) => TableSeat(
        seat: s,
        model: model,
        name: name,
        status: status,
        summary: sum,
      );
      final seats = [
        seat(
          'A',
          'groq:openai/gpt-oss-120b',
          'GPT-OSS 120B',
          'done',
          'Debounce with a Timer; cancel it in dispose.',
        ),
        seat(
          'B',
          'ollama:gemma4:31b',
          'Gemma 4 31B',
          'done',
          'Agrees; adds a 300 ms default.',
        ),
        seat(
          'C',
          'nvidia:nvidia/nemotron-3-ultra-550b-a55b',
          'Nemotron 3 Ultra',
          'working',
          '',
        ),
        seat('D', 'nvidia:z-ai/glm-5.3-flash', 'GLM 5.3 Flash', 'failed', ''),
      ];
      await _pump(
        tester,
        theme,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final s in seats) ...[
                TableSeatRow(seat: s, live: false),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        height: 360,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/model_logos_table_$mode.png'),
      );
    });
  }
}
