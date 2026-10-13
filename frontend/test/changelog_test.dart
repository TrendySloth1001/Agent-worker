import 'package:app/core/constants/changelog.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/about/changelog_screen.dart';
import 'package:app/features/about/whats_new_sheet.dart';
import 'package:app/features/about/widgets/changelog_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/render.dart';
import 'support/shot.dart';

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

Future<void> _phone(
  WidgetTester tester,
  Widget home, {
  required bool dark,
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
  await _settleArt(tester);
}

Finder get _earlier => find.text(ChangelogStrings.earlier);

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('data', () {
    test('every release has a headline and short, filled-in items', () {
      final versions = <String>{};
      for (final r in Changelog.releases) {
        expect(versions.add(r.version), isTrue, reason: r.version);
        expect(r.headline, isNotEmpty);
        expect(r.items, isNotEmpty);
        for (final c in r.items) {
          expect(c.title.length, lessThanOrEqualTo(28), reason: c.title);
          expect(c.detail, isNotEmpty);
        }
      }
    });

    test('groupByKind orders New, Improved, Fixed and skips empty kinds', () {
      final r = Changelog.find('1.1.2')!;
      expect(groupByKind(r).map((g) => g.$1), [
        ChangeKind.added,
        ChangeKind.improved,
        ChangeKind.fixed,
      ]);
      expect(
        groupByKind(Changelog.find('1.1.1')!).map((g) => g.$1),
        [ChangeKind.added],
      );
    });

    test('the update sheet is due only after an update with an entry', () {
      final v = Changelog.latest.version;
      expect(WhatsNew.due(lastSeen: null, current: v), isNull); // install
      expect(WhatsNew.due(lastSeen: v, current: v), isNull);
      expect(WhatsNew.due(lastSeen: '1.0.0', current: v)?.version, v);
      expect(WhatsNew.due(lastSeen: v, current: '9.9.9'), isNull);
    });
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('changelog hero + highlights ($theme)', (tester) async {
      await _phone(tester, const ChangelogScreen(), dark: dark);
      final latest = Changelog.latest;
      expect(find.text(latest.version), findsOneWidget);
      expect(find.text(latest.headline), findsOneWidget);
      expect(find.text(ChangelogStrings.heroKicker(latest.date)), findsOne);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/changelog_$theme.png'),
      );
      // Every highlight of the latest release is on the page.
      for (final c in latest.items) {
        expect(find.text(c.title), findsOneWidget);
      }
    });

    testWidgets('changelog timeline collapsed / expanded ($theme)', (
      tester,
    ) async {
      await _phone(tester, const ChangelogScreen(), dark: dark);
      final second = Changelog.releases[1];
      await _scrollTo(tester, find.text(Changelog.releases.last.headline));
      // Collapsed: the count shows, the items don't.
      expect(
        find.text(ChangelogStrings.count(second.items.length).toUpperCase()),
        findsWidgets,
      );
      expect(find.text(second.items.first.title), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/changelog_timeline_collapsed_$theme.png'),
      );

      await _scrollTo(tester, _earlier);
      await tester.tap(find.text(second.headline));
      await tester.pump(ChangelogSizes.expandDuration ~/ 2);
      await tester.pumpAndSettle();
      await _settleArt(tester);
      expect(find.text(second.items.first.title), findsOneWidget);
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -AppSizesForTest.nudge),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/changelog_timeline_expanded_$theme.png'),
      );

      // Collapses again.
      await tester.tap(find.text(second.headline));
      await tester.pumpAndSettle();
      expect(find.text(second.items.first.title), findsNothing);
    });

    testWidgets('whats new sheet ($theme)', (tester) async {
      await _phone(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => WhatsNew.show(context, Changelog.latest),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        dark: dark,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _settleArt(tester);
      final latest = Changelog.latest;
      expect(find.text(ChangelogStrings.sheetKicker(latest.version)), findsOne);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/changelog_sheet_$theme.png'),
      );

      // "See all" opens the full screen.
      await tester.tap(find.text(ChangelogStrings.seeAll));
      await tester.pumpAndSettle();
      await _settleArt(tester);
      expect(find.byType(ChangelogScreen), findsOneWidget);
    });
  }

  testWidgets('maybeShow skips a fresh install, shows once after update', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final results = <bool>[];
    final v = Changelog.latest.version;
    await _phone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async =>
                  results.add(await WhatsNew.maybeShow(context, version: v)),
              child: const Text('launch'),
            ),
          ),
        ),
      ),
      dark: false,
    );
    Future<void> launch() async {
      await tester.tap(find.text('launch'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    await launch(); // Fresh install: only records the version.
    expect(results, [false]);
    expect(find.byType(WhatsNewSheet), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ChangelogPrefs.lastSeenVersion, '1.0.0');
    await launch(); // Updated: shows.
    expect(find.byType(WhatsNewSheet), findsOneWidget);
    await tester.tap(find.text(ChangelogStrings.gotIt));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewSheet), findsNothing);
    expect(prefs.getString(ChangelogPrefs.lastSeenVersion), v);

    await launch(); // Same version again: nothing.
    expect(results.last, isFalse);
  });

  for (final (name, theme, scale) in renderCases) {
    testWidgets('changelog fits 360dp ($name)', (tester) async {
      await pumpScreen(
        tester,
        const ChangelogScreen(),
        theme: theme,
        textScale: scale,
      );
      await scrollThrough(tester, steps: 14);
      expect(tester.takeException(), isNull);
      // Expand an earlier release at this size too.
      final r = Changelog.releases.last;
      await tester.tap(find.text(r.headline));
      await tester.pumpAndSettle();
      await scrollThrough(tester, steps: 8);
      expect(tester.takeException(), isNull);
      final toggle = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.text(r.headline),
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.expanded != null,
              ),
            )
            .first,
      );
      expect(toggle.properties.button, isTrue);
      expect(toggle.properties.expanded, isTrue);
    });
  }
}

abstract final class AppSizesForTest {
  static const nudge = 160.0;
}
