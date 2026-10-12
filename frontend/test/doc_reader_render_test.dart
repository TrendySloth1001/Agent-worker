import 'package:app/core/constants/docs.dart';
import 'package:app/features/docs/doc_controller.dart';
import 'package:app/features/docs/doc_screen.dart';
import 'package:app/features/docs/doc_toc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'docs_widgets_test.dart' show finish, setSize;
import 'support/doc_fake.dart';
import 'support/render.dart';
import 'support/shot.dart';

const _prose =
    'Sodium is an essential mineral that regulates fluid balance, nerve '
    'signalling and muscle contraction. Most adults eat far more than the '
    'body needs, and the gap between intake and need is where the health '
    'risk lives. The evidence on blood pressure is the strongest, but the '
    'picture for heart disease is more nuanced. [W1]';

Map<String, dynamic> _doc({String status = 'done'}) => {
  'doc': {
    'id': 'd1',
    'title': 'Sodium and health: what the evidence says',
    'subtitle': 'A practical guide to salt, blood pressure and everyday food',
    'summary':
        'Most adults consume about twice the recommended sodium. This guide '
        'reviews the evidence on blood pressure and cardiovascular risk and '
        'turns it into practical limits.',
    'status': status,
    'words': 1200,
    'outline': {
      'sections': [
        {'id': 's1', 'heading': 'Why sodium matters', 'goal': 'Explain role'},
        {'id': 's2', 'heading': 'How much is too much', 'goal': 'Limits'},
        {'id': 's3', 'heading': 'Reading food labels', 'goal': 'Practice'},
        {'id': 'references', 'heading': 'References', 'kind': 'references'},
      ],
      'glossary': [
        {'term': 'Sodium', 'definition': 'The element in table salt.'},
        {'term': 'DASH', 'definition': 'A diet pattern that lowers pressure.'},
      ],
    },
    'sections': [
      {
        'sectionId': 's1',
        'ord': 0,
        'status': 'done',
        'markdown': '$_prose\n\n$_prose',
        'usedIds': ['W1'],
      },
      {
        'sectionId': 's2',
        'ord': 1,
        'status': 'done',
        'markdown': '$_prose\n\n- First point\n- Second point',
        'usedIds': ['W1'],
      },
      {
        'sectionId': 's3',
        'ord': 2,
        'status': status == 'done' ? 'done' : 'writing',
        'markdown': status == 'done' ? _prose : '',
      },
      {
        'sectionId': 'references',
        'ord': 3,
        'status': 'done',
        'markdown': '1. [W1] [WHO](https://who.int) · who.int',
      },
    ],
    'sources': [
      {
        'id': 'W1',
        'kind': 'web',
        'title': 'WHO sodium fact sheet',
        'url': 'https://who.int/sodium',
        'site': 'who.int',
      },
    ],
  },
};

/// Render matrix for the reader chrome: 360dp, light/dark/1.3x.
void main() {
  setUpAll(loadAppFonts);

  for (final (name, theme, scale) in renderCases) {
    final tag = name.replaceAll(' ', '_');

    testWidgets('reader chrome renders a finished doc ($name)', (tester) async {
      await setSize(tester, const Size(360, 780));
      final server = FakeDocsServer()
        ..highlights = [
          {
            'id': 'h1',
            'sectionId': 's1',
            'quote': 'the gap between intake and need',
            'note': 'Key idea for the summary',
            'color': 'accent',
          },
          {
            'id': 'h2',
            'sectionId': 's1',
            'quote': 'picture for heart disease is more nuanced',
            'color': 'accent',
            'thread': [
              {
                'id': 'q1',
                'q': 'What does nuanced mean here?',
                'a': 'Studies disagree on whether very low sodium helps.',
              },
            ],
          },
        ]
        ..onConnect = [sse('doc_snapshot', _doc())];
      final c = await _pump(tester, server, theme, scale);
      await shot(tester, 'reader_top_$tag');
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
      await tester.pump(const Duration(milliseconds: 600));
      await shot(tester, 'reader_mid_$tag');

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
      await tester.pump(const Duration(milliseconds: 600));
      await shot(tester, 'reader_end_$tag');
      expect(find.text(DocStrings.continueWriting), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(DocTocPill));
      await tester.pumpAndSettle();
      await shot(tester, 'reader_toc_$tag');
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(DocStrings.notesOpen));
      await tester.pumpAndSettle();
      await shot(tester, 'reader_notes_$tag');
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 40000));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.bySemanticsLabel(DocStrings.menuTitle).first);
      await tester.pumpAndSettle();
      await shot(tester, 'reader_menu_$tag');
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();
      await finish(tester, c, server);
    });

    testWidgets('reader chrome renders a doc being written ($name)', (
      tester,
    ) async {
      await setSize(tester, const Size(360, 780));
      final server = FakeDocsServer()
        ..onConnect = [
          sse('doc_snapshot', _doc(status: 'writing')),
          sse('doc_status', {'phase': 'writing', 'done': 2, 'total': 3}),
        ];
      final c = await _pump(tester, server, theme, scale);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, 'reader_writing_$tag');
      expect(tester.takeException(), isNull);
      await finish(tester, c, server);
    });
  }
}

Future<DocController> _pump(
  WidgetTester tester,
  FakeDocsServer server,
  ThemeData theme,
  double scale,
) async {
  final c = DocController('d1', api: server.api());
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: DocScreen(controller: c),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  return c;
}
