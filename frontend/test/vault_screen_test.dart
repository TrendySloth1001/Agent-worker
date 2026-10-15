import 'package:app/core/constants/vault.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/vault/vault_api.dart';
import 'package:app/data/chat_api.dart' show ApiException;
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/vault/vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';

const _key = 'dGhpcy1pcy1hLXRlc3QtZGF0YS1rZXktMzItYnl0ZXM=';
final _now = DateTime(2026, 10, 22, 12);

class FakeVaultApi implements VaultApi {
  FakeVaultApi(this.status0);
  VaultStatus status0;
  final calls = <String>[];
  Object? revealError;

  @override
  Future<VaultStatus> status() async {
    calls.add('status');
    return status0;
  }

  @override
  Future<VaultStatus> seed(String password) async {
    calls.add('seed:$password');
    return status0 = VaultStatus(exists: true, updatedAt: _now);
  }

  @override
  Future<String> reveal(String password) async {
    calls.add('reveal:$password');
    if (revealError != null) throw revealError!;
    return _key;
  }
}

const _none = VaultStatus(exists: false);
final _sealed = VaultStatus(
  exists: true,
  updatedAt: _now.subtract(const Duration(days: 2)),
);
final _stale = VaultStatus(exists: true, updatedAt: _now, needsReseal: true);

Future<void> _pump(
  WidgetTester tester,
  FakeVaultApi api, {
  bool owner = true,
  bool hasPassword = true,
  List<bool>? secureLog,
  Future<void> Function(String)? saveFile,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: VaultScreen(
        api: api,
        owner: () => owner,
        hasPassword: () => hasPassword,
        now: () => _now,
        autoHide: const Duration(seconds: 3),
        clipboardClear: const Duration(seconds: 5),
        secure: (on) async => secureLog?.add(on),
        saveFile: saveFile,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _enterPassword(WidgetTester tester, String pw) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.enterText(find.byKey(const ValueKey('vault-password')), pw);
  await tester.tap(find.byKey(const ValueKey('input-ok')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    Haptics.enabled = false;
  });

  testWidgets('not set up: offers set up only, and seeds with the password', (
    tester,
  ) async {
    final api = FakeVaultApi(_none);
    await _pump(tester, api);
    expect(find.text(VaultStrings.notSetUp), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-reveal')), findsNothing);
    expect(find.text(VaultStrings.explain), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vault_not_set_up.png'),
    );
    await tester.tap(find.byKey(const ValueKey('vault-seed')));
    await tester.pump(const Duration(milliseconds: 400));
    await _enterPassword(tester, 'hunter22!');
    expect(api.calls, contains('seed:hunter22!'));
    expect(find.text(VaultStrings.sealed), findsOneWidget);
  });

  testWidgets('sealed: reveal shows the key blurred, then tap shows it', (
    tester,
  ) async {
    final api = FakeVaultApi(_sealed);
    final secure = <bool>[];
    await _pump(tester, api, secureLog: secure);
    expect(find.text(VaultStrings.sealed), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vault_sealed.png'),
    );
    await tester.tap(find.byKey(const ValueKey('vault-reveal')));
    await _enterPassword(tester, 'pw-123456');
    expect(api.calls, contains('reveal:pw-123456'));
    expect(secure, [true]);
    expect(find.text(VaultStrings.tapToShow), findsOneWidget);
    expect(find.byType(ImageFiltered), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vault_key_blurred.png'),
    );
    await tester.tap(find.byKey(const ValueKey('vault-key-box')));
    await tester.pump();
    expect(find.text(VaultStrings.tapToShow), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vault_key_shown.png'),
    );
    // Auto-hide: the key leaves the tree and the secure flag is cleared.
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('vault-key-text')), findsNothing);
    expect(secure, [true, false]);
  });

  testWidgets('copy puts the key on the clipboard, cleared later', (
    tester,
  ) async {
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return {'text': clip};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final api = FakeVaultApi(_sealed);
    String? saved;
    await _pump(tester, api, saveFile: (t) async => saved = t);
    await tester.tap(find.byKey(const ValueKey('vault-reveal')));
    await _enterPassword(tester, 'pw-123456');
    await tester.tap(find.byKey(const ValueKey('vault-copy')));
    await tester.pump();
    expect(clip, _key);
    await tester.tap(find.byKey(const ValueKey('vault-save')));
    await tester.pump();
    expect(saved, _key);
    await tester.pump(const Duration(seconds: 6));
    expect(clip, '');
  });

  testWidgets('wrong password shows an inline error and no key', (
    tester,
  ) async {
    final api = FakeVaultApi(_sealed)
      ..revealError = const ApiException(
        'x',
        status: 403,
        code: 'wrong_password',
      );
    await _pump(tester, api);
    await tester.tap(find.byKey(const ValueKey('vault-reveal')));
    await _enterPassword(tester, 'nope');
    expect(find.text(VaultStrings.wrongPassword), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-key-text')), findsNothing);
  });

  testWidgets('needs re-seal: says so and offers sealing again only', (
    tester,
  ) async {
    await _pump(tester, FakeVaultApi(_stale));
    expect(find.text(VaultStrings.needsReseal), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-reveal')), findsNothing);
    expect(find.text(VaultStrings.reSeal), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vault_needs_reseal.png'),
    );
  });

  testWidgets('owner without a password is told to set one in Profile', (
    tester,
  ) async {
    await _pump(tester, FakeVaultApi(_none), hasPassword: false);
    expect(find.text(VaultStrings.noPasswordTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-seed')), findsNothing);
    expect(find.byKey(const ValueKey('vault-reveal')), findsNothing);
  });

  testWidgets('a non-owner never loads or sees the vault', (tester) async {
    final api = FakeVaultApi(_sealed);
    await _pump(tester, api, owner: false);
    expect(api.calls, isEmpty);
    expect(find.text(VaultStrings.notOwner), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-reveal')), findsNothing);
  });

  testWidgets('VaultScreen.open does nothing for a non-owner', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await VaultScreen.open(ctx, owner: () => false);
    await tester.pump();
    expect(find.byType(VaultScreen), findsNothing);
  });

  test('settings: the vault entry is owner-only and direct', () {
    expect(SettingsCategory.vault.ownerOnly, isTrue);
    expect(SettingsCategory.vault.isDirect, isTrue);
    expect(SettingsCategory.vault.title, VaultStrings.entryTitle);
  });
}
