import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/settings_copy.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/auth_models.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/features/settings/telemetry/telemetry_screen.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shot.dart';

Future<SettingsController> _pump(
  WidgetTester tester,
  ThemeData theme, {
  double textScale = 1,
  Widget home = const SettingsScreen(),
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
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
  await autoShot(tester);
  return settings;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get _page => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 15 && target.evaluate().isEmpty; i++) {
    await tester.drag(_page, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

/// Scrolls the whole page; any overflow throws.
Future<void> _scrollThrough(WidgetTester tester) async {
  final list = _page;
  for (var i = 0; i < 12; i++) {
    await tester.drag(list, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

AppScope _scopeOf(WidgetTester tester) =>
    AppScope.of(tester.element(find.byType(SettingsScreen)));

void main() {
  tearDown(() => AuthController.instance.user = null);

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('root fits 360dp without overflow ($name)', (tester) async {
      await _pump(tester, theme);
      expect(tester.takeException(), isNull);
      expect(find.text(SettingsStrings.searchHint), findsOneWidget);
      expect(find.text(SettingsStrings.catReplies), findsOneWidget);
      await _scrollThrough(tester);
      expect(find.text(SettingsStrings.reset), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('root survives the 1.3 text scale', (tester) async {
    await _pump(tester, AppTheme.light, textScale: 1.3);
    await _scrollThrough(tester);
    expect(find.text(SettingsStrings.reset), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final c in SettingsCategory.values.where((c) => !c.isDirect)) {
    testWidgets('${c.name} page opens without overflow', (tester) async {
      await _pump(
        tester,
        AppTheme.dark,
        textScale: 1.3,
        home: SettingsCategoryPage(category: c),
      );
      await _settle(tester);
      expect(find.text(c.title), findsWidgets);
      await _scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tapping a category opens its page', (tester) async {
    await _pump(tester, AppTheme.light);
    await _scrollTo(tester, find.text(SettingsStrings.catAppearance));
    await tester.tap(find.text(SettingsStrings.catAppearance));
    await _settle(tester);
    expect(find.text(SettingsStrings.hapticsLabel), findsOneWidget);
    expect(find.text(SettingsStrings.themeLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search finds an item in a sub-page and opens it', (
    tester,
  ) async {
    await _pump(tester, AppTheme.light);
    await tester.enterText(find.byType(TextField), 'vibrate');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(SettingsStrings.hapticsLabel), findsOneWidget);
    expect(find.text(SettingsStrings.catReplies), findsNothing);
    await tester.tap(find.text(SettingsStrings.hapticsLabel));
    await _settle(tester);
    // Now on the Appearance page, with the haptics row in view.
    expect(find.text(SettingsStrings.themeLabel), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'zzzzqq');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(SettingsStrings.noResults), findsOneWidget);
  });

  testWidgets('a switch row toggles from anywhere on the row', (tester) async {
    final settings = await _pump(tester, AppTheme.light);
    await _scrollTo(tester, find.text(SettingsStrings.catNotifications));
    await tester.tap(find.text(SettingsStrings.catNotifications));
    await _settle(tester);
    expect(settings.notifyRoundTable, isTrue);
    await tester.tap(find.text(SettingsStrings.tableNotifyHelp));
    await tester.pump();
    expect(settings.notifyRoundTable, isFalse);
  });

  testWidgets('a non-owner does not see Telemetry or Server', (tester) async {
    await _pump(tester, AppTheme.light);
    await _scrollThrough(tester);
    expect(find.text(SettingsStrings.catServer), findsNothing);
    expect(find.text(SettingsStrings.catTelemetry), findsNothing);
    expect(searchSettings('telemetry', _scopeOf(tester)), isEmpty);
  });

  testWidgets('the owner sees Telemetry and it opens', (tester) async {
    AuthController.instance.user = const AuthUser(
      id: '1',
      email: 'o@x.dev',
      name: 'Owner',
      role: 'owner',
    );
    await _pump(tester, AppTheme.light);
    expect(find.text('Owner'), findsOneWidget);
    await _scrollTo(tester, find.text(SettingsStrings.developerShow));
    await tester.tap(find.text(SettingsStrings.developerShow));
    await _settle(tester);
    await _scrollTo(tester, find.text(SettingsStrings.catTelemetry));
    expect(find.text(SettingsStrings.catTelemetry), findsOneWidget);
    expect(searchSettings('telemetry', _scopeOf(tester)), isNotEmpty);
    await tester.tap(find.text(SettingsStrings.catTelemetry));
    await _settle(tester);
    expect(find.byType(TelemetryScreen), findsOneWidget);
    // Dispose the screen, then let its reconnect backoff run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a preset sets tone and length', (tester) async {
    final settings = await _pump(tester, AppTheme.light);
    await tester.tap(find.text(SettingsStrings.catReplies));
    await _settle(tester);
    await _scrollTo(tester, find.text('Straight to the point'));
    await tester.tap(find.text('Straight to the point'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(settings.tone, 'direct');
    expect(settings.length, 'concise');
    await _scrollTo(tester, find.text('Teacher'));
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
    await tester.pump();
    await _scrollThrough(tester);
    await tester.tap(find.text(SettingsStrings.reset));
    await _settle(tester);
    expect(find.text(SettingsStrings.resetConfirmTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-ok')));
    await _settle(tester);
    expect(settings.tone, '');
    expect(settings.length, 'detailed');
    expect(settings.textScale, 'normal');
    expect(settings.modelId, isNull);
    expect(settings.name, 'Ada');
  });
}
