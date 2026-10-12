import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/mascot.dart';
import 'package:app/features/chat/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';

MascotState _mascot(WidgetTester tester) =>
    tester.widget<Mascot>(find.byType(Mascot)).state;

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('empty chat shows sparky ($name)', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: EmptyState()),
        theme: theme,
      );
      expect(_mascot(tester), MascotState.idle);
      expect(tester.takeException(), isNull);
    });
  }

  test('stages map to mascot states', () {
    expect(MascotState.forTablePhase('seating'), MascotState.thinking);
    expect(MascotState.forTablePhase('drafting'), MascotState.writing);
    expect(MascotState.forDocPhase('research'), MascotState.searching);
    expect(MascotState.forDocPhase('outline'), MascotState.thinking);
    expect(MascotState.forDocPhase('finish'), MascotState.celebrating);
  });
}
