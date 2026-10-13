import 'support/backdrop.dart';
import 'package:app/assist/assistant_setup.dart';
import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/onboarding.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/auth_models.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/about/about_screen.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/chat/chat_launch.dart';
import 'package:app/features/onboarding/onboarding_gate.dart';
import 'package:app/features/onboarding/onboarding_screen.dart';
import 'package:app/features/onboarding/onboarding_store.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:app/features/settings/widgets/reply_style_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSetup extends AssistantSetup {
  _FakeSetup();

  bool isDefault = false;
  int requests = 0;

  @override
  Future<AssistantStatus> status() async =>
      AssistantStatus(isDefault: isDefault, manufacturer: 'Nothing');

  @override
  Future<String> request() async {
    requests++;
    isDefault = true;
    return 'granted';
  }
}

const _home = Text('HOME');

AuthUser _user({bool? onboarded}) => AuthUser(
  id: 'u-1',
  email: 'nikhil@example.com',
  name: 'Nikhil Kumawat',
  role: 'user',
  onboarded: onboarded,
);

class _Remote {
  final calls = <bool>[];
  Future<AuthUser?> call(bool done) async {
    calls.add(done);
    return null;
  }
}

OnboardingStore _store({bool hasChats = false, _Remote? remote}) =>
    OnboardingStore(
      hasChats: () async => hasChats,
      remote: (remote ?? _Remote()).call,
    );

