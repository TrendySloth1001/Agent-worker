import 'package:app/core/constants/m3_copy.dart';
import 'package:app/data/doc_models.dart';
import 'package:app/data/docs_api.dart';
import 'package:app/features/docs/docs_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';
import 'support/shot.dart';

final _now = DateTime(2026, 10, 12, 12);

class _FakeDocs implements DocsApi {
  @override
  Future<List<Doc>> list({String? conversationId}) async => [
    Doc(
      id: 'a',
      title: 'Chat Application Database & Architecture for Scale',
      updatedAt: _now.subtract(const Duration(minutes: 10)),
      status: DocStatus.done,
      sections: [for (var i = 0; i < 8; i++) DocSection(id: 's$i')],
    ),
    Doc(
      id: 'b',
      title: 'Technical Documentation Blueprint',
      updatedAt: _now.subtract(const Duration(hours: 10)),
      status: DocStatus.writing,
      sections: [
        for (var i = 0; i < 8; i++)
          DocSection(
            id: 's$i',
            status: i < 3 ? DocSectionStatus.done : DocSectionStatus.pending,
          ),
      ],
    ),
    Doc(
      id: 'c',
      title: '',
      status: DocStatus.failed,
      updatedAt: _now.subtract(const Duration(days: 2)),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadAppFonts);

  for (final (name, theme, scale) in renderCases) {
    testWidgets('docs list renders at 360dp ($name)', (tester) async {
      await pumpScreen(
        tester,
        DocsListScreen(api: _FakeDocs(), now: _now),
        theme: theme,
        textScale: scale,
        height: 800,
      );
      await shot(tester, 'docs_${name.replaceAll(' ', '_')}');
      expect(find.textContaining('Writing 3/8', findRichText: true), findsOneWidget);
      expect(find.textContaining('10 min ago', findRichText: true), findsOneWidget);
      expect(find.text(DocsCopy.untitled), findsOneWidget);
      // Rows keep their natural height: no stretched trailing chips.
      expect(
        tester.getSize(find.byType(DocListTile).first).height,
        lessThan(140),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('docs list search filters rows', (tester) async {
    await pumpScreen(tester, DocsListScreen(api: _FakeDocs(), now: _now));
    await tester.enterText(find.byType(EditableText), 'blueprint');
    await tester.pump();
    expect(find.text('Technical Documentation Blueprint'), findsOneWidget);
    expect(find.textContaining('Chat Application'), findsNothing);
    await tester.enterText(find.byType(EditableText), 'zzz');
    await tester.pump();
    expect(find.text(DocsCopy.noMatches), findsOneWidget);
  });
}
