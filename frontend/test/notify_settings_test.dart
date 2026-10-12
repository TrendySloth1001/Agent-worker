import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/notify_copy.dart';
import 'package:app/core/constants/settings_copy.dart';
import 'package:app/core/notify/notify_kind.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/render.dart';

Future<SettingsController> _open(
  WidgetTester tester,
  ThemeData theme, {
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsController.load();
  await pumpScreen(
    tester,
    const SettingsCategoryPage(category: SettingsCategory.notifications),
    theme: theme,
    textScale: scale,
    wrap: (app) => AppScope(
      settings: settings,
      usage: UsageController(UsageApi('http://localhost:1')),
      api: ChatApi(),
      baseUrl: 'http://localhost:1',
      child: app,
    ),
  );
  return settings;
}

Finder get _list => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.ensureVisible(f);
  await tester.pump();
}

void main() {
  for (final (name, theme, scale) in renderCases) {
    testWidgets('notifications page fits 360dp ($name)', (tester) async {
      await _open(tester, theme, scale: scale);
      expect(find.text(NotifyCopy.masterLabel), findsOneWidget);
      expect(find.text(NotifyCopy.permissionLabel), findsOneWidget);
      await scrollThrough(tester, steps: 14);
      expect(find.text(NotifyCopy.testLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('every kind has a switch', (tester) async {
    await _open(tester, AppTheme.light);
    final seen = <String>{};
    for (var i = 0; i < 20; i++) {
      for (final k in NotifyKind.values) {
        if (find.text(k.label).evaluate().isNotEmpty) seen.add(k.key);
      }
      await tester.drag(_list, const Offset(0, -250));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(seen.length, NotifyKind.values.length);
  });

  testWidgets('master and per-kind switches change the prefs', (tester) async {
    final s = await _open(tester, AppTheme.light);
    await tester.tap(find.text(NotifyCopy.masterLabel));
    await tester.pump();
    expect(s.notify.master, isFalse);
    await tester.tap(find.text(NotifyCopy.masterLabel));
    await tester.pump();
    expect(s.notify.master, isTrue);

    final reply = find.text(NotifyKind.reply.label);
    await _scrollTo(tester, reply);
    await tester.tap(reply);
    await tester.pump();
    expect(s.notify.isOn(NotifyKind.reply), isFalse);
  });

  testWidgets('the round table switch keeps its old setting', (tester) async {
    final s = await _open(tester, AppTheme.light);
    expect(s.notifyRoundTable, isTrue);
    final help = find.text(SettingsStrings.tableNotifyHelp);
    await _scrollTo(tester, help);
    await tester.tap(help);
    await tester.pump();
    expect(s.notifyRoundTable, isFalse);
    expect(s.notify.isOn(NotifyKind.roundTable), isFalse);
  });

  testWidgets('quiet hours reveal From and Until', (tester) async {
    final s = await _open(tester, AppTheme.dark);
    final quiet = find.text(NotifyCopy.quietHelp);
    await _scrollTo(tester, quiet);
    expect(find.text(NotifyCopy.quietFrom), findsNothing);
    await tester.tap(quiet);
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.notify.quietOn, isTrue);
    await _scrollTo(tester, find.text(NotifyCopy.quietTo));
    expect(find.text(NotifyCopy.quietFrom), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission is unavailable off Android', (tester) async {
    await _open(tester, AppTheme.light);
    expect(find.text(NotifyCopy.permissionUnavailable), findsOneWidget);
    expect(find.text(NotifyCopy.allow), findsNothing);
  });
}
