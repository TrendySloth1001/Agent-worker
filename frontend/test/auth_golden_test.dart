import 'support/backdrop.dart';
import 'dart:async';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/sso_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/features/auth/register_screen.dart';
import 'package:app/features/auth/widgets/sso_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/shot.dart';

/// Lets flutter_svg finish decoding the pictures (real async work).
Future<void> _settleArt(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
}

void _view(
  WidgetTester tester, {
  Size size = const Size(412, 915),
  double keyboard = 0,
}) {
  const dpr = 2.6;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = const FakeViewPadding(top: 24 * dpr, bottom: 16 * dpr);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required bool dark,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await _settleArt(tester);
}

Future<void> _golden(WidgetTester tester, String name) async {
  await settleBackdrop(tester);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/auth_$name.png'),
  );
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    SsoSection.debugProviders = const SsoProviders(
      github: true,
      githubWeb: true,
      googleWebClientId: 'test.apps.googleusercontent.com',
    );
  });
  tearDownAll(() => SsoSection.debugProviders = null);

  for (final (name, dark) in [('light', false), ('dark', true)]) {
    testWidgets('login ($name)', (tester) async {
      _view(tester);
      await _pump(tester, const LoginScreen(), dark: dark);
      expect(find.text('Continue with GitHub'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      await _golden(tester, 'login_$name');
    });

    testWidgets('register ($name)', (tester) async {
      _view(tester);
      await _pump(tester, const RegisterScreen(), dark: dark);
      await _golden(tester, 'register_$name');
    });
  }

  testWidgets('login, keyboard open', (tester) async {
    _view(tester, keyboard: 315);
    await _pump(tester, const LoginScreen(), dark: false);
    await _golden(tester, 'login_keyboard');
  });

  testWidgets('login, short screen (412x600)', (tester) async {
    _view(tester, size: const Size(412, 600));
    await _pump(tester, const LoginScreen(), dark: true);
    await _golden(tester, 'login_short');
  });

  testWidgets('login, small phone (360x740) at 1.3x text', (tester) async {
    _view(tester, size: const Size(360, 740));
    await _pump(tester, const LoginScreen(), dark: false, scale: 1.3);
    expect(tester.takeException(), isNull);
    await _golden(tester, 'login_360_text13');
  });

  testWidgets('login, error then loading', (tester) async {
    _view(tester);
    // Holds the sign-in request open so the button stays loading.
    final pending = Completer<http.Response>();
    AuthController.instance.debugHttp = MockClient((_) => pending.future);
    addTearDown(() => AuthController.instance.debugHttp = http.Client());
    AuthController.instance.notice = 'Wrong email or password.';
    await _pump(tester, const LoginScreen(), dark: false);
    expect(find.text('Wrong email or password.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      'nick@cloudnsofts.com',
    );
    await tester.enterText(find.byType(TextField).last, 'correct horse');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Signing in…'), findsOneWidget);
    await _golden(tester, 'login_loading');
    pending.complete(
      http.Response('{"error":{"message":"Wrong email or password."}}', 401),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    await _golden(tester, 'login_error');
  });

  testWidgets('login, field errors (dark)', (tester) async {
    _view(tester);
    await _pump(tester, const LoginScreen(), dark: true);
    await tester.enterText(find.byType(TextField).first, 'nick@');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Enter a valid email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    await _golden(tester, 'login_invalid_dark');
  });

  testWidgets('trouble signing in sheet', (tester) async {
    _view(tester);
    await _pump(tester, const LoginScreen(), dark: false);
    await tester.tap(find.text('Trouble signing in?'));
    await tester.pumpAndSettle();
    expect(find.text('Email support'), findsOneWidget);
    await _golden(tester, 'trouble_sheet');
  });
}
