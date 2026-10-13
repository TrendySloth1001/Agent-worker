import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/profile_copy.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/dot_matrix_backdrop.dart';
import 'package:app/data/auth_models.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/profile/profile_screen.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:app/features/settings/widgets/settings_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
      // No photo: the dot-matrix monogram over the animated dots is shown,
      // and the dots are masked into a ring.
      expect(find.byType(DotMonogram), findsOneWidget);
      expect(find.byType(DotMatrixBackdrop), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DotMatrixBackdrop),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
      // The account id is for the owner only.
      expect(find.text('ID ABCDEF01'), findsNothing);
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

  testWidgets('the owner also sees the account id', (tester) async {
    AuthController.instance.user = const AuthUser(
      id: 'abcdef0123456789',
      email: 'ada@x.dev',
      name: 'Ada Lovelace',
      role: 'owner',
    );
    await _pump(tester, AppTheme.light);
    expect(find.text('ID ABCDEF01'), findsOneWidget);
    expect(find.text(ProfileCopy.roleOwner), findsOneWidget);
  });

  testWidgets('the edit button opens the name sheet', (tester) async {
    await _pump(tester, AppTheme.light);
    await tester.tap(find.text(ProfileCopy.editName));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'touching the circle ripples without blocking the avatar action',
    (tester) async {
      await _pump(tester, AppTheme.light);
      // Let the opening wave finish and the dots come to rest.
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(SchedulerBinding.instance.transientCallbackCount, 0);

      // A tap on the avatar edit button wakes the dots and still triggers it
      // (the button opens the photo sheet when there is a photo to remove).
      AuthController.instance.user = const AuthUser(
        id: 'abcdef0123456789',
        email: 'ada@x.dev',
        name: 'Ada Lovelace',
        role: 'member',
        avatarUrl: 'http://localhost:1/a.png',
      );
      await _pump(tester, AppTheme.light);
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DotMatrixBackdrop)) + const Offset(0, -57),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        SchedulerBinding.instance.transientCallbackCount,
        greaterThan(0),
        reason: 'a touch on the ring wakes the dots',
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byTooltip(ProfileCopy.changePhoto));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion: the circle builds as a still frame', (
    tester,
  ) async {
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
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(DotMatrixBackdrop), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
