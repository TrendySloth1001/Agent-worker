import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/illustration.dart';
import 'package:app/core/widgets/mascot.dart';
import 'package:app/core/widgets/rotating_illustration.dart';
import 'package:app/features/chat/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';

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
      final art = tester.widget<RotatingIllustration>(
        find.byType(RotatingIllustration),
      );
      expect(art.kinds, IllustrationKind.home);
      await tester.pumpWidget(const SizedBox());
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
