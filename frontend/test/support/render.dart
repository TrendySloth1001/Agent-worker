import 'package:app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The theme/scale matrix of the render tests: 360dp wide, light and dark,
/// plus a 1.3 text scale.
final renderCases = <(String, ThemeData, double)>[
  ('light', AppTheme.light, 1.0),
  ('dark', AppTheme.dark, 1.0),
  ('light 1.3x', AppTheme.light, 1.3),
];

/// Pumps [home] on a 360x780 phone and lets short animations run.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget home, {
  ThemeData? theme,
  double textScale = 1,
  Widget Function(Widget child)? wrap,
  double height = 780,
}) async {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
    theme: theme ?? AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );
  await tester.pumpWidget(wrap == null ? app : wrap(app));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Drags the first scroll view through its whole length; overflows throw.
Future<void> scrollThrough(WidgetTester tester, {int steps = 8}) async {
  final list = find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var i = 0; i < steps; i++) {
    await tester.drag(list, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
