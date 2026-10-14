import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/errors.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/auth_models.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shot.dart';

Future<SettingsController> _pump(WidgetTester tester, AuthUser user) async {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  AuthController.instance.user = user;
  SharedPreferences.setMockInitialValues({ErrorsPrefs.errorQueue: '[]'});
  final settings = await SettingsController.load();
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      usage: UsageController(UsageApi('http://localhost:1')),
      api: ChatApi(),
      baseUrl: 'http://localhost:1',
      child: MaterialApp(
        theme: AppTheme.light,
        home: const SettingsCategoryPage(category: SettingsCategory.privacy),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return settings;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    Haptics.enabled = false;
  });
  tearDown(() => AuthController.instance.user = null);

  testWidgets('a user can turn crash reports off, which clears the queue', (
    tester,
  ) async {
    final s = await _pump(
      tester,
      const AuthUser(id: 'u1', email: 'a@b.co', name: 'A', role: 'user'),
    );
    expect(find.text(ErrorsStrings.sendReportsTitle), findsOneWidget);
    expect(s.sendCrashReports, isTrue);
    await tester.tap(find.text(ErrorsStrings.sendReportsTitle));
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.sendCrashReports, isFalse);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(ErrorsPrefs.errorQueue), isNull);
  });

  testWidgets('the owner sees it on and cannot turn it off', (tester) async {
    final s = await _pump(
      tester,
      const AuthUser(id: 'o1', email: 'o@b.co', name: 'O', role: 'owner'),
    );
    expect(find.text(ErrorsStrings.sendReportsOwner), findsOneWidget);
    await tester.tap(find.text(ErrorsStrings.sendReportsTitle));
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.sendCrashReports, isTrue);
  });
}
