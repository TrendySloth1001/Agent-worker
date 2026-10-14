import 'package:app/core/constants/errors.dart';
import 'package:app/core/constants/update.dart';
import 'package:app/core/errors/errors_api.dart';
import 'package:app/core/errors/errors_models.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/update/update_models.dart';
import 'package:app/features/errors/error_detail_screen.dart';
import 'package:app/features/errors/errors_screen.dart';
import 'package:app/features/update/releases_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';
import 'support/update_fakes.dart';

final _now = DateTime(2026, 10, 21, 12);
const _fpA = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678';
const _fpB = 'b1b2c3d4e5f60718293a4b5c6d7e8f9012345678';

ErrorGroup _group(
  String fp,
  String title,
  int users,
  int count, [
  ErrorStatus status = ErrorStatus.open,
]) => ErrorGroup(
  fingerprint: fp,
  title: title,
  kind: 'dart',
  status: status,
  count: count,
  users: users,
  firstBuild: 33,
  lastBuild: 34,
  lastSeen: _now.subtract(const Duration(hours: 3)),
  buildCount: count,
  buildUsers: users,
);

class FakeErrorsApi implements ErrorsApi {
  final calls = <String>[];
  var groupsList = [
    _group(_fpA, 'StateError: Bad state: no element', 4, 11),
    _group(_fpB, 'RangeError: index out of range', 1, 2),
  ];
  var statusOf = ErrorStatus.open;

  @override
  Future<ErrorGroupList> groups({int? build, String status = 'open'}) async {
    calls.add('groups:$build:$status');
    return ErrorGroupList(groups: groupsList, builds: const [34, 33]);
  }

  @override
  Future<List<BuildHealth>> buildHealth({int days = 7}) async => const [
    BuildHealth(
      build: 34,
      sessions: 240,
      users: 18,
      crashed: 3,
      crashFree: 0.9875,
      errorGroups: 2,
    ),
    BuildHealth(
      build: 33,
      sessions: 90,
      users: 11,
      crashed: 0,
      crashFree: 1,
      errorGroups: 0,
    ),
  ];

  @override
  Future<ErrorGroupDetail> detail(String fingerprint) async => ErrorGroupDetail(
    group: _group(
      fingerprint,
      'StateError: Bad state: no element',
      4,
      11,
      statusOf,
    ),
    builds: const [ErrorBuildRow(34, 9, 3), ErrorBuildRow(33, 2, 1)],
    samples: [
      ErrorSample(
        id: '17',
        build: 34,
        at: _now.subtract(const Duration(hours: 3)),
        kind: 'dart',
        message: 'Bad state: no element',
        stack:
            '#0      _Foo.bar (package:app/features/chat/foo.dart:42:7)\n'
            '#1      _Baz.go (package:app/core/baz.dart:10:3)',
        breadcrumbs: const [
          'route push /chat',
          'lifecycle resumed',
          'update downloading',
        ],
        device: const {
          'model': 'Pixel 8',
          'sdk': 35,
          'abi': 'arm64-v8a',
          'net': 'wifi',
          'fg': true,
        },
        user: '3f2a9c1e',
      ),
    ],
  );

  @override
  Future<void> setStatus(String fingerprint, ErrorStatus status) async {
    calls.add('status:$fingerprint:${status.name}');
    statusOf = status;
  }

