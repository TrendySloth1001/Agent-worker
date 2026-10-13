import 'package:app/core/constants/about.dart';
import 'package:app/core/constants/m3_copy.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/about/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/render.dart';

import 'support/shot.dart';

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('about screen fits 360px without overflow ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      PackageInfo.setMockInitialValues(
        appName: 'sparky',
        packageName: 'com.sparky.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const AboutScreen()),
      );
      await tester.pumpAndSettle();
      await autoShot(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(AboutStrings.tagline), findsOneWidget);
      expect(find.text(AboutStrings.heroVersion('1.0.0')), findsOneWidget);

      // Scroll through every section; any overflow throws.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text(AboutStrings.madeWith),
        300,
        scrollable: list,
      );
      await tester.pumpAndSettle();
      expect(find.text(AboutCopy.feedback), findsOneWidget);
      expect(find.text(AboutStrings.madeWith), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('about survives the 1.3 text scale', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'sparky',
      packageName: 'com.sparky.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await pumpScreen(tester, const AboutScreen(), textScale: 1.3);
    await scrollThrough(tester, steps: 12);
    expect(tester.takeException(), isNull);
  });
}
