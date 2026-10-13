import 'package:app/core/constants/profile_copy.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/profile/widgets/log_out_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';

Future<List<bool>> _open(WidgetTester tester, {required bool dark}) async {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  final results = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async =>
                  results.add(await LogOutSheet.show(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
  return results;
}

void main() {
  setUpAll(loadAppFonts);

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('sign-out sheet ($theme)', (tester) async {
      await _open(tester, dark: dark);
      expect(find.text(ProfileCopy.logOutTitle), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/log_out_sheet_$theme.png'),
      );
    });
  }

  testWidgets('Stay returns false, Sign out returns true', (tester) async {
    final results = await _open(tester, dark: false);
    await tester.tap(find.text(ProfileCopy.logOutStay));
    await tester.pumpAndSettle();
    expect(find.byType(LogOutSheet), findsNothing);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ProfileCopy.logOut));
    await tester.pumpAndSettle();
    expect(results, [false, true]);
  });
}