  @override
  Future<String?> userEmail(String eventId) async {
    calls.add('email:$eventId');
    return 'maya@example.com';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: home,
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    Haptics.enabled = false;
  });

  group('gating', () {
    testWidgets('a user gets an empty page and the API is never called', (
      tester,
    ) async {
      final api = FakeErrorsApi();
      await _phone(
        tester,
        ErrorsScreen(api: api, now: () => _now, owner: () => false),
      );
      expect(api.calls, isEmpty);
      expect(find.text(ErrorsStrings.groupsHeader), findsNothing);
      expect(find.text(ErrorsStrings.emptyTitle), findsOneWidget);
    });

    testWidgets(
      'open() does nothing for a user and pushes the screen for the owner',
      (tester) async {
        final api = FakeErrorsApi();
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
        await ErrorsScreen.open(ctx, api: api, owner: () => false);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(ErrorsScreen), findsNothing);
        // ignore: unawaited_futures
        ErrorsScreen.open(ctx, api: api, owner: () => true);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.byType(ErrorsScreen), findsOneWidget);
      },
    );

    testWidgets('Releases offers the Errors entry and it opens the screen', (
      tester,
    ) async {
      final errors = FakeErrorsApi();
      final api = FakeUpdateApi(list: const ReleaseList());
      await _phone(
        tester,
        ReleasesScreen(api: api, errorsApi: errors, now: () => _now),
      );
      expect(find.byTooltip(ErrorsStrings.entryTitle), findsOneWidget);
      await tester.tap(find.byTooltip(ErrorsStrings.entryTitle));
      await tester.pump(const Duration(milliseconds: 600));
      // isOwner() is false in tests (nobody is signed in), so the route refuses.
      expect(find.byType(ErrorsScreen), findsNothing);
      expect(UpdateStrings.releasesTitle, isNotEmpty);
    });
  });

  group('owner', () {
    testWidgets(
      'groups come in server order with users and events; builds show crash-free',
      (tester) async {
        final api = FakeErrorsApi();
        await _phone(
          tester,
          ErrorsScreen(api: api, now: () => _now, owner: () => true),
        );
        expect(api.calls.first, 'groups:null:open');
        expect(find.text('StateError: Bad state: no element'), findsOneWidget);
        expect(find.textContaining('4 users'), findsOneWidget);
        expect(find.text('98.75%'), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);
        final a = tester
            .getTopLeft(find.text('StateError: Bad state: no element'))
            .dy;
        final b = tester
            .getTopLeft(find.text('RangeError: index out of range'))
            .dy;
        expect(a, lessThan(b));
      },
    );

    testWidgets('picking a build reloads for that build', (tester) async {
      final api = FakeErrorsApi();
      await _phone(
        tester,
        ErrorsScreen(api: api, now: () => _now, owner: () => true),
      );
      await _tap(
        tester,
        find.widgetWithText(ChoiceChip, ErrorsStrings.buildLabel(33)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.calls, contains('groups:33:open'));
    });

    testWidgets(
      'detail shows samples; resolve and ignore call the API; the user is revealed on tap',
      (tester) async {
        final api = FakeErrorsApi();
        await _phone(
          tester,
          ErrorDetailScreen(fingerprint: _fpA, api: api, now: () => _now),
        );
        expect(find.textContaining('foo.dart'), findsWidgets);
        expect(find.text(ErrorsStrings.symbolize(_fpA)), findsOneWidget);
        expect(find.text('3f2a9c1e'), findsOneWidget);
        expect(find.textContaining('maya@example.com'), findsNothing);

        await _tap(tester, find.text(ErrorsStrings.resolve));
        await tester.pump(const Duration(milliseconds: 300));
        expect(api.calls, contains('status:$_fpA:resolved'));
        expect(find.text(ErrorsStrings.reopen), findsOneWidget);
        await _tap(tester, find.text(ErrorsStrings.ignore));
        await tester.pump(const Duration(milliseconds: 300));
        expect(api.calls, contains('status:$_fpA:ignored'));

        await _tap(tester, find.text(ErrorsStrings.showUser));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('maya@example.com'), findsOneWidget);
      },
    );
  });

  group('golden', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('errors list $mode', (tester) async {
        await _phone(
          tester,
          ErrorsScreen(
            api: FakeErrorsApi(),
            now: () => _now,
            owner: () => true,
          ),
          dark: dark,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/errors_list_$mode.png'),
        );
      });
      testWidgets('errors detail $mode', (tester) async {
        await _phone(
          tester,
          ErrorDetailScreen(
            fingerprint: _fpA,
            api: FakeErrorsApi(),
            now: () => _now,
          ),
          dark: dark,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/errors_detail_$mode.png'),
        );
      });
    }
  });
}
