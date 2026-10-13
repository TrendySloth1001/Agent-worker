import 'package:app/core/theme/app_palette.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/confirm_sheet.dart';
import 'package:app/core/widgets/illustration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = 'Delete this?';
const _body = 'It will be gone.';

Future<List<bool>> _open(
  WidgetTester tester, {
  bool dark = false,
  bool destructive = true,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  final results = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => results.add(
                await ConfirmSheet.show(
                  context,
                  illustration: IllustrationKind.emptyHistory,
                  kicker: 'DELETE',
                  title: _title,
                  body: _body,
                  confirmLabel: 'Delete',
                  cancelLabel: 'Keep',
                  destructive: destructive,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('shows kicker, title, body, illustration', (tester) async {
    await _open(tester);
    expect(find.text('DELETE'), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_body), findsOneWidget);
    expect(find.byType(Illustration), findsOneWidget);
  });

  testWidgets('confirm resolves true, cancel resolves false', (tester) async {
    final results = await _open(tester);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmSheet), findsNothing);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(results, [false, true]);
  });

  testWidgets('dismissing the sheet resolves false', (tester) async {
    final results = await _open(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  for (final dark in [false, true]) {
    testWidgets('destructive confirm is red with white text (dark: $dark)', (
      tester,
    ) async {
      await _open(tester, dark: dark);
      final p = dark ? AppPalette.dark : AppPalette.light;
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-ok')),
      );
      final style = button.style!;
      expect(style.backgroundColor!.resolve({}), p.error);
      expect(
        style.foregroundColor!.resolve({}),
        dark ? p.textPrimary : p.textInverse,
      );
    });
  }

  testWidgets('a plain confirm is not red', (tester) async {
    await _open(tester, destructive: false);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-ok')),
    );
    expect(button.style!.backgroundColor, isNull);
  });

  testWidgets('the illustration folds away while the keyboard is open', (
    tester,
  ) async {
    await _open(tester, keyboard: 300);
    expect(find.text(_title), findsOneWidget);
    expect(find.byType(Illustration), findsNothing);
  });
}
