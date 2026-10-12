import 'package:app/core/constants/illustrations.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/illustration.dart';
import 'package:app/core/widgets/rotating_illustration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kinds = [
  IllustrationKind.homeChat,
  IllustrationKind.homeCode,
  IllustrationKind.homeRead,
];
const _every = IllustrationDurations.rotateEvery;
const _swap = IllustrationDurations.swap;

Widget _host(Widget child, {bool still = false, bool ticking = true}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: TickerMode(
            enabled: ticking,
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );

const _slot = RotatingIllustration(kinds: _kinds, height: 120, initialIndex: 0);

/// Kinds currently in the tree (the outgoing one too, mid cross-fade).
List<IllustrationKind> _shown(WidgetTester tester) => tester
    .widgetList<Illustration>(find.byType(Illustration))
    .map((i) => i.kind)
    .toList();

void main() {
  testWidgets('advances to the next scene after the interval', (tester) async {
    await tester.pumpWidget(_host(_slot));
    expect(_shown(tester), [IllustrationKind.homeChat]);

    await tester.pump(_every - const Duration(milliseconds: 100));
    expect(_shown(tester), [IllustrationKind.homeChat]);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(_swap ~/ 2);
    // Mid cross-fade both scenes are up.
    expect(_shown(tester), [
      IllustrationKind.homeChat,
      IllustrationKind.homeCode,
    ]);

    await tester.pump(_swap);
    expect(_shown(tester), [IllustrationKind.homeCode]);

    // ...and wraps around.
    await tester.pump(_every);
    await tester.pump(_swap * 2);
    await tester.pump(_every);
    await tester.pump(_swap * 2);
    expect(_shown(tester), [IllustrationKind.homeChat]);
  });

  testWidgets('the slot keeps one size for every scene', (tester) async {
    await tester.pumpWidget(_host(_slot));
    final size = tester.getSize(find.byType(RotatingIllustration));
    expect(size, const Size(120 * IllustrationSizes.rotatingAspect, 120));
    await tester.pump(_every);
    await tester.pump(_swap * 2);
    expect(tester.getSize(find.byType(RotatingIllustration)), size);
  });

  testWidgets('reduced motion shows one still scene', (tester) async {
    await tester.pumpWidget(_host(_slot, still: true));
    await tester.pump(_every * 3);
    expect(_shown(tester), [IllustrationKind.homeChat]);
    expect(
      find.descendant(
        of: find.byType(RotatingIllustration),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('pauses while offstage (TickerMode off)', (tester) async {
    await tester.pumpWidget(_host(_slot, ticking: false));
    await tester.pump(_every * 3);
    expect(_shown(tester), [IllustrationKind.homeChat]);

    await tester.pumpWidget(_host(_slot));
    await tester.pump(_every);
    await tester.pump(_swap * 2);
    expect(_shown(tester), [IllustrationKind.homeCode]);
  });

  testWidgets('pauses while the app is in the background', (tester) async {
    await tester.pumpWidget(_host(_slot));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(_every * 3);
    expect(_shown(tester), [IllustrationKind.homeChat]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_every);
    await tester.pump(_swap * 2);
    expect(_shown(tester), [IllustrationKind.homeCode]);
  });

  testWidgets('disposes its timer and ticker cleanly', (tester) async {
    await tester.pumpWidget(_host(_slot));
    await tester.pump(_every ~/ 2);
    await tester.pumpWidget(const SizedBox());
    // A live periodic timer or ticker would fail the test here.
    await tester.pump(_every * 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new slot carries on from where the last one stopped', (
    tester,
  ) async {
    const set = [IllustrationKind.homeThink, IllustrationKind.homeDream];
    RotatingIllustration.debugStartAt(set, 1);
    const slot = RotatingIllustration(kinds: set, height: 100);
    await tester.pumpWidget(_host(slot));
    expect(_shown(tester), [IllustrationKind.homeDream]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(slot));
    expect(_shown(tester), [IllustrationKind.homeThink]);
    await tester.pumpWidget(const SizedBox());
  });

  test('the home and GitHub sets are non-empty and distinct', () {
    expect(IllustrationKind.home, hasLength(greaterThanOrEqualTo(5)));
    expect(
      IllustrationKind.home.toSet(),
      hasLength(IllustrationKind.home.length),
    );
    expect(
      IllustrationKind.githubSet,
      contains(IllustrationKind.githubBranches),
    );
  });
}