Future<void> _fonts() async {
  for (final (family, files) in [
    ('SpaceGrotesk', ['SpaceGrotesk.ttf']),
    ('SpaceMono', ['SpaceMono-Regular.ttf', 'SpaceMono-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
}

/// Lets flutter_svg decode the illustration and the logos.
Future<void> _settleArt(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<SettingsController> _pump(
  WidgetTester tester,
  Widget home, {
  bool dark = false,
  Size size = const Size(412, 915),
  double ratio = 2.6,
}) async {
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final settings = await SettingsController.load();
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      usage: UsageController(UsageApi('http://localhost:1')),
      api: ChatApi(),
      baseUrl: 'http://localhost:1',
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return settings;
}

/// Finishing writes storage (real async), then the gate cross-fades.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _next(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text(OnboardingStrings.next));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }
}

void main() {
  setUpAll(() async {
    await _fonts();
    Haptics.enabled = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthController.instance.user = _user(onboarded: false);
  });

  group('store', () {
    test('server flag decides; local flag wins and re-syncs', () async {
      final remote = _Remote();
      final store = _store(remote: remote);
      expect(await store.need(_user(onboarded: false)), TourNeed.show);
      expect(await store.need(_user(onboarded: true)), TourNeed.skip);
      // The server's true is cached per account.
      expect(await store.need(_user(onboarded: false)), TourNeed.skip);
      expect(remote.calls, [true]);
      expect(await store.need(_user()), TourNeed.skip);
    });

    test('older server: chats mean onboarded, none mean new', () async {
      expect(await _store(hasChats: true).resolveUnknown(_user()), isFalse);
      expect(await _store(hasChats: true).need(_user()), TourNeed.skip);
      SharedPreferences.setMockInitialValues({});
      expect(await _store().need(_user()), TourNeed.unknown);
      expect(await _store().resolveUnknown(_user()), isTrue);
      final failing = OnboardingStore(
        hasChats: () async => throw Exception('offline'),
        remote: _Remote().call,
      );
      expect(await failing.resolveUnknown(_user()), isFalse);
    });

    test('flag is per account', () async {
      final store = _store();
      await store.markDone(_user(onboarded: false));
      expect(await store.need(_user(onboarded: false)), TourNeed.skip);
      const other = AuthUser(
        id: 'u-2',
        email: 'b@example.com',
        name: 'B',
        role: 'user',
        onboarded: false,
      );
      expect(await store.need(other), TourNeed.show);
    });
  });

  group('gate', () {
    testWidgets('a new account sees the tour once', (tester) async {
      final remote = _Remote();
      final store = _store(remote: remote);
      await _pump(
        tester,
        OnboardingGate(
          user: _user(onboarded: false),
          store: store,
          child: _home,
        ),
      );
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text(OnboardingStrings.hello('Nikhil')), findsOneWidget);
      expect(find.text('HOME'), findsNothing);

      await tester.tap(find.text(OnboardingStrings.skip));
      await _settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(remote.calls, [true]);
      expect(AuthController.instance.user?.onboarded, isTrue);

      // Signing in again on this phone: straight to the chat.
      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        OnboardingGate(
          user: _user(onboarded: false),
          store: store,
          child: _home,
        ),
      );
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('a returning account goes straight to the chat', (
      tester,
    ) async {
      await _pump(
        tester,
        OnboardingGate(
          user: _user(onboarded: true),
          store: _store(),
          child: _home,
        ),
      );
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('older server with chats: no tour', (tester) async {
      await _pump(
        tester,
        OnboardingGate(
          user: _user(),
          store: _store(hasChats: true),
          child: _home,
        ),
      );
      expect(find.text('HOME'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('finishing saves the picks and lands on the chat', (
      tester,
    ) async {
      final settings = await _pump(
        tester,
        OnboardingGate(
          user: _user(onboarded: false),
          store: _store(),
          child: _home,
        ),
      );
      await _next(tester, 5);
      expect(find.text(OnboardingStrings.start), findsOneWidget);
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, 'Nikhil');
      await tester.enterText(field, 'Nick');
      await tester.tap(find.text('Straight to the point'));
      await tester.pump();
      await tester.tap(find.text(OnboardingStrings.start));
      await _settle(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(settings.name, 'Nick');
      final direct = replyPresets.firstWhere((p) => p.id == 'direct');
      expect(settings.tone, direct.tone);
      expect(settings.length, direct.length);
    });

    testWidgets('back steps through pages; set assistant works', (
      tester,
    ) async {
      final setup = _FakeSetup();
      var done = 0;
      await _pump(
        tester,
        OnboardingScreen(
          setup: setup,
          showAssistantSetup: true,
          onDone: () async => done++,
        ),
      );
      await _next(tester, 4);
      expect(find.text(OnboardingStrings.assistTitle), findsOneWidget);
      await tester.tap(find.text(OnboardingStrings.assistCta));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(setup.requests, 1);
      expect(find.text(OnboardingStrings.assistDone), findsOneWidget);

      // System back goes to the previous page, not out of the tour.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text(OnboardingStrings.appsTitle), findsOneWidget);
      await tester.tap(find.text(OnboardingStrings.back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text(OnboardingStrings.knowTitle), findsOneWidget);
      expect(done, 0);
    });
  });

  testWidgets('About → Take the tour reopens it and ends on a new chat', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'sparky',
      packageName: 'com.sparky.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    AuthController.instance.user = _user(onboarded: true);
    OnboardingStore.instance = _store();
    final fresh = ChatLaunch.instance.fresh.value;
    await _pump(tester, const AboutScreen(), size: const Size(412, 915));
    final tour = find.text(OnboardingStrings.takeTour);
    await tester.scrollUntilVisible(
      tour,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(tour);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tester.tap(find.text(OnboardingStrings.skip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(ChatLaunch.instance.fresh.value, fresh + 1);
  });

  group('goldens', () {
    const pages = ['welcome', 'ask', 'knowledge', 'apps', 'assistant', 'yours'];
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      for (final (i, name) in pages.indexed) {
        testWidgets('tour $name ($theme)', (tester) async {
          await _pump(
            tester,
            OnboardingScreen(
              setup: _FakeSetup(),
              showAssistantSetup: true,
              onDone: () async {},
            ),
            dark: dark,
          );
          await _next(tester, i);
          await _settleArt(tester);
          expect(tester.takeException(), isNull);
          await settleBackdrop(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/onboarding_${name}_$theme.png'),
          );
        });
      }
    }

    for (final (i, name) in [(0, 'welcome'), (1, 'ask'), (5, 'yours')]) {
      testWidgets('tour $name at 360x740 fits', (tester) async {
        await _pump(
          tester,
          OnboardingScreen(
            setup: _FakeSetup(),
            showAssistantSetup: true,
            onDone: () async {},
          ),
          size: const Size(360, 740),
          ratio: 3,
        );
        await _next(tester, i);
        await _settleArt(tester);
        // Scroll the page through; any overflow throws.
        final list = find.byType(SingleChildScrollView).last;
        await tester.drag(list, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await tester.drag(list, const Offset(0, 600));
        await tester.pump(const Duration(milliseconds: 100));
        if (name == 'ask') {
          await settleBackdrop(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/onboarding_ask_360.png'),
          );
        }
      });
    }

    testWidgets('large text at 360x740 does not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        OnboardingScreen(
          setup: _FakeSetup(),
          showAssistantSetup: true,
          onDone: () async {},
        ),
        size: const Size(360, 740),
        ratio: 3,
      );
      for (var i = 0; i < OnboardingSizes.pages; i++) {
        final list = find.byType(SingleChildScrollView).last;
        await tester.drag(list, const Offset(0, -900));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        if (i < OnboardingSizes.pages - 1) await _next(tester, 1);
      }
    });
  });
}
