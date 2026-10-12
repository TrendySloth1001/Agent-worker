import 'package:app/core/constants/app_strings.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/chat/widgets/markdown/app_markdown.dart';
import 'package:app/features/chat/widgets/markdown/md_blocks.dart';
import 'package:app/features/chat/widgets/markdown/md_table_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const comparison = '''
| Option | Strengths | Weaknesses |
|---|---|---|
| Postgres | Rock solid relational engine with great extensions and tooling | Needs more care when scaling writes across many machines |
| MongoDB | Flexible documents and easy horizontal sharding out of the box | Weaker joins and transactions across collections historically |
| SQLite | Zero configuration and embedded straight into your application | Single writer, so heavy concurrent workloads will struggle |
''';

const wide = '''
| Month | Jan | Feb | Mar | Apr | May | Jun |
|---|---|---|---|---|---|---|
| Sales | 120 | 135 | 150 | 160 | 170 | 190 |
| Costs | 80 | 85 | 90 | 95 | 100 | 105 |
| Profit | 40 | 50 | 60 | 65 | 70 | 85 |
''';

const numeric = '''
| City | Pop | Area |
|---|---:|---:|
| Tokyo | 37.4M | 2,194 |
| Delhi | 31.0M | 1,484 |
| Shanghai | 27.1M | 6,341 |
''';

const many = '''
| A | B | C | D | E | F | G | H | I | J |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
''';

Future<void> pump(
  WidgetTester tester,
  String md,
  ThemeData theme, {
  bool streaming = false,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AppMarkdown(
            data: md,
            citations: const [],
            streaming: streaming,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    group('md table at 360px ($name)', () {
      testWidgets('comparison table becomes cards', (tester) async {
        await pump(tester, comparison, theme);
        expect(tester.takeException(), isNull);
        expect(find.byKey(MdTableLayout.cards.key), findsOneWidget);
        expect(find.byKey(MdTableLayout.scroll.key), findsNothing);
        expect(find.text('WEAKNESSES'), findsNWidgets(3));
      });

      testWidgets('toggle switches to the table and back', (tester) async {
        await pump(tester, comparison, theme);
        await tester.tap(find.text(MdTableStrings.table));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(MdTableLayout.cards.key), findsNothing);
        expect(find.byKey(MdTableLayout.scroll.key), findsOneWidget);
        await tester.tap(find.text(MdTableStrings.cards));
        await tester.pump();
        expect(find.byKey(MdTableLayout.cards.key), findsOneWidget);
      });

      testWidgets('wide 7-column table scrolls with a frozen column', (
        tester,
      ) async {
        await pump(tester, wide, theme);
        expect(tester.takeException(), isNull);
        expect(find.byKey(MdTableLayout.scroll.key), findsOneWidget);
        // Scroll sideways: the overlay keeps the first column in view.
        await tester.drag(
          find.byKey(MdTableLayout.scroll.key),
          const Offset(-200, 0),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Profit'), findsNWidgets(2));
      });

      testWidgets('numeric table fits', (tester) async {
        await pump(tester, numeric, theme);
        expect(tester.takeException(), isNull);
        expect(find.byKey(MdTableLayout.fit.key), findsOneWidget);
        // Right-aligned column: number sits against the right edge.
        final cell = tester.getRect(find.text('37.4M'));
        final head = tester.getRect(find.text('POP'));
        expect(cell.right, closeTo(head.right, 1));
      });

      testWidgets('very many columns become cards', (tester) async {
        await pump(tester, many, theme);
        expect(tester.takeException(), isNull);
        expect(find.byKey(MdTableLayout.cards.key), findsOneWidget);
      });

      testWidgets('header tap sorts asc, desc, then original', (tester) async {
        await pump(tester, numeric, theme);
        double y(String s) => tester.getTopLeft(find.text(s)).dy;
        await tester.tap(find.text('AREA'));
        await tester.pump();
        expect(y('Delhi') < y('Tokyo') && y('Tokyo') < y('Shanghai'), isTrue);
        await tester.tap(find.text('AREA'));
        await tester.pump();
        expect(y('Shanghai') < y('Tokyo') && y('Tokyo') < y('Delhi'), isTrue);
        await tester.tap(find.text('AREA'));
        await tester.pump();
        expect(y('Tokyo') < y('Delhi') && y('Delhi') < y('Shanghai'), isTrue);
      });
    });
  }

  testWidgets('streaming table keeps its layout once locked', (tester) async {
    // Header and two short rows: fits.
    const start = '| Option | Pros |\n|---|---|\n| A | fast |\n| B | cheap |';
    await pump(tester, start, AppTheme.light, streaming: true);
    expect(find.byKey(MdTableLayout.fit.key), findsOneWidget);
    // A later row is long: it may scroll but must not become cards.
    final longer = '$start\n| C | ${'a very long description ' * 6} |';
    await pump(tester, longer, AppTheme.light, streaming: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(MdTableLayout.cards.key), findsNothing);
  });

  test('numeric detection, sorting and TSV', () {
    final b = parseBlocks(numeric).whereType<MdTableBlock>().single;
    expect(mdNumericColumns(b), [false, true, true]);
    expect(mdParseNumber('1.5k'), 1500);
    expect(mdParseNumber('37.4M'), 37400000);
    expect(mdSortedOrder(b, 1, MdSort.asc, [false, true, true]), [2, 1, 0]);
    expect(mdTableToTsv(b).split('\n').first, 'City\tPop\tArea');
  });
}
