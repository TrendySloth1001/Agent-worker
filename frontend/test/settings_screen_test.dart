import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/settings_copy.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> _pump(
  WidgetTester tester,
  ThemeData theme, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsController.load();
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      usage: UsageController(UsageApi('http://localhost:1')),
      api: ChatApi(),
      baseUrl: 'http://localhost:1',
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return settings;
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('settings fits 360px without overflow ($name)', (tester) async {
      await _pump(tester, theme);
      expect(tester.takeException(), isNull);
      expect(find.text(SettingsStrings.youTitle), findsOneWidget);
      expect(find.text('Straight to the point'), findsOneWidget);

      // Open Advanced and scroll through everything; any overflow throws.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text(SettingsStrings.advancedTitle),
        300,
        scrollable: list,
      );
      await tester.tap(find.text(SettingsStrings.advancedTitle));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(
        find.text(SettingsStrings.modelAuto),
        300,
        scrollable: list,
      );
      expect(find.text(SettingsStrings.modelAuto), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(SettingsStrings.reset),
        300,
        scrollable: list,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings survives the largest text size', (tester) async {
    await _pump(tester, AppTheme.light, textScale: 1.3);
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text(SettingsStrings.reset),
      300,
      scrollable: list,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters settings', (tester) async {
    await _pump(tester, AppTheme.light);
    expect(find.text('Straight to the point'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'vibrate');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(SettingsStrings.hapticsLabel), findsOneWidget);
    expect(find.text('Straight to the point'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzzzqq');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(SettingsStrings.noResults), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a preset sets tone and length', (tester) async {
    final settings = await _pump(tester, AppTheme.light);
    await tester.tap(find.text('Straight to the point'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.tone, 'direct');
    expect(settings.length, 'concise');
    await tester.ensureVisible(find.text('Teacher'));
    await tester.pump();
    await tester.tap(find.text('Teacher'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.tone, 'friendly');
    expect(settings.length, 'detailed');
  });

  testWidgets('reset restores defaults but keeps the profile', (tester) async {
    final settings = await _pump(tester, AppTheme.light);
    settings.setName('Ada');
    settings.applyReplyStyle('direct', 'concise');
    settings.setTextScale('huge');
    settings.setModelChoice('fast');
    settings.resetToDefaults();
    expect(settings.tone, '');
    expect(settings.length, 'detailed');
    expect(settings.textScale, 'normal');
    expect(settings.modelId, isNull);
    expect(settings.name, 'Ada');
  });
}
