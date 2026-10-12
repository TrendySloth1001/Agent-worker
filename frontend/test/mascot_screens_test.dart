import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/mascot.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/doc_models.dart';
import 'package:app/features/chat/widgets/empty_state.dart';
import 'package:app/features/chat/widgets/round_table_panel.dart';
import 'package:app/features/docs/doc_controller.dart';
import 'package:app/features/docs/doc_progress.dart';
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
    testWidgets('round table wait shows the mascot ($name)', (tester) async {
      final m = ChatMessage(role: Role.assistant, isStreaming: true)
        ..tablePhase = 'researching'
        ..tableElapsedMs = 42000
        ..tableEtaMs = 90000
        ..tableStamp = DateTime.now();
      await pumpScreen(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: RoundTablePanel(message: m)),
          ),
        ),
        theme: theme,
      );
      expect(find.byType(Mascot), findsOneWidget);
      expect(_mascot(tester), MascotState.searching);
      expect(tester.takeException(), isNull);
    });

    testWidgets('doc progress maps its stage to a mascot ($name)', (
      tester,
    ) async {
      final c = DocController(
        'd1',
        seed: Doc(id: 'd1', status: 'writing'),
      );
      await pumpScreen(
        tester,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: DocProgressBar(controller: c)),
          ),
        ),
        theme: theme,
      );
      expect(_mascot(tester), MascotState.writing);
      expect(tester.takeException(), isNull);
    });

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
