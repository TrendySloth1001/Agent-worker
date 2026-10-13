import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/notify_copy.dart';
import 'package:app/core/constants/settings_copy.dart';
import 'package:app/core/constants/smart_toggles.dart';
import 'package:app/core/constants/voice.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/ai_model.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ChatApi {
  @override
  Future<List<AiModel>> fetchModels() async => const [
    AiModel(id: 'x:one', name: 'Model One', provider: 'X'),
    AiModel(id: 'x:two', name: 'Model Two', provider: 'X'),
  ];
}

/// Pumps the root; every test navigates the way the user does so the
/// "summary refreshes on return" paths are covered too.
Future<SettingsController> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsController.load();
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      usage: UsageController(UsageApi('http://localhost:1')),
      api: _FakeApi(),
      baseUrl: 'http://localhost:1',
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return settings;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get _scrollable => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _reveal(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
    await tester.drag(_scrollable, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _open(WidgetTester tester, String category) async {
  await _tap(tester, find.text(category));
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await _settle(tester);
}

Finder _switchRow(String title) => find.widgetWithText(SwitchListTile, title);

bool _on(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(_switchRow(title)).value;

/// The supporting [text] of the list row titled [title].
Finder _summary(String title, String text, {bool contains = false}) =>
    find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: contains ? find.textContaining(text) : find.text(text),
    );

String? _modelGroup(WidgetTester tester) => tester
    .widget<RadioGroup<String>>(find.byType(RadioGroup<String>).first)
    .groupValue;

void main() {
  testWidgets('reply presets highlight and update the root summary', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catReplies);
    bool selected(String t) => tester
        .widget<Semantics>(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == t,
          ),
        )
        .properties
        .selected!;
    expect(selected('Default (recommended)'), isTrue);
    await _tap(tester, find.text('Straight to the point'));
    expect(s.tone, 'direct');
    expect(s.length, 'concise');
    expect(selected('Straight to the point'), isTrue);
    expect(selected('Default (recommended)'), isFalse);
    // The tone and length rows follow too.
    expect(
      _summary(SettingsStrings.toneLabel, SettingsStrings.toneDirect),
      findsOneWidget,
    );
    await _back(tester);
    expect(
      _summary(
        SettingsStrings.catReplies,
        '${SettingsStrings.toneDirect}${SettingsStrings.separator}'
        '${SettingsStrings.lengthConcise}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tone, length and mode dialogs apply the pick', (tester) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catReplies);

    await _tap(tester, find.text(SettingsStrings.toneLabel));
    await _settle(tester);
    await tester.tap(find.text(SettingsStrings.toneCasual));
    await _settle(tester);
    expect(s.tone, 'casual');
    expect(
      _summary(SettingsStrings.toneLabel, SettingsStrings.toneCasual),
      findsOneWidget,
    );

    await _tap(tester, find.text(SettingsStrings.lengthLabel));
    await _settle(tester);
    await tester.tap(find.text(SettingsStrings.lengthConcise));
    await _settle(tester);
    expect(s.length, 'concise');
    expect(
      _summary(SettingsStrings.lengthLabel, SettingsStrings.lengthConcise),
      findsOneWidget,
    );

    await _tap(tester, find.text(SettingsStrings.modeTitle));
    await _settle(tester);
    await tester.tap(find.text(SettingsStrings.modeDebug));
    await _settle(tester);
    expect(s.mode, 'debug');
    expect(
      _summary(SettingsStrings.modeTitle, SettingsStrings.modeDebug),
      findsOneWidget,
    );

    // The dialog opens with the saved pick selected.
    await _tap(tester, find.text(SettingsStrings.toneLabel));
    await _settle(tester);
    expect(_modelGroup(tester), 'casual');
    await tester.tap(find.text(SettingsStrings.cancel));
    await _settle(tester);
  });

  testWidgets('typing switches flip and persist', (tester) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catReplies);
    for (final (title, read) in <(String, bool Function())>[
      (SettingsStrings.autocompleteLabel, () => s.autocompleteOn),
      (VoiceStrings.autoSendLabel, () => s.voiceAutoSend),
      (VoiceStrings.accuracyLabel, () => s.voiceHighAccuracy),
    ]) {
      final before = read();
      await _reveal(tester, _switchRow(title));
      expect(_on(tester, title), before);
      await _tap(tester, _switchRow(title));
      expect(read(), !before, reason: title);
      expect(_on(tester, title), !before, reason: title);
    }
  });

  testWidgets('search default switches flip and the summary follows', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catSearch);
    // WEB starts on Auto and smart suggestions on; the rest start off.
    expect(_on(tester, SettingsStrings.webLabel), isTrue);
    expect(_on(tester, SmartStrings.settingLabel), isTrue);
    for (final title in [SettingsStrings.kbLabel, SettingsStrings.tableLabel]) {
      expect(_on(tester, title), isFalse);
      await _tap(tester, _switchRow(title));
      expect(_on(tester, title), isTrue, reason: title);
    }
    await _tap(tester, _switchRow(SettingsStrings.webLabel));
    await _tap(tester, _switchRow(SmartStrings.settingLabel));
    expect(s.defaultWebSearch, isFalse);
    expect(s.smartSuggestions, isFalse);
    expect(s.defaultKnowledge, isTrue);
    expect(s.defaultRoundTable, isTrue);
    await _back(tester);
    expect(
      _summary(
        SettingsStrings.catSearch,
        [
          SettingsStrings.sumKnowledge,
          SettingsStrings.sumRoundTable,
        ].join(SettingsStrings.separator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('model radios select, persist and update the root', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catModels);
    expect(_modelGroup(tester), 'auto');
    await _tap(tester, find.text(SettingsStrings.modelSmart));
    expect(s.modelChoice, 'smart');
    expect(_modelGroup(tester), 'smart');
    await _tap(tester, find.text(SettingsStrings.modelFast));
    expect(s.modelChoice, 'fast');
    expect(_modelGroup(tester), 'fast');
    await _back(tester);
    expect(
      _summary(
        SettingsStrings.catModels,
        SettingsStrings.modelFast,
        contains: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a specific model picked in the sheet shows everywhere', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catModels);
    await _tap(tester, find.text(SettingsStrings.allModels));
    await _settle(tester);
    await tester.tap(find.text('Model Two'));
    await _settle(tester);
    expect(s.modelChoice, 'x:two');
    // People see the model's name; the raw id is for the owner.
    expect(_summary(SettingsStrings.allModels, 'Model Two'), findsOneWidget);
    expect(_modelGroup(tester), 'x:two');
    await _back(tester);
    expect(
      _summary(SettingsStrings.catModels, 'Model Two', contains: true),
      findsOneWidget,
    );
  });

  testWidgets('theme, text size and haptics update their UI', (tester) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catAppearance);

    await _tap(tester, find.text(SettingsStrings.themeDark));
    expect(s.themeMode, ThemeMode.dark);
    final seg = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(seg.selected, {ThemeMode.dark});

    // Text size: tap near the far end of the track.
    await _reveal(tester, find.byType(Slider));
    final slider = find.byType(Slider);
    expect(tester.widget<Slider>(slider).value, 1);
    await tester.tapAt(tester.getTopRight(slider) + const Offset(-30, 24));
    await _settle(tester);
    expect(s.textScale, 'huge');
    expect(tester.widget<Slider>(slider).value, 3);

    expect(_on(tester, SettingsStrings.hapticsLabel), isTrue);
    await _tap(tester, _switchRow(SettingsStrings.hapticsLabel));
    expect(s.hapticsOn, isFalse);
    expect(_on(tester, SettingsStrings.hapticsLabel), isFalse);

    await _back(tester);
    expect(
      _summary(
        SettingsStrings.catAppearance,
        SettingsStrings.themeDark,
        contains: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('the slider uses the Material 3 Expressive design', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, SettingsStrings.catAppearance);
    await _reveal(tester, find.byType(Slider));
    final theme = Theme.of(tester.element(find.byType(Slider))).sliderTheme;
    // ignore: deprecated_member_use
    expect(theme.year2023, isFalse);
  });

  testWidgets('notifications switch flips and the root summary follows', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catNotifications);
    expect(_on(tester, NotifyCopy.masterLabel), isTrue);
    expect(s.notifyRoundTable, isTrue);
    await _tap(tester, _switchRow(NotifyCopy.masterLabel));
    expect(s.notify.master, isFalse);
    expect(_on(tester, NotifyCopy.masterLabel), isFalse);
    await _back(tester);
    expect(
      _summary(SettingsStrings.catNotifications, SettingsStrings.off),
      findsOneWidget,
    );
  });

  testWidgets('a profile field saved in its sheet shows at once', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _open(tester, SettingsStrings.catReplies);
    await _tap(tester, find.text(SettingsStrings.languageLabel));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'French');
    await tester.tap(find.widgetWithText(FilledButton, 'SAVE'));
    await _settle(tester);
    expect(s.language, 'French');
    expect(find.text('French'), findsOneWidget);
  });

  testWidgets('categorySummary reads the live settings', (tester) async {
    final s = await _pump(tester);
    final scope = AppScope.of(tester.element(find.byType(SettingsScreen)));
    s.setTextScale('large');
    expect(
      categorySummary(SettingsCategory.appearance, scope),
      contains(SettingsStrings.textLarge),
    );
  });
}
