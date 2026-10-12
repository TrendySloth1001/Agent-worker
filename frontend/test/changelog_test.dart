import 'package:app/core/constants/changelog.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/about/changelog_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';

void main() {
  setUpAll(loadAppFonts);
  for (final dark in [false, true]) {
    testWidgets('changelog (${dark ? 'dark' : 'light'})', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          debugShowCheckedModeBanner: false,
          home: const ChangelogScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await shot(tester, 'changelog_${dark ? 'dark' : 'light'}');
      expect(find.text(ChangelogStrings.latest), findsOneWidget);
      expect(find.text(Changelog.releases.first.changes.first), findsOneWidget);
    });
  }
}
