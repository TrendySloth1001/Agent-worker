import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/constants/mascot.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/illustration.dart';
import 'package:app/core/widgets/mascot.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  test('every state maps to an illustration', () {
    for (final s in MascotState.values) {
      expect(s.illustration, isA<IllustrationKind>());
    }
    expect(MascotState.github.illustration, IllustrationKind.github);
    expect(MascotState.idle.illustration, IllustrationKind.hello);
  });

  testWidgets('large sizes draw the illustration', (tester) async {
    await tester.pumpWidget(
      _host(const Mascot(state: MascotState.idle, size: MascotSizes.large)),
    );
    expect(find.byType(Illustration), findsOneWidget);
  });

  testWidgets('compact slots draw nothing', (tester) async {
    await tester.pumpWidget(
      _host(const Mascot(state: MascotState.writing, size: MascotSizes.small)),
    );
    expect(find.byType(Illustration), findsNothing);
  });
}
