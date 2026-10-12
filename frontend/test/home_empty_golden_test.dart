import 'package:app/core/constants/app_sizes.dart';
import 'package:app/core/theme/app_palette.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/illustration.dart';
import 'package:app/core/widgets/rotating_illustration.dart';
import 'package:app/features/chat/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';

Future<void> _fonts() async {
  for (final (family, files) in [
    ('SpaceGrotesk', ['SpaceGrotesk.ttf']),
    ('SpaceMono', ['SpaceMono-Regular.ttf', 'SpaceMono-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
}

/// Lets flutter_svg finish decoding the pictures (real async work).
Future<void> _settleArt(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
}

const _themes = [('light', false), ('dark', true)];

void main() {
  setUpAll(_fonts);

  for (final (name, dark) in _themes) {
    for (final kind in [
      IllustrationKind.homeChat,
      IllustrationKind.homeCoffee,
    ]) {
      testWidgets('home empty state, ${kind.name} ($name)', (tester) async {
        _phone(tester);
        RotatingIllustration.debugStartAt(
          IllustrationKind.home,
          IllustrationKind.home.indexOf(kind),
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(body: EmptyState(onSuggestion: (_) {})),
          ),
        );
        await _settleArt(tester);
        final shown = tester.widget<Illustration>(find.byType(Illustration));
        expect(shown.kind, kind);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home_empty_${kind.name}_$name.png'),
        );
        await tester.pumpWidget(const SizedBox());
      });
    }

    // Review sheet of every scene (written to the scratch shot dir).
    testWidgets('illustration contact sheet ($name)', (tester) async {
      // Logical size at 1x; the shot helper renders it at 2x.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const kinds = [...IllustrationKind.home, ...IllustrationKind.githubSet];
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final k in kinds)
                        Container(
                          width: 184,
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: context.palette.border),
                          ),
                          alignment: Alignment.center,
                          child: Illustration(
                            kind: k,
                            height: 120,
                            width: 170,
                            entrance: false,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settleArt(tester);
      await shot(tester, 'illustrations_$name');
    });
  }
}
