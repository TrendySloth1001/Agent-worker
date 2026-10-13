import 'support/backdrop.dart';
import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/about.dart';
import 'package:app/core/constants/changelog.dart';
import 'package:app/core/constants/m3_copy.dart';
import 'package:app/core/constants/notify_copy.dart';
import 'package:app/core/constants/onboarding.dart';
import 'package:app/core/constants/settings_copy.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/auth_models.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/about/about_screen.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:app/features/settings/widgets/developer_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _baseUrl = 'https://sparky.example.dev';

/// Serves a healthy (or unreachable) server with a few providers.
class _FakeUsageApi extends UsageApi {
  _FakeUsageApi({this.reachable = true}) : super(_baseUrl);

  final bool reachable;

  @override
  Future<UsageSnapshot> fetchUsage() async {
    if (!reachable) throw Exception('offline');
    return UsageSnapshot.fromJson({
      'totals': {'requestsToday': 214, 'tokensToday': 182000},
      'providers': [
        for (final (id, name) in [
          ('groq', 'Groq'),
          ('ollama', 'Ollama Cloud'),
          ('nvidia', 'NVIDIA'),
          ('openrouter', 'OpenRouter'),
        ])
          {
            'id': id,
            'name': name,
            'configured': true,
            'keyHint': 'sk-…a1b2',
            'status': 'ok',
            'today': {'requests': 40, 'tokens': 30000},
          },
      ],
      'services': {
        'kb': {'sources': 12, 'chunks': 340},
      },
    });
  }

  @override
  Future<HealthStatus> fetchHealth() async {
    if (!reachable) throw Exception('offline');
    return const HealthStatus('ok', db: 'ok', embeddings: 'ok');
  }
}

const _user = AuthUser(
  id: 'u1',
  email: 'maya@example.com',
  name: 'Maya Patel',
  role: 'user',
);
const _owner = AuthUser(
  id: 'o1',
  email: 'nick@example.com',
  name: 'Nick Kumawat',
  role: 'owner',
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

Future<SettingsController> _pump(
  WidgetTester tester,
  Widget home, {
  required AuthUser user,
  bool dark = false,
  bool reachable = true,
}) async {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  AuthController.instance.user = user;
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'sparky',
    packageName: 'com.sparky.app',
    version: '1.5.3',
    buildNumber: '22',
    buildSignature: '',
  );
  final settings = await SettingsController.load();
  final usage = UsageController(_FakeUsageApi(reachable: reachable));
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      usage: usage,
      api: ChatApi(),
      baseUrl: _baseUrl,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: home,
      ),
    ),
  );
  await usage.refresh();
  await _settle(tester);
  return settings;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.ensureVisible(target);
  await _settle(tester);
}

AppScope _scope(WidgetTester tester) =>
    AppScope.of(tester.element(find.byType(MaterialApp)));

/// Words a normal user should never meet anywhere in Settings.
const _devWords = [
  'server',
  'backend',
  'telemetry',
  'tokens',
  'quota',
  'providers',
  'latency',
  'database',
  'embeddings',
];

