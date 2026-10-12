import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/mascot.dart';
import 'package:app/core/widgets/mascot_frame.dart';
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
      for (final step in [0, 1, 2, 3]) {
        await tester.pump(Duration(milliseconds: step == 0 ? 1 : 700));
        expect(tester.takeException(), isNull);
        await autoShot(tester, '_$step');
      }
      expect(find.byType(Mascot), findsNWidgets(MascotState.values.length));
    });
  }

  test('every state lights dots at every moment of the loop', () {
    for (final s in MascotState.values) {
      for (var t = 0.0; t < 4; t += 0.1) {
        expect(buildMascotFrame(s, t).litCount, greaterThan(20), reason: '$s');
      }
    }
  });

  test('states look different from one another', () {
    String sig(MascotState s) {
      final f = buildMascotFrame(s, 0.5);
      return [
        for (var r = 0; r < 15; r++)
          for (var c = 0; c < 17; c++) f.at(c, r) == null ? '.' : 'x',
      ].join();
    }

    final sigs = {for (final s in MascotState.values) sig(s)};
    expect(sigs.length, MascotState.values.length);
  });

  testWidgets('reduced motion shows a static frame', (tester) async {
    await tester.pumpWidget(_gallery(AppTheme.light, still: true));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpAndSettle();
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
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
