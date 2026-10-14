import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/core/constants/update.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/update/update_controller.dart';
import 'package:app/core/update/update_installer.dart';
import 'package:app/core/update/update_models.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/update/release_form_sheet.dart';
import 'package:app/features/update/releases_screen.dart';
import 'package:app/features/update/update_required_screen.dart';
import 'package:app/features/update/update_settings.dart';
import 'package:app/features/update/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';
import 'support/update_fakes.dart';

final _boundary = GlobalKey();

/// Review screenshot of the whole app (sheets included), only with
/// `--dart-define=SHOTS=true`.
Future<void> autoShot(WidgetTester tester, [String suffix = '']) async {
  if (!const bool.fromEnvironment('SHOTS')) return;
  final name = tester.testDescription.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  await tester.runAsync(() async {
    final b =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await b.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotDir).createSync(recursive: true);
    File(
      '$shotDir/upd_$name$suffix.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _phone(
  WidgetTester tester,
  Widget home, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A screen with one button that opens the update sheet.
Widget _sheetHost(UpdateController c) => Scaffold(
  body: Center(
    child: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => UpdateSheet.show(ctx, controller: c),
        child: const Text('open'),
      ),
    ),
  ),
);

UpdateInfo _info(UpdateKind kind, {bool required = false}) => UpdateInfo(
  current: 25,
  required: required,
  latest: fakeRelease(kind: kind),
);

Future<UpdateRig> _rig(UpdateKind kind, {bool required = false}) async {
  final r = UpdateRig(info: _info(kind, required: required));
  await r.controller.check();
  return r;
}

void main() {
  setUpAll(loadAppFonts);

  group('UpdateSheet', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('feature sheet ($mode)', (tester) async {
        final r = await _rig(UpdateKind.feature);
        await _phone(tester, _sheetHost(r.controller), dark: dark);
        await tester.tap(find.text('open'));
        await _settle(tester);
        expect(find.text(UpdateStrings.kickerFeature), findsOneWidget);
        expect(find.text('Faster chats and a calmer look'), findsOneWidget);
        expect(find.text('Replies start sooner'), findsOneWidget);
        expect(find.text(UpdateStrings.update), findsOneWidget);
        expect(find.text(UpdateStrings.later), findsOneWidget);
        await autoShot(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('major sheet ($mode)', (tester) async {
        final r = await _rig(UpdateKind.major);
        await _phone(tester, _sheetHost(r.controller), dark: dark);
        await tester.tap(find.text('open'));
        await _settle(tester);
        expect(find.text(UpdateStrings.kickerMajor), findsOneWidget);
        expect(find.text('Fewer hiccups on slow networks'), findsOneWidget);
        await autoShot(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Later closes the sheet', (tester) async {
      final r = await _rig(UpdateKind.feature);
      await _phone(tester, _sheetHost(r.controller));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(find.text(UpdateStrings.later));
      await _settle(tester);
      expect(find.text(UpdateStrings.kickerFeature), findsNothing);
      expect(r.downloader.downloads, 0);
    });

    testWidgets('Update shows progress, then hands over to the installer', (
      tester,
    ) async {
      final r = await _rig(UpdateKind.feature);
      r.downloader.gate = Completer<void>();
      await _phone(tester, _sheetHost(r.controller));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(find.text(UpdateStrings.update));
      await tester.pump();
      await tester.pump();
      expect(find.text(UpdateStrings.downloading(50)), findsOneWidget);
      expect(find.text(UpdateStrings.update), findsNothing);
      await autoShot(tester, '_progress');

      r.downloader.gate!.complete();
      await tester.pump();
      await tester.pump();
      expect(r.installer.installed, ['/cache/30.apk']);
    });

    testWidgets('missing permission shows the friendly step', (tester) async {
      final r = await _rig(UpdateKind.feature);
      r.installer.allowed = false;
      await _phone(tester, _sheetHost(r.controller));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(find.text(UpdateStrings.update));
      await _settle(tester);
      expect(find.text(UpdateStrings.permissionTitle), findsOneWidget);
      await autoShot(tester, '_permission');
      await tester.tap(find.text(UpdateStrings.permissionOpen));
      await tester.pump();
      expect(r.installer.settingsOpened, 1);
    });

    testWidgets('a failed download offers Try again', (tester) async {
      final r = await _rig(UpdateKind.feature);
      r.downloader.error = Exception('offline');
      await _phone(tester, _sheetHost(r.controller));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(find.text(UpdateStrings.update));
      await _settle(tester);
      expect(find.text(UpdateStrings.failNetwork), findsOneWidget);
      expect(find.text(UpdateStrings.tryAgain), findsOneWidget);
      await autoShot(tester, '_failed');
    });

    testWidgets('maybeShow records the prompt once', (tester) async {
      final r = await _rig(UpdateKind.feature);
      late BuildContext ctx;
      await _phone(
        tester,
        Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      );
      unawaited(UpdateSheet.maybeShow(ctx, controller: r.controller));
      await _settle(tester);
      expect(find.text(UpdateStrings.kickerFeature), findsOneWidget);
      expect(r.controller.sheetDue, isFalse);
      expect(
        await UpdateSheet.maybeShow(ctx, controller: r.controller),
        isFalse,
      );
    });
  });

  group('UpdateRequiredScreen', () {
    for (final dark in [false, true]) {
      testWidgets(
        'blocks with a single Update button (${dark ? 'dark' : 'light'})',
        (tester) async {
          final r = await _rig(UpdateKind.critical, required: true);
          await _phone(
            tester,
            UpdateRequiredScreen(controller: r.controller),
            dark: dark,
          );
          await _settle(tester);
          expect(find.text(UpdateStrings.requiredTitle), findsOneWidget);
          expect(find.text(UpdateStrings.requiredCritical), findsOneWidget);
          expect(find.text(UpdateStrings.later), findsNothing);
          await autoShot(tester);
          await tester.tap(find.text(UpdateStrings.update));
          await _settle(tester);
          expect(r.installer.installed, hasLength(1));
        },
      );
    }

    testWidgets('failure shows a retry', (tester) async {
      final r = await _rig(UpdateKind.critical, required: true);
      r.installer.result = InstallStatus.failed;
      await _phone(tester, UpdateRequiredScreen(controller: r.controller));
      await tester.tap(find.text(UpdateStrings.update));
      await _settle(tester);
      expect(find.text(UpdateStrings.failInstall), findsOneWidget);
      expect(find.text(UpdateStrings.tryAgain), findsOneWidget);
      await autoShot(tester, '_failed');
    });

    testWidgets('the gate covers the app only while an update is required', (
      tester,
    ) async {
      final r = UpdateRig();
      await _phone(
        tester,
        UpdateGate(
          controller: r.controller,
          child: const Scaffold(body: Text('the app')),
        ),
      );
      expect(find.text(UpdateStrings.requiredTitle), findsNothing);
      r.api.info = _info(UpdateKind.feature, required: true);
      await r.controller.check();
      await tester.pump();
      expect(find.text(UpdateStrings.requiredTitle), findsOneWidget);
    });
  });

  group('Settings → About', () {
    Widget host(UpdateController c) => Scaffold(
      body: SingleChildScrollView(child: UpdateSettingsGroup(controller: c)),
    );

    testWidgets('up to date, no dot', (tester) async {
      final r = UpdateRig();
      await r.controller.check();
      await _phone(tester, host(r.controller));
      expect(find.text(UpdateStrings.statusUpToDate), findsOneWidget);
      await autoShot(tester);
    });

    testWidgets('an update shows a status and opens the sheet', (tester) async {
      final r = UpdateRig(info: _info(UpdateKind.patch), wifi: false);
      await r.controller.check();
      await _phone(tester, host(r.controller), dark: true);
      expect(find.text(UpdateStrings.statusAvailable('1.7.0')), findsOneWidget);
      await autoShot(tester);
      await tester.tap(find.text(UpdateStrings.rowTitle));
      await _settle(tester);
      expect(find.text(UpdateStrings.kickerFeature), findsOneWidget);
    });

    testWidgets('Check for updates asks the server', (tester) async {
      final r = UpdateRig();
      await _phone(tester, host(r.controller));
      expect(find.text(UpdateStrings.statusUnknown), findsOneWidget);
      await tester.tap(find.text(UpdateStrings.check));
      await _settle(tester);
      expect(r.api.checks, 1);
      expect(find.text(UpdateStrings.statusUpToDate), findsOneWidget);
    });

    testWidgets('a failed check says so', (tester) async {
      final r = UpdateRig()..api.error = Exception('offline');
      await _phone(tester, host(r.controller));
      await tester.tap(find.text(UpdateStrings.check));
      await _settle(tester);
      expect(find.text(UpdateStrings.checkFailed), findsOneWidget);
    });

    testWidgets('the Wi-Fi switch is stored', (tester) async {
      final r = UpdateRig();
      await _phone(tester, host(r.controller));
      expect(r.controller.wifiOnly, isTrue);
      await tester.tap(find.text(UpdateStrings.wifiOnly));
      await tester.pump();
      expect(r.controller.wifiOnly, isFalse);
    });

    testWidgets('downloading shows the percentage', (tester) async {
      final r = await _rig(UpdateKind.feature);
      r.downloader.gate = Completer<void>();
      unawaited(r.controller.begin());
      await _phone(tester, host(r.controller));
      await tester.pump();
      expect(find.text(UpdateStrings.statusDownloading(50)), findsOneWidget);
      r.downloader.gate!.complete();
      await _settle(tester);
    });
  });

  group('Releases (owner)', () {
    final releases = [
      OwnerRelease(
        id: 'r3',
        release: fakeRelease(
          kind: UpdateKind.feature,
          build: 30,
          version: '1.7.0',
          title: 'Faster chats',
        ),
        status: ReleaseStatus.live,
        minSupportedBuild: 22,
        publishedAt: DateTime(2026, 10, 12),
      ),
      OwnerRelease(
        id: 'r2',
        release: fakeRelease(
          kind: UpdateKind.critical,
          build: 29,
          version: '1.6.1',
          title: 'Security fix',
        ),
        status: ReleaseStatus.pulled,
        createdAt: DateTime(2026, 10, 1),
      ),
      OwnerRelease(
        id: 'r1',
        release: fakeRelease(
          kind: UpdateKind.patch,
          build: 31,
          version: '1.7.1',
          title: '',
        ),
        status: ReleaseStatus.draft,
        createdAt: DateTime(2026, 10, 13),
      ),
    ];
    final list = ReleaseList(
      releases: releases,
      adoption: const [
        AdoptionRow(build: 30, version: '1.7.0', users: 14),
        AdoptionRow(build: 25, version: '1.5.3', users: 3),
      ],
    );
    final now = DateTime(2026, 10, 13, 12);

    Future<FakeUpdateApi> open(
      WidgetTester tester, {
      bool dark = false,
      ApkPicker? pick,
      ReleaseList? data,
    }) async {
      final api = FakeUpdateApi(list: data ?? list);
      await _phone(
        tester,
        ReleasesScreen(api: api, pickApk: pick, now: () => now),
        dark: dark,
      );
      await _settle(tester);
      return api;
    }

    for (final dark in [false, true]) {
      testWidgets('lists releases and adoption (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        await open(tester, dark: dark);
        expect(find.text('Faster chats'), findsOneWidget);
        expect(find.text(UpdateStrings.statusLive), findsOneWidget);
        expect(find.text(UpdateStrings.statusPulled), findsOneWidget);
        expect(find.text(UpdateStrings.users(14)), findsOneWidget);
        expect(find.text(UpdateStrings.kindCritical), findsOneWidget);
        await autoShot(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows install outcomes for a release', (tester) async {
      final data = ReleaseList(
        releases: releases,
        adoption: list.adoption,
        installs: const [
          InstallStats(
            build: 30,
            stages: {
              'install_ok': 8,
              'install_fail': 1,
              'verify_fail': 1,
              'cancelled': 2,
            },
            successRate: 0.8,
          ),
        ],
      );
      await open(tester, data: data);
      expect(find.text(UpdateStrings.installsHeader), findsOneWidget);
      expect(
        find.text(UpdateStrings.installsLine(8, 2, 80)),
        findsOneWidget,
      );
      expect(find.textContaining('cancelled 2'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await open(tester, data: const ReleaseList());
      expect(find.text(UpdateStrings.releasesEmptyTitle), findsOneWidget);
    });

    testWidgets('go live sends the status change', (tester) async {
      final api = await open(tester);
      await tester.scrollUntilVisible(
        find.text(UpdateStrings.goLive).first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(UpdateStrings.goLive).first);
      await _settle(tester);
      expect(api.calls.single, contains('edit:r2'));
      expect(api.calls.single, contains('live'));
    });

    testWidgets('pull asks first', (tester) async {
      final api = await open(tester);
      await tester.tap(find.text(UpdateStrings.pull));
      await _settle(tester);
      expect(find.text(UpdateStrings.confirmPullTitle), findsOneWidget);
      await tester.tap(find.text(UpdateStrings.pull).last);
      await _settle(tester);
      expect(api.calls.single, contains('edit:r3'));
      expect(api.calls.single, contains('pulled'));
    });

    testWidgets('only drafts and pulled releases can be deleted', (
      tester,
    ) async {
      final api = await open(tester);
      // Draft and pulled: two delete buttons; the live one has none.
      expect(find.text(UpdateStrings.delete), findsNWidgets(2));
      await tester.tap(find.text(UpdateStrings.delete).first);
      await _settle(tester);
      await tester.tap(find.text(UpdateStrings.delete).last);
      await _settle(tester);
      expect(api.calls.single, startsWith('delete:'));
    });

    testWidgets('edit changes kind, title and minimum build', (tester) async {
      final api = await open(tester);
      await tester.tap(find.text(UpdateStrings.edit).first);
      await _settle(tester);
      expect(find.text(UpdateStrings.editTitle), findsOneWidget);
      await autoShot(tester, '_edit');
      await tester.tap(find.text(UpdateStrings.kindMajor));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, UpdateStrings.fieldTitle),
        'Big redesign',
      );
      await tester.tap(find.text(UpdateStrings.save));
      await _settle(tester);
      expect(api.calls.single, contains('edit:r3'));
      expect(api.calls.single, contains('major'));
      expect(api.calls.single, contains('Big redesign'));
    });

    testWidgets('upload sends the APK with its details', (tester) async {
      final api = await open(tester, pick: () async => '/tmp/app.apk');
      await tester.tap(find.text(UpdateStrings.uploadApk));
      await _settle(tester);
      expect(find.text(UpdateStrings.uploadTitle), findsOneWidget);
      await autoShot(tester, '_upload');

      // Nothing chosen yet.
      await tester.tap(find.text(UpdateStrings.uploadApk).last);
      await tester.pump();
      expect(find.text(UpdateStrings.needFile), findsOneWidget);

      await tester.tap(find.text(UpdateStrings.pickApk));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, UpdateStrings.fieldVersion),
        '1.8.0',
      );
      await tester.enterText(
        find.widgetWithText(TextField, UpdateStrings.fieldBuild),
        '32',
      );
      await tester.tap(find.text(UpdateStrings.kindPatch).last);
      await tester.pump();
      await tester.tap(find.text(UpdateStrings.uploadApk).last);
      await _settle(tester);
      expect(api.calls.single, 'upload:1.8.0:32:patch:live=false');
      // The new draft is on the list.
      expect(find.text('v1.8.0'), findsOneWidget);
    });
  });

  test('Releases is an owner-only direct settings entry', () {
    expect(SettingsCategory.releases.ownerOnly, isTrue);
    expect(SettingsCategory.releases.isDirect, isTrue);
    expect(SettingsCategory.releases.title, UpdateStrings.releasesTitle);
  });
}
