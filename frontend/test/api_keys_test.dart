import 'package:app/core/constants/app_strings.dart';
import 'package:app/core/constants/api_keys.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/api_keys_api.dart';
import 'package:app/features/settings/api_keys/api_keys_controller.dart';
import 'package:app/features/settings/api_keys/api_keys_screen.dart';
import 'package:app/features/settings/api_keys/key_usage_screen.dart';
import 'package:app/features/settings/api_keys/keys_intro_screen.dart';
import 'package:app/features/settings/api_keys/usage_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/backdrop.dart';
import 'support/render.dart';
import 'support/shot.dart';

final _groqKey = 'gsk_${'a' * 24}';

class _FakeApi implements ApiKeysApi {
  _FakeApi({Map<String, SavedKey>? keys}) : keys = keys ?? {};

  final Map<String, SavedKey> keys;
  KeyCheck testResult = KeyCheck.valid;
  KeyCheck saveResult = KeyCheck.valid;
  final saved = <String, String>{};
  final removed = <String>[];
  final tested = <String>[];
  KeyUsage? usageData;

  static const _info = [
    ('groq', 'Groq', 'Very fast open models.'),
    ('openrouter', 'OpenRouter', 'One key, many models.'),
    ('nvidia', 'NVIDIA', 'NVIDIA-hosted models.'),
    ('ollama', 'Ollama Cloud', 'Ollama\'s hosted models.'),
  ];

  @override
  Future<KeysPage> list() async => KeysPage(
    providers: [
      for (final (id, name, blurb) in _info)
        KeyProviderInfo(
          id: id,
          name: name,
          blurb: blurb,
          keyUrl: 'https://example.com/$id',
          placeholder: 'key…',
          key: keys[id],
        ),
    ],
    hasValidKey: keys.values.any((k) => k.status == KeyStatus.valid),
  );

  @override
  Future<KeyTestResult> save(String provider, String key) async {
    saved[provider] = key;
    final status = switch (saveResult) {
      KeyCheck.valid => KeyStatus.valid,
      KeyCheck.invalid => KeyStatus.invalid,
      KeyCheck.quota => KeyStatus.quota,
      KeyCheck.network => KeyStatus.untested,
    };
    keys[provider] = SavedKey(
      hint: key.substring(key.length - 4),
      status: status,
    );
    return KeyTestResult(result: saveResult, key: keys[provider]);
  }

  @override
  Future<KeyTestResult> test(String provider) async {
    tested.add(provider);
    return KeyTestResult(result: testResult);
  }

  @override
  Future<void> remove(String provider) async {
    removed.add(provider);
    keys.remove(provider);
  }

  @override
  Future<KeyUsage> usage(int days) async => usageData ?? _usage(days);
}

KeyUsage _usage(int days) => KeyUsage(
  days: days,
  requests: 42,
  errors: 3,
  tokens: 18400,
  avgLatencyMs: 820,
  byDay: [
    for (var i = 0; i < days; i++)
      UsageBucket(
        label: DateTime(2026, 10, 13)
            .subtract(Duration(days: days - 1 - i))
            .toIso8601String()
            .substring(0, 10),
        requests: (i * 7) % 11,
        tokens: 100,
        errors: i == 3 ? 1 : 0,
      ),
  ],
  byModel: const [
    UsageBucket(
      label: 'openai/gpt-oss-20b',
      provider: 'groq',
      requests: 30,
      tokens: 12000,
      errors: 1,
      avgLatencyMs: 600,
    ),
    UsageBucket(
      label: 'nvidia/nemotron-3-super-120b-a12b',
      provider: 'nvidia',
      requests: 12,
      tokens: 6400,
      errors: 2,
      avgLatencyMs: 1500,
    ),
  ],
  byProvider: const [
    UsageBucket(label: 'groq', requests: 30, tokens: 12000, errors: 1),
    UsageBucket(label: 'nvidia', requests: 12, tokens: 6400, errors: 2),
  ],
);

ApiKeysController _controller(_FakeApi api) =>
    ApiKeysController(api: api, userId: 'u1');

const _valid = SavedKey(hint: 'a1b2', status: KeyStatus.valid);

