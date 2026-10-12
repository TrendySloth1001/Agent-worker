import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/profile_copy.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/auth_models.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/profile/profile_screen.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:app/features/settings/widgets/settings_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shot.dart';

Future<void> _pump(
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
        home: const ProfileScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
  await autoShot(tester);
}

void main() {
  setUp(
    () => AuthController.instance.user = const AuthUser(
      id: 'abcdef0123456789',
      email: 'ada@x.dev',
      name: 'Ada Lovelace',
      role: 'member',
    ),
  );
  tearDown(() => AuthController.instance.user = null);

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('profile hero and groups render without overflow ($name)', (
      tester,
    ) async {
      await _pump(tester, theme, textScale: 1.3);
      expect(find.text('Ada Lovelace'), findsWidgets);
      expect(find.text('ada@x.dev'), findsWidgets);
      // No photo: the dot-matrix monogram and the dot grid are shown.
      expect(find.byType(DotMonogram), findsOneWidget);
      expect(find.byType(DotGrid), findsOneWidget);
      expect(find.text('ID ABCDEF01'), findsOneWidget);
      expect(find.text(ProfileCopy.roleMember), findsOneWidget);
      expect(tester.takeException(), isNull);
      final list = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 0; i < 10; i++) {
        await tester.drag(list, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text(ProfileCopy.logOut), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the edit button opens the name sheet', (tester) async {
    await _pump(tester, AppTheme.light);
    await tester.tap(find.text(ProfileCopy.editName));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
