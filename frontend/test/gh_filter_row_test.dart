import 'package:app/core/constants/widget_github.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/chat/widgets/github/github_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';

void main() {
  setUpAll(loadAppFonts);
  for (final dark in [false, true]) {
    testWidgets('commit filter row (${dark ? 'dark' : 'light'})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412 * 2.6, 200 * 2.6);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      GhFilterChip(
                        label: 'BRANCH',
                        on: false,
                        picker: true,
                        height: GithubPagingSizes.fieldHeight,
                        onTap: () {},
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GhSearchField(
                          hint: GithubPagingStrings.commitFilterHint,
                          onChanged: (_) {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GhSearchField(hint: 'Filter branches', onChanged: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'main');
      await tester.pump();
      await shot(tester, 'gh_filter_row_${dark ? 'dark' : 'light'}');
      expect(find.text('main'), findsOneWidget);
    });
  }
}