/// Lets flutter_svg decode logos and the illustration.
Future<void> _settleArt(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _open(
  WidgetTester tester,
  _FakeApi api, {
  bool introSeen = true,
  ThemeData? theme,
  double height = 1400,
}) async {
  SharedPreferences.setMockInitialValues({
    if (introSeen) ApiKeysPrefs.introSeen('u1'): true,
  });
  await pumpScreen(
    tester,
    ApiKeysScreen(controller: _controller(api)),
    height: height,
    theme: theme,
  );
  await _settleArt(tester);
}

void main() {
  setUpAll(() async {
    Haptics.enabled = false;
    await loadAppFonts();
  });

  group('keys page', () {
    testWidgets('lists providers with real logos and an Add key action', (
      tester,
    ) async {
      await _open(tester, _FakeApi());
      expect(find.text('Groq'), findsOneWidget);
      expect(find.text('Ollama Cloud'), findsOneWidget);
      expect(find.text(ApiKeysStrings.add), findsNWidgets(4));
      expect(find.text(ApiKeysStrings.usageTitle), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows status chip and key hint, never the key', (
      tester,
    ) async {
      await _open(
        tester,
        _FakeApi(
          keys: {
            'groq': _valid,
            'nvidia': const SavedKey(hint: 'zzzz', status: KeyStatus.invalid),
            'openrouter': const SavedKey(hint: 'qqqq', status: KeyStatus.quota),
          },
        ),
      );
      expect(find.text(ApiKeysStrings.endsWith('a1b2')), findsOneWidget);
      expect(find.text(ApiKeysStrings.statusValid), findsOneWidget);
      expect(find.text(ApiKeysStrings.statusInvalid), findsOneWidget);
      expect(find.text(ApiKeysStrings.statusQuota), findsOneWidget);
      // A valid key opens the usage entry.
      expect(find.text(ApiKeysStrings.usageTitle), findsOneWidget);
    });

    testWidgets('Test shows the live result for each outcome', (tester) async {
      final api = _FakeApi(keys: {'groq': _valid});
      await _open(tester, api);
      for (final (result, text) in [
        (KeyCheck.valid, ApiKeysStrings.resultValid),
        (KeyCheck.invalid, ApiKeysStrings.resultInvalid),
        (KeyCheck.quota, ApiKeysStrings.resultQuota),
        (KeyCheck.network, ApiKeysStrings.resultNetwork),
      ]) {
        api.testResult = result;
        await tester.tap(find.byKey(const ValueKey('test-groq')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const ValueKey('result-groq')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('result-groq'))).data,
          text,
          reason: '$result',
        );
      }
      expect(api.tested, hasLength(4));
      // A rejected key flips the chip; a network failure leaves it alone.
      expect(find.text(ApiKeysStrings.statusQuota), findsOneWidget);
    });

    testWidgets('add: hidden field, paste, save runs the test and closes', (
      tester,
    ) async {
      final api = _FakeApi();
      await _open(tester, api);
      await tester.tap(find.byKey(const ValueKey('add-groq')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('key-field')),
      );
      expect(field.obscureText, isTrue);
      await tester.enterText(find.byKey(const ValueKey('key-field')), _groqKey);
      await tester.tap(find.byKey(const ValueKey('key-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.saved['groq'], _groqKey);
      expect(find.byKey(const ValueKey('key-field')), findsNothing);
      expect(find.text(ApiKeysStrings.endsWith('aaaa')), findsOneWidget);
      expect(find.text(ApiKeysStrings.statusValid), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('add: a rejected key keeps the sheet open with friendly copy', (
      tester,
    ) async {
      final api = _FakeApi()..saveResult = KeyCheck.invalid;
      await _open(tester, api);
      await tester.tap(find.byKey(const ValueKey('add-groq')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byKey(const ValueKey('key-field')), _groqKey);
      await tester.tap(find.byKey(const ValueKey('key-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('key-field')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('key-message'))).data,
        ApiKeysStrings.resultInvalid,
      );
    });

    testWidgets('add: a too-short key is refused before any call', (
      tester,
    ) async {
      final api = _FakeApi();
      await _open(tester, api);
      await tester.tap(find.byKey(const ValueKey('add-groq')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byKey(const ValueKey('key-field')), 'abc');
      await tester.tap(find.byKey(const ValueKey('key-save')));
      await tester.pump();
      expect(find.text(ApiKeysStrings.badFormat), findsOneWidget);
      expect(api.saved, isEmpty);
    });

    testWidgets('remove asks first, then deletes', (tester) async {
      final api = _FakeApi(keys: {'groq': _valid});
      await _open(tester, api);
      await tester.tap(find.byKey(const ValueKey('remove-groq')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(ApiKeysStrings.removeTitle), findsOneWidget);
      // Cancel keeps it.
      await tester.tap(find.text(AppStrings.cancel));
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.removed, isEmpty);
      await tester.tap(find.byKey(const ValueKey('remove-groq')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.widgetWithText(FilledButton, ApiKeysStrings.remove),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.removed, ['groq']);
      expect(find.byKey(const ValueKey('add-groq')), findsOneWidget);
      expect(find.text(ApiKeysStrings.usageTitle), findsNothing);
    });
  });

  group('intro', () {
    testWidgets('shows on first open only', (tester) async {
      final api = _FakeApi();
      await _open(tester, api, introSeen: false);
      expect(find.byType(KeysIntroScreen), findsOneWidget);
      expect(find.text(ApiKeysIntroStrings.useTitle), findsOneWidget);

      // Leave and open again: the choice was remembered.
      await tester.tap(find.text(ApiKeysIntroStrings.skip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(KeysIntroScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await pumpScreen(
        tester,
        ApiKeysScreen(controller: _controller(api)),
        height: 1400,
      );
      await _settleArt(tester);
      expect(find.byType(KeysIntroScreen), findsNothing);
    });

    testWidgets('Skip closes it without opening the add sheet', (tester) async {
      await _open(tester, _FakeApi(), introSeen: false);
      await tester.tap(find.text(ApiKeysIntroStrings.skip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(KeysIntroScreen), findsNothing);
      expect(find.byKey(const ValueKey('key-field')), findsNothing);
    });

    testWidgets('Next walks the three pages; Add a key opens the sheet', (
      tester,
    ) async {
      await _open(tester, _FakeApi(), introSeen: false);
      for (final title in [
        ApiKeysIntroStrings.privateTitle,
        ApiKeysIntroStrings.usageTitle,
      ]) {
        await tester.tap(find.text(ApiKeysIntroStrings.next));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text(ApiKeysIntroStrings.skip), findsOneWidget);
      await tester.tap(find.text(ApiKeysIntroStrings.done));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(KeysIntroScreen), findsNothing);
      expect(find.byKey(const ValueKey('key-field')), findsOneWidget);
    });

    testWidgets('How it works reopens it', (tester) async {
      await _open(tester, _FakeApi());
      expect(find.byType(KeysIntroScreen), findsNothing);
      await tester.tap(find.byKey(const ValueKey('how-link')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(KeysIntroScreen), findsOneWidget);
    });
  });

  group('usage', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        ApiKeysPrefs.usageIntroSeen('u1'): true,
      }),
    );

    testWidgets('renders the user\'s own numbers', (tester) async {
      await pumpScreen(
        tester,
        KeyUsageScreen(api: _FakeApi(), userId: 'u1'),
        height: 1700,
      );
      await _settleArt(tester);
      expect(find.text(KeyUsageStrings.byDay), findsOneWidget);
      expect(find.text(KeyUsageStrings.byModel), findsOneWidget);
      expect(find.text('gpt-oss-20b'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('30 days reloads; empty usage shows the empty state', (
      tester,
    ) async {
      final api = _FakeApi()
        ..usageData = const KeyUsage(
          days: 7,
          requests: 0,
          errors: 0,
          tokens: 0,
          byDay: [],
          byModel: [],
          byProvider: [],
        );
      await pumpScreen(
        tester,
        KeyUsageScreen(api: api, userId: 'u1'),
        height: 1000,
      );
      await _settleArt(tester);
      expect(find.text(KeyUsageStrings.empty), findsOneWidget);
      await tester.tap(find.text(KeyUsageStrings.days30));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(KeyUsageStrings.empty), findsOneWidget);
    });
  });

  group('usage intro', () {
    Future<void> openUsage(WidgetTester tester, {bool seen = false}) async {
      SharedPreferences.setMockInitialValues({
        if (seen) ApiKeysPrefs.usageIntroSeen('u1'): true,
      });
      await pumpScreen(
        tester,
        KeyUsageScreen(api: _FakeApi(), userId: 'u1'),
        height: 1400,
      );
      await _settleArt(tester);
    }

    testWidgets('shows on first open only', (tester) async {
      await openUsage(tester);
      expect(find.byType(UsageIntroScreen), findsOneWidget);
      expect(find.text(UsageIntroStrings.analyticsTitle), findsOneWidget);
      await tester.tap(find.text(UsageIntroStrings.skip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(UsageIntroScreen), findsNothing);

      // Opened again (same prefs): it was remembered.
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(
        tester,
        KeyUsageScreen(api: _FakeApi(), userId: 'u1'),
        height: 1400,
      );
      await _settleArt(tester);
      expect(find.byType(UsageIntroScreen), findsNothing);
    });

    testWidgets('is remembered per user', (tester) async {
      SharedPreferences.setMockInitialValues({
        ApiKeysPrefs.usageIntroSeen('someone-else'): true,
      });
      await pumpScreen(
        tester,
        KeyUsageScreen(api: _FakeApi(), userId: 'u1'),
        height: 1400,
      );
      await _settleArt(tester);
      expect(find.byType(UsageIntroScreen), findsOneWidget);
    });

    testWidgets('Skip closes it and the numbers are there', (tester) async {
      await openUsage(tester);
      await tester.tap(find.text(UsageIntroStrings.skip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(UsageIntroScreen), findsNothing);
      expect(find.text(KeyUsageStrings.byDay), findsOneWidget);
    });

    testWidgets('Next walks the three pages; See my usage closes it', (
      tester,
    ) async {
      await openUsage(tester);
      for (final title in [
        UsageIntroStrings.onlyYoursTitle,
        UsageIntroStrings.workTitle,
      ]) {
        await tester.tap(find.text(UsageIntroStrings.next));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text(title), findsOneWidget);
      }
      await tester.tap(find.text(UsageIntroStrings.done));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(UsageIntroScreen), findsNothing);
      expect(find.text(KeyUsageStrings.byDay), findsOneWidget);
    });

    testWidgets('the info icon reopens it', (tester) async {
      await openUsage(tester, seen: true);
      expect(find.byType(UsageIntroScreen), findsNothing);
      await tester.tap(find.byKey(const ValueKey('usage-how-it-works')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(UsageIntroScreen), findsOneWidget);
    });
  });

  group('goldens', () {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      final data = dark ? AppTheme.dark : AppTheme.light;

      for (final (i, name) in ['use', 'private', 'usage'].indexed) {
        testWidgets('intro $name ($theme)', (tester) async {
          tester.view.physicalSize = const Size(412 * 2.6, 915 * 2.6);
          tester.view.devicePixelRatio = 2.6;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: data,
              home: const KeysIntroScreen(),
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
          for (var n = 0; n < i; n++) {
            await tester.tap(find.text(ApiKeysIntroStrings.next));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 800));
          }
          await _settleArt(tester);
          await settleBackdrop(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/api_keys_intro_${name}_$theme.png'),
          );
        });
      }

      for (final (i, name) in ['analytics', 'only_yours', 'work'].indexed) {
        testWidgets('usage intro $name ($theme)', (tester) async {
          tester.view.physicalSize = const Size(412 * 2.6, 915 * 2.6);
          tester.view.devicePixelRatio = 2.6;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: data,
              home: const UsageIntroScreen(),
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
          for (var n = 0; n < i; n++) {
            await tester.tap(find.text(UsageIntroStrings.next));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 800));
          }
          await _settleArt(tester);
          await settleBackdrop(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/usage_intro_${name}_$theme.png'),
          );
        });
      }

      testWidgets('keys page ($theme)', (tester) async {
        await _open(
          tester,
          _FakeApi(
            keys: {
              'groq': _valid,
              'nvidia': const SavedKey(hint: 'zzzz', status: KeyStatus.invalid),
              'openrouter': const SavedKey(
                hint: 'qqqq',
                status: KeyStatus.quota,
              ),
            },
          ),
          theme: data,
          height: 915,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/api_keys_page_$theme.png'),
        );
      });

      testWidgets('usage ($theme)', (tester) async {
        SharedPreferences.setMockInitialValues({
          ApiKeysPrefs.usageIntroSeen('u1'): true,
        });
        await pumpScreen(
          tester,
          KeyUsageScreen(api: _FakeApi(), userId: 'u1'),
          theme: data,
          height: 1500,
        );
        await _settleArt(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/api_keys_usage_$theme.png'),
        );
      });
    }
  });
}
