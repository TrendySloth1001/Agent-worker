import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/mascot.dart';
import 'package:lottie/lottie.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';

Widget _gallery(ThemeData theme, {bool still = false}) => MaterialApp(
  theme: theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: still),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final s in MascotState.values)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Mascot(state: s, size: 110),
                Text(s.name, style: const TextStyle(fontSize: 11)),
              ],
            ),
        ],
      ),
    ),
  ),
);

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('mascot renders every state ($name)', (tester) async {
      tester.view.physicalSize = const Size(412, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_gallery(theme));
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
      for (final step in [0, 1, 2, 3]) {
        await tester.pump(Duration(milliseconds: step == 0 ? 1 : 700));
        expect(tester.takeException(), isNull);
        await autoShot(tester, '_$step');
      }
      expect(find.byType(Mascot), findsNWidgets(MascotState.values.length));
    });
  }

  test('every state maps to a bundled lottie file', () {
    final assets = {for (final s in MascotState.values) s.asset};
    expect(assets.length, MascotState.values.length);
    for (final a in assets) {
      final f = File(a);
      expect(f.existsSync(), isTrue, reason: a);
      expect(f.lengthSync(), lessThan(200 * 1024), reason: a);
    }
  });

  testWidgets('loads the lottie and cross-fades on state change', (
    tester,
  ) async {
    Widget app(MascotState s) => MaterialApp(
      theme: AppTheme.light,
      home: Mascot(state: s),
    );
    await tester.pumpWidget(app(MascotState.idle));
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LottieBuilder), findsOneWidget);
    await tester.pumpWidget(app(MascotState.thinking));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LottieBuilder), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LottieBuilder), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows a static frame', (tester) async {
    await tester.pumpWidget(_gallery(AppTheme.light, still: true));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('animates when motion is allowed and stops when hidden', (
    tester,
  ) async {
    Widget app(bool on) => MaterialApp(
      theme: AppTheme.light,
      home: TickerMode(
        enabled: on,
        child: const Mascot(state: MascotState.thinking),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
