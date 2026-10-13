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
  int pumpMs = 400,
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
  await tester.pump(Duration(milliseconds: pumpMs));
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
      // and the dots form a radial aura (no mask, no edit badge).
      expect(find.byType(DotMonogram), findsOneWidget);
      expect(find.byType(DotMatrixBackdrop), findsOneWidget);
      expect(
        tester.widget<DotMatrixBackdrop>(find.byType(DotMatrixBackdrop)).aura,
        isNotNull,
      );
      expect(find.byTooltip(ProfileCopy.changePhoto), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.label == ProfileCopy.changePhoto,
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

  testWidgets('touching the aura wakes the dots; tapping the avatar opens '
      'change photo', (tester) async {
    AuthController.instance.user = const AuthUser(
      id: 'abcdef0123456789',
      email: 'ada@x.dev',
      name: 'Ada Lovelace',
      role: 'member',
      avatarUrl: 'http://localhost:1/a.png',
    );
    await _pump(tester, AppTheme.light);
    // Let the opening wave finish and the dots come to rest.
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    // A touch on the aura (outside the avatar) wakes the dots.
    final centre = tester.getCenter(find.byType(DotMatrixBackdrop));
    final gesture = await tester.startGesture(centre + const Offset(0, -75));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      SchedulerBinding.instance.transientCallbackCount,
      greaterThan(0),
      reason: 'a touch on the aura wakes the dots',
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BottomSheet), findsNothing);

    // Tapping the avatar itself opens the change-photo sheet.
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  // Review screenshots of the aura (only with --dart-define=SHOTS=true).
  if (const bool.fromEnvironment('SHOTS')) {
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      for (final photo in [false, true]) {
        testWidgets('aura shots $name ${photo ? 'photo' : 'initials'}', (
          tester,
        ) async {
          if (photo) {
            AuthController.instance.user = AuthUser(
              id: 'abcdef0123456789',
              email: 'ada@x.dev',
              name: 'Ada Lovelace',
              role: 'member',
              avatarUrl: 'data:image/png;base64,$_photoPng',
            );
          }
          // _pump runs 500 ms; the opening wave is in full swing.
          await _pump(tester, theme, pumpMs: _waveMs);
          await shot(
            tester,
            'aura_${name}_${photo ? 'photo' : 'initials'}_wave',
          );
          for (var i = 0; i < 200; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await shot(
            tester,
            'aura_${name}_${photo ? 'photo' : 'initials'}_rest',
          );
        });
      }
    }
  }
}

const _waveMs = 150;

/// A small solid-colour PNG used as the test photo.
const _photoPng =
    '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';
