import 'package:app/core/constants/greetings.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/illustration.dart';
import 'package:app/core/widgets/rotating_illustration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never repeats the last greeting and uses the first name', () {
    var last = Greetings.pick(name: 'Nikhil Binwal').title;
    for (var i = 0; i < 50; i++) {
      final g = Greetings.pick(name: 'Nikhil Binwal');
      expect(g.title, isNot(last));
      expect(g.title, isNot(contains('Binwal')));
      last = g.title;
    }
  });

  test('time of day greeting', () {
    final all = <String>{};
    for (var i = 0; i < 200; i++) {
      all.add(Greetings.pick(now: DateTime(2026, 1, 1, 8)).title);
    }
    expect(all, contains('Good morning'));
    expect(all, contains('Hey there'));
  });

  testWidgets('a non-cycling slot keeps its scene', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const RotatingIllustration(
          kinds: IllustrationKind.home,
          height: 100,
          cycle: false,
          initialIndex: 0,
        ),
      ),
    );
    final first = tester.widget<Illustration>(find.byType(Illustration)).kind;
    await tester.pump(const Duration(seconds: 30));
    expect(tester.widget<Illustration>(find.byType(Illustration)).kind, first);
    await tester.pumpWidget(const SizedBox());
  });
}
