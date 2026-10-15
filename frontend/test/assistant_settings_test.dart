import 'package:app/assist/assistant_setup.dart';
import 'package:app/core/constants/app_prefs.dart';
import 'package:app/core/constants/assist.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/settings/assistant_settings_screen.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSetup extends AssistantSetup {
  FakeSetup(this.current);

  AssistantStatus current;
  int requests = 0, tries = 0;

  @override
  Future<AssistantStatus> status() async => current;

  @override
  Future<String> request() async {
    requests++;
    current = const AssistantStatus(
      isDefault: true,
      screenText: true,
      screenshot: false,
      manufacturer: 'Nothing',
    );
    return 'granted';
  }

  @override
  Future<void> tryIt() async => tries++;
}

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

void main() {
  setUpAll(() async {
    await _fonts();
    Haptics.enabled = false;
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('Settings > Assistant, not set up ($theme)', (tester) async {
      tester.view.physicalSize = const Size(412, 915) * 2.6;
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      final setup = FakeSetup(
        const AssistantStatus(isDefault: false, manufacturer: 'Nothing'),
      );
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsController.load();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: AssistantSettingsScreen(setup: setup, settings: settings),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AssistStrings.statusOffTitle), findsOneWidget);
      expect(find.text(AssistStrings.howNothingTitle), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/assistant_settings_$theme.png'),
      );

      await tester.tap(find.text(AssistStrings.setDefault));
      await tester.pumpAndSettle();
      expect(setup.requests, 1);
      expect(find.text(AssistStrings.statusOnTitle), findsOneWidget);
      await tester.tap(find.text(AssistStrings.tryIt));
      expect(setup.tries, 1);
    });
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('Settings > Assistant: features and switches ($theme)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915) * 2.6;
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsController.load();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: AssistantSettingsScreen(
            setup: FakeSetup(
              const AssistantStatus(isDefault: true, manufacturer: 'Nothing'),
            ),
            settings: settings,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(AssistStrings.secDo),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text(AssistStrings.secDo));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/assistant_settings_features_$theme.png'),
      );
      await tester.tap(find.text(AssistStrings.actionsTitle));
      await tester.pumpAndSettle();
      expect(settings.assistActions, isFalse);
      await tester.tap(find.text(AssistStrings.liveTitle));
      await tester.pumpAndSettle();
      expect(settings.assistLive, isFalse);
    });
  }

  testWidgets('sound on open switch: shown, default on, persists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    expect(settings.assistOpenSound, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AssistantSettingsScreen(
          setup: FakeSetup(
            const AssistantStatus(isDefault: true, manufacturer: 'Nothing'),
          ),
          settings: settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AssistStrings.soundTitle), findsOneWidget);
    await tester.tap(find.text(AssistStrings.soundTitle));
    await tester.pumpAndSettle();
    expect(settings.assistOpenSound, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppPrefs.assistOpenSound), isFalse);
    expect((await SettingsController.load()).assistOpenSound, isFalse);
  });
}
