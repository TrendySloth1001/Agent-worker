import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/chat/preview/widget_gallery.dart';
import 'package:app/features/chat/widgets/rich/compare_card.dart';
import 'package:app/features/chat/widgets/rich/progress_card.dart';
import 'package:app/features/chat/widgets/rich/tree_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseCompare reads options, points and the pick flag', () {
    final d = parseCompare(
      'title: T\noption: A | tag | pick\n+ good\n- bad\noption: B\n+ ok',
    )!;
    expect(d.options, hasLength(2));
    expect(d.options[0].pick, isTrue);
    expect(d.options[0].pros, ['good']);
    expect(d.options[0].cons, ['bad']);
    expect(parseCompare('garbage'), isNull);
    expect(parseCompare('option: A'), isNull);
  });

  test('parseProgress defaults max and drops bad rows', () {
    final d = parseProgress(
      'bar: A | 80\nrating: B | 4\nbar: C | x\nbar: | 3',
    )!;
    expect(d.rows, hasLength(2));
    expect(d.rows[0].max, 100);
    expect(d.rows[1].max, 5);
    expect(d.rows[1].rating, isTrue);
    expect(parseProgress('nothing'), isNull);
  });

  test('parseTree nests by indentation', () {
    final d = parseTree('title: X\nRoot\n  a\n    a1\n  b\n')!;
    expect(d.title, 'X');
    expect(d.roots, hasLength(1));
    expect(d.roots[0].children.map((c) => c.text), ['a', 'b']);
    expect(d.roots[0].children[0].children.single.text, 'a1');
    expect(parseTree('   \n'), isNull);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('gallery renders at 360px without errors ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const WidgetGalleryScreen()),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);

      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
    });
  }
}