void main() {
  setUpAll(() async {
    await _fonts();
    Haptics.enabled = false;
  });
  tearDown(() => AuthController.instance.user = null);

  group('Settings root', () {
    testWidgets('a user sees no developer entries', (tester) async {
      await _pump(tester, const SettingsScreen(), user: _user);
      await _scrollTo(tester, find.text(SettingsStrings.reset));
      expect(find.text(SettingsStrings.catServer), findsNothing);
      expect(find.text(SettingsStrings.catTelemetry), findsNothing);
      expect(find.byType(DeveloperSection), findsNothing);
      expect(find.text(SettingsStrings.unreachableTitle), findsNothing);
      // The model summary has no provider count.
      expect(
        find.textContaining(SettingsStrings.providersActive),
        findsNothing,
      );
      expect(find.text(SettingsStrings.modelAuto), findsOneWidget);
      for (final w in _devWords) {
        expect(searchSettings(w, _scope(tester)), isEmpty, reason: w);
      }
    });

    testWidgets('the owner has a collapsible Developer section', (
      tester,
    ) async {
      await _pump(tester, const SettingsScreen(), user: _owner);
      await _scrollTo(tester, find.text(SettingsStrings.developerShow));
      expect(find.text(SettingsStrings.catTelemetry), findsNothing);
      await tester.tap(find.text(SettingsStrings.developerShow));
      await _settle(tester);
      await _scrollTo(tester, find.text(SettingsStrings.catTelemetry));
      expect(find.text(SettingsStrings.catServer), findsOneWidget);
      expect(find.text(SettingsStrings.catTelemetry), findsOneWidget);
      expect(find.text(SettingsStrings.developerHide), findsOneWidget);
      expect(
        find.textContaining(SettingsStrings.providersActive),
        findsOneWidget,
      );
      expect(searchSettings('telemetry', _scope(tester)), isNotEmpty);
      expect(searchSettings('backend', _scope(tester)), isNotEmpty);
    });

    testWidgets('a problem shows one plain notice, with no jargon', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsScreen(),
        user: _user,
        reachable: false,
      );
      expect(find.text(SettingsStrings.unreachableTitle), findsOneWidget);
      expect(find.text(SettingsStrings.tryAgain), findsOneWidget);
      expect(find.textContaining('OFFLINE'), findsNothing);
      expect(find.textContaining('Offline'), findsNothing);
    });
  });

  group('Models page', () {
    testWidgets('a user only picks a model', (tester) async {
      final settings = await _pump(
        tester,
        const SettingsCategoryPage(category: SettingsCategory.models),
        user: _user,
      );
      settings.setModelChoice('ollama:gemma4:31b');
      await _settle(tester);
      expect(find.text(SettingsStrings.secModel), findsOneWidget);
      expect(find.text(SettingsStrings.secUsage), findsNothing);
      expect(find.text(SettingsStrings.secProviders), findsNothing);
      expect(find.text(SettingsStrings.secServices), findsNothing);
      // A friendly name, never the raw id.
      expect(find.text('ollama:gemma4:31b'), findsNothing);
      expect(find.text('Gemma4 31b'), findsOneWidget);
      settings.setModelChoice('ollama:gemma4:31b', name: 'Gemma 4');
      await _settle(tester);
      expect(find.text('Gemma 4'), findsOneWidget);
    });

    testWidgets('the owner keeps usage, providers and raw ids', (tester) async {
      final settings = await _pump(
        tester,
        const SettingsCategoryPage(category: SettingsCategory.models),
        user: _owner,
      );
      settings.setModelChoice('ollama:gemma4:31b', name: 'Gemma 4');
      await _settle(tester);
      expect(find.text('ollama:gemma4:31b'), findsOneWidget);
      await _scrollTo(tester, find.text(SettingsStrings.secUsage));
      await _scrollTo(tester, find.text(SettingsStrings.secProviders));
      expect(find.text(SettingsStrings.secProviders), findsOneWidget);
    });
  });

  testWidgets('quota alerts are only offered to the owner', (tester) async {
    await _pump(
      tester,
      const SettingsCategoryPage(category: SettingsCategory.notifications),
      user: _user,
    );
    expect(
      searchSettings(NotifyCopy.usageLabel.toLowerCase(), _scope(tester)),
      isEmpty,
    );
    AuthController.instance.user = _owner;
    await _settle(tester);
    expect(
      searchSettings(NotifyCopy.usageLabel.toLowerCase(), _scope(tester)),
      isNotEmpty,
    );
  });

  group('About', () {
    testWidgets('a user sees the simple page', (tester) async {
      await _pump(tester, const AboutScreen(), user: _user);
      expect(find.text(AboutStrings.heroVersion('1.5.3')), findsOneWidget);
      for (final t in [
        ChangelogStrings.entry,
        OnboardingStrings.takeTour,
        AboutStrings.privacyPolicy,
        AboutStrings.terms,
        AboutCopy.licenses,
        AboutCopy.feedback,
      ]) {
        await _scrollTo(tester, find.text(t));
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await _scrollTo(tester, find.text(AboutStrings.madeWith));
      expect(find.text(_baseUrl), findsNothing);
      expect(find.textContaining('(22)'), findsNothing);
      expect(find.byType(DeveloperSection), findsNothing);
      expect(find.text(AboutCopy.backend), findsNothing);
      expect(find.text(AboutCopy.whatItDoes), findsNothing);
      expect(find.textContaining('Groq'), findsNothing);
    });

    testWidgets('the owner gets the Developer section', (tester) async {
      await _pump(tester, const AboutScreen(), user: _owner);
      expect(find.text(AboutStrings.heroVersion('1.5.3')), findsOneWidget);
      await _scrollTo(tester, find.text(SettingsStrings.developerShow));
      await tester.tap(find.text(SettingsStrings.developerShow));
      await _settle(tester);
      await _scrollTo(tester, find.text(AboutStrings.telemetry));
      expect(find.text(_baseUrl), findsOneWidget);
      expect(find.text(AboutCopy.status), findsOneWidget);
      expect(find.text(AboutStrings.buildTitle), findsOneWidget);
      expect(find.text(AboutStrings.telemetry), findsOneWidget);
    });
  });

  group('goldens', () {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('settings root, user ($theme)', (tester) async {
        await _pump(tester, const SettingsScreen(), user: _user, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_root_user_$theme.png'),
        );
      });

      testWidgets('settings root, owner ($theme)', (tester) async {
        await _pump(tester, const SettingsScreen(), user: _owner, dark: dark);
        await _scrollTo(tester, find.text(SettingsStrings.developerShow));
        await tester.tap(find.text(SettingsStrings.developerShow));
        await _settle(tester);
        await _scrollTo(tester, find.text(SettingsStrings.reset));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_root_owner_$theme.png'),
        );
      });

      testWidgets('settings root, unreachable ($theme)', (tester) async {
        await _pump(
          tester,
          const SettingsScreen(),
          user: _user,
          dark: dark,
          reachable: false,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_root_unreachable_$theme.png'),
        );
      });

      testWidgets('about, user ($theme)', (tester) async {
        await _pump(tester, const AboutScreen(), user: _user, dark: dark);
        await settleBackdrop(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/about_user_$theme.png'),
        );
      });

      testWidgets('about, owner ($theme)', (tester) async {
        await _pump(tester, const AboutScreen(), user: _owner, dark: dark);
        await _scrollTo(tester, find.text(SettingsStrings.developerShow));
        await tester.tap(find.text(SettingsStrings.developerShow));
        await _settle(tester);
        await _scrollTo(tester, find.text(AboutStrings.madeWith));
        await settleBackdrop(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/about_owner_$theme.png'),
        );
      });
    }
  });
}
