import 'package:app/core/constants/update.dart';
import 'package:app/core/update/update_controller.dart';
import 'package:app/core/update/update_downloader.dart';
import 'package:app/core/update/update_installer.dart';
import 'package:app/core/update/update_models.dart';
import 'package:app/core/update/update_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/update_fakes.dart';

UpdateInfo _with(UpdateKind kind, {bool required = false, int build = 30}) =>
    UpdateInfo(
      current: 25,
      required: required,
      latest: fakeRelease(kind: kind, build: build),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('check', () {
    test('a feature update asks for the sheet and notifies once', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      expect(await r.controller.check(), UpdateCheck.available);
      expect(r.controller.prompt, UpdatePrompt.sheet);
      expect(r.controller.sheetDue, isTrue);
      expect(r.notified, [30]);
      await r.controller.check();
      expect(r.notified, [30], reason: 'once per version');
    });

    test('showing the sheet records it and quiets the prompt', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      await r.controller.check();
      await r.controller.markSheetShown();
      expect(r.controller.prompt, UpdatePrompt.dot);
      expect(r.controller.sheetDue, isFalse);
      // 3 days later (a new session): due again.
      r.now = r.now.add(const Duration(days: 3));
      final next = UpdateRig(
        info: _with(UpdateKind.feature),
        prefs: {
          'ota.promptedBuild': 30,
          'ota.promptCount': 1,
          'ota.nextPromptAt': r.now.millisecondsSinceEpoch,
        },
      )..now = r.now;
      await next.controller.check();
      expect(next.controller.prompt, UpdatePrompt.sheet);
    });

    test('suppressing the sheet keeps it from showing this session', () async {
      final r = UpdateRig(info: _with(UpdateKind.major));
      await r.controller.check();
      r.controller.suppressSheetThisSession();
      expect(r.controller.sheetDue, isFalse);
      expect(r.controller.hasUpdate, isTrue, reason: 'the dot stays');
    });

    test('critical blocks, and a patch only dots', () async {
      final c = UpdateRig(info: _with(UpdateKind.critical));
      await c.controller.check();
      expect(c.controller.blocking, isTrue);
      final p = UpdateRig(info: _with(UpdateKind.patch), wifi: false);
      await p.controller.check();
      expect(p.controller.blocking, isFalse);
      expect(p.controller.prompt, UpdatePrompt.dot);
      expect(p.notified, isEmpty);
    });

    test('a failed check is silent and leaves no update', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature))
        ..api.error = Exception('offline');
      expect(await r.controller.check(), UpdateCheck.failed);
      expect(r.controller.hasUpdate, isFalse);
      expect(r.controller.checking, isFalse);
    });

    test('up to date', () async {
      final r = UpdateRig();
      expect(await r.controller.check(), UpdateCheck.upToDate);
      expect(r.controller.everChecked, isTrue);
    });
  });

  group('scheduling', () {
    testWidgets('checks 3 seconds after start, and on resume after 6h', (
      tester,
    ) async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      r.controller.start();
      await tester.pump(const Duration(seconds: 2));
      expect(r.api.checks, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(r.api.checks, 1);

      // Back after 5 hours: too soon.
      r.now = r.now.add(const Duration(hours: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(r.api.checks, 1);

      // Another 2 hours: over 6 since the check.
      r.now = r.now.add(const Duration(hours: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(r.api.checks, 2);
      r.controller.dispose();
    });
  });

  group('download and install', () {
    test('a patch downloads by itself on Wi-Fi', () async {
      final r = UpdateRig(info: _with(UpdateKind.patch));
      await r.controller.check();
      await Future<void>.delayed(Duration.zero);
      expect(r.downloader.downloads, 1);
      expect(r.controller.phase, UpdatePhase.ready);
      expect(r.installer.installed, isEmpty, reason: 'waits for the tap');
    });

    test(
      'a patch waits off Wi-Fi, and goes anywhere with the switch off',
      () async {
        final off = UpdateRig(info: _with(UpdateKind.patch), wifi: false);
        await off.controller.check();
        expect(off.downloader.downloads, 0);
        final any = UpdateRig(
          info: _with(UpdateKind.patch),
          wifi: false,
          prefs: {'ota.wifiOnly': false},
        );
        await any.controller.check();
        await Future<void>.delayed(Duration.zero);
        expect(any.downloader.downloads, 1);
      },
    );

    test('a feature never downloads before the tap', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      await r.controller.check();
      expect(r.downloader.downloads, 0);
      expect(r.controller.phase, UpdatePhase.idle);
    });

    test('Update downloads then installs', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      await r.controller.check();
      final seen = <UpdatePhase>[];
      r.controller.addListener(() => seen.add(r.controller.phase));
      await r.controller.begin();
      expect(seen, contains(UpdatePhase.downloading));
      expect(seen, contains(UpdatePhase.installing));
      expect(r.installer.installed, ['/cache/30.apk']);
      expect(r.controller.phase, UpdatePhase.idle);
    });

    test('without the unknown-apps permission it asks, then resumes', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      r.installer.allowed = false;
      await r.controller.check();
      await r.controller.begin();
      expect(r.controller.phase, UpdatePhase.needsPermission);
      expect(r.installer.installed, isEmpty);
      await r.controller.openPermissionSettings();
      expect(r.installer.settingsOpened, 1);

      // The user came back having allowed it.
      r.installer.allowed = true;
      r.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(r.installer.installed, ['/cache/30.apk']);
    });

    test('coming back without allowing it stays on the step', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      r.installer.allowed = false;
      await r.controller.check();
      await r.controller.begin();
      r.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(r.controller.phase, UpdatePhase.needsPermission);
      r.controller.cancelPermission();
      expect(r.controller.phase, UpdatePhase.ready);
    });

    test('a download that fails can be retried', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      r.downloader.error = Exception('reset');
      await r.controller.check();
      await r.controller.begin();
      expect(r.controller.phase, UpdatePhase.failed);
      expect(r.controller.failure, UpdateFailure.network);
      r.downloader.error = null;
      await r.controller.begin();
      expect(r.installer.installed, hasLength(1));
    });

    test('a failing background download stays quiet', () async {
      final r = UpdateRig(info: _with(UpdateKind.patch));
      r.downloader.error = Exception('reset');
      await r.controller.check();
      await Future<void>.delayed(Duration.zero);
      expect(r.controller.phase, UpdatePhase.idle);
      expect(r.controller.failure, isNull);
    });

    test('a bad checksum twice is a verify failure', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      r.downloader.error = const UpdateVerifyException();
      await r.controller.check();
      await r.controller.begin();
      expect(r.downloader.downloads, 2, reason: 're-downloads once');
      expect(r.controller.failure, UpdateFailure.verify);
    });

    test('a signature mismatch is reported', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      r.installer.result = InstallStatus.signatureMismatch;
      await r.controller.check();
      await r.controller.begin();
      expect(r.controller.phase, UpdatePhase.failed);
      expect(r.controller.failure, UpdateFailure.signature);
    });

    test('cancelling the system confirmation keeps the download', () async {
      final r = UpdateRig(info: _with(UpdateKind.feature));
      r.installer.result = InstallStatus.cancelled;
      await r.controller.check();
      await r.controller.begin();
      expect(r.controller.phase, UpdatePhase.ready);
    });

    test('Wi-Fi only is remembered', () async {
      final r = UpdateRig();
      await r.controller.setWifiOnly(false);
      final again = UpdateRig(prefs: {'ota.wifiOnly': false});
      await again.controller.check();
      expect(again.controller.wifiOnly, isFalse);
      expect(UpdateConfig.maxPrompts, 3);
    });
  });
}
