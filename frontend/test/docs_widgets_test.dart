import 'package:app/core/constants/docs.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/doc_models.dart';
import 'package:app/data/files_api.dart';
import 'package:app/features/chat/widgets/chat_input.dart';
import 'package:app/features/docs/doc_card.dart';
import 'package:app/features/docs/doc_controller.dart';
import 'package:app/features/docs/doc_registry.dart';
import 'package:app/features/docs/doc_screen.dart';
import 'package:app/features/docs/doc_toc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/doc_fake.dart';

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder rich(String text) => find.textContaining(text, findRichText: true);

/// A finished doc whose sections are long enough to scroll.
Map<String, dynamic> doneDoc() {
  String para(String w) =>
      List.filled(40, '$w sentence for scrolling.').join(' ');
  return {
    'doc': {
      'id': 'd1',
      'title': 'Sodium and health',
      'subtitle': 'What the evidence says',
      'status': 'done',
      'words': 1200,
      'outline': {
        'sections': [
          {'id': 's1', 'heading': 'Why sodium matters', 'goal': 'g'},
          {'id': 's2', 'heading': 'How much is too much', 'goal': 'g'},
          {'id': 'takeaways', 'heading': 'Key takeaways', 'goal': 'g'},
          {'id': 'references', 'heading': 'References', 'kind': 'references'},
        ],
      },
      'sections': [
        for (final (i, id) in ['s1', 's2', 'takeaways'].indexed)
          {
            'sectionId': id,
            'ord': i,
            'status': 'done',
            'markdown': '${para(id)} [W1]\n\n${para(id)}\n\n${para(id)}',
            'usedIds': ['W1'],
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
}

Future<DocController> pumpReader(
  WidgetTester tester,
  FakeDocsServer server,
  ThemeData theme,
) async {
  final c = DocController('d1', api: server.api());
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: DocScreen(controller: c),
    ),
  );
  await tester.pump();
  return c;
}

Future<void> finish(
  WidgetTester tester,
  DocController c,
  FakeDocsServer s,
) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  await s.closeEvents();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    final mode = theme.brightness.name;

    testWidgets('reader: outline skeletons, then streamed sections ($mode)', (
      tester,
    ) async {
      await setSize(tester, const Size(360, 780));
      final server = FakeDocsServer()
        ..onConnect = [
          sse('doc_snapshot', {
            'doc': {'id': 'd1', 'status': 'planning', 'prompt': 'salt'},
          }),
        ];
      final c = await pumpReader(tester, server, theme);
      expect(find.text(DocStrings.phase('planning')), findsOneWidget);
      final run = scriptedRun();
      // Outline: every section is a skeleton with its goal.
      for (final (e, d) in run.take(3)) {
        server.emit(e, d);
      }
      await tester.pump();
      await tester.pump();
      expect(find.text('Sodium and health'), findsOneWidget);
      expect(find.text('Why sodium matters'), findsWidgets);
      expect(find.text('Explain the role of sodium.'), findsOneWidget);
      expect(
        find.text(DocStrings.pending, skipOffstage: false),
        findsNWidgets(3),
      );
      expect(find.text(DocStrings.stop), findsOneWidget);

      // First section streams: its text shows, the others stay skeletons.
      final firstDone = run.indexWhere(
        (e) => e.$1 == 'doc_section_done' && e.$2['sectionId'] == 's1',
      );
      for (final (e, d) in run.sublist(3, firstDone)) {
        server.emit(e, d);
      }
      await tester.pump();
      await tester.pump(DocSizes.streamThrottle);
      expect(rich('Sodium keeps fluids'), findsWidgets);
      expect(find.text(DocStrings.writingNow), findsWidgets);
      expect(
        find.text('Give the limits.', skipOffstage: false),
        findsOneWidget,
      );

      for (final (e, d) in run.sublist(firstDone)) {
        server.emit(e, d);
      }
      await tester.pump();
      await tester.pump(DocSizes.streamThrottle);
      expect(find.text(DocStrings.pending), findsNothing);
      expect(find.text(DocStrings.stop), findsNothing);
      expect(rich('Adults should eat under 2 g a day'), findsWidgets);
      expect(find.textContaining('· DONE'), findsOneWidget);
      // Bibliography: cited sources in first-use order.
      expect(
        find.text(DocStrings.references, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'WHO sodium fact sheet',
          findRichText: true,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester, c, server);
    });

    testWidgets('phone TOC: pill opens the sheet, a line jumps ($mode)', (
      tester,
    ) async {
      await setSize(tester, const Size(360, 700));
      final server = FakeDocsServer()
        ..onConnect = [sse('doc_snapshot', doneDoc())];
      final c = await pumpReader(tester, server, theme);
      await tester.pump();
      expect(find.byType(DocTocPill), findsOneWidget);
      expect(find.text(DocStrings.sectionOf(1, 3)), findsOneWidget);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, 0);
      await tester.tap(find.byType(DocTocPill));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, 'Key takeaways'));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(500));
      expect(find.text(DocStrings.sectionOf(3, 3)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, c, server);
    });
  }

  testWidgets('wide screens get a TOC rail; tapping jumps', (tester) async {
    await setSize(tester, const Size(1200, 800));
    final server = FakeDocsServer()
      ..onConnect = [sse('doc_snapshot', doneDoc())];
    final c = await pumpReader(tester, server, AppTheme.light);
    await tester.pump();
    expect(find.byType(DocTocRail), findsOneWidget);
    expect(find.byType(DocTocPill), findsNothing);
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.widgetWithText(InkWell, 'How much is too much'));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(200));
    expect(tester.takeException(), isNull);
    await finish(tester, c, server);
  });

  group('chat card', () {
    Future<void> card(WidgetTester tester, DocLink link, DocRegistry r) async {
      await setSize(tester, const Size(360, 600));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DocCard(link: link, registry: r),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('saved states: done, failed, interrupted', (tester) async {
      final server = FakeDocsServer();
      final r = DocRegistry(api: server.api());
      for (final (status, label) in [
        ('done', 'DONE'),
        ('failed', 'FAILED'),
        ('interrupted', 'INTERRUPTED'),
        ('partial', 'PARTIAL'),
      ]) {
        await card(
          tester,
          DocLink.fromMeta({
            'doc': {
              'id': 'd-$status',
              'title': 'Salt guide',
              'status': status,
              'words': 3420,
              'sections': ['done', 'done', if (status != 'done') 'failed'],
            },
          })!,
          r,
        );
        expect(find.text(label), findsOneWidget);
        expect(find.text('Salt guide'), findsOneWidget);
        expect(find.text(DocStrings.open), findsOneWidget);
        expect(find.textContaining('3,420 WORDS'), findsOneWidget);
      }
      // Saved as finished: no stream was opened.
      expect(server.requests, isEmpty);
      r.clear();
    });

    testWidgets('running: follows the live doc to done', (tester) async {
      final server = FakeDocsServer()
        ..onConnect = [
          sse('doc_snapshot', {
            'doc': {
              'id': 'd1',
              'title': 'Live title',
              'status': 'writing',
              'outline': {
                'sections': [
                  {'id': 's1', 'heading': 'A'},
                  {'id': 's2', 'heading': 'B'},
                ],
              },
              'sections': [
                {'sectionId': 's1', 'status': 'done', 'markdown': 'x y'},
                {'sectionId': 's2', 'status': 'writing', 'markdown': 'z'},
              ],
            },
          }),
        ];
      final r = DocRegistry(api: server.api());
      await card(
        tester,
        const DocLink(id: 'd1', title: 'Saved', status: 'planning'),
        r,
      );
      await tester.pump();
      expect(find.text('Live title'), findsOneWidget);
      expect(find.text('WRITING'), findsOneWidget);
      expect(find.textContaining('1/2 SECTIONS'), findsOneWidget);
      server.emit('doc_section_done', {'sectionId': 's2', 'markdown': 'z z'});
      server.emit('doc_done', {'status': 'done', 'words': 40});
      await tester.pump();
      await tester.pump();
      expect(find.text('DONE'), findsOneWidget);
      expect(find.textContaining('40 WORDS'), findsOneWidget);
      expect(find.textContaining('2/2 SECTIONS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      r.clear();
      await server.closeEvents();
    });
  });

  testWidgets('composer: DOC chip, length picker, WRITE AS DOCUMENT?', (
    tester,
  ) async {
    await setSize(tester, const Size(360, 640));
    var doc = false;
    String? sentAsDoc;
    String length = DocConfig.defaultLength;
    Widget input() => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatInput(
            onSend: (_, _) {},
            onStop: () {},
            isStreaming: false,
            webSearch: true,
            knowledge: false,
            onToggleWebSearch: () {},
            onToggleKnowledge: () {},
            onToggleRoundTable: () {},
            doc: doc,
            onToggleDoc: () => doc = !doc,
            docLength: length,
            onDocLength: (v) => length = v,
            onSendAsDoc: (text, List<FileInfo> _) => sentAsDoc = text,
          ),
        ),
      ),
    );
    await tester.pumpWidget(input());
    expect(find.text(DocStrings.chip), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'what is salt');
    await tester.pump();
    expect(find.text(DocStrings.suggest), findsNothing);
    await tester.enterText(
      find.byType(TextField),
      'Write a short report about salt',
    );
    await tester.pump();
    expect(find.text(DocStrings.suggest), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text(DocStrings.suggest));
    await tester.pumpAndSettle();
    expect(sentAsDoc, 'Write a short report about salt');

    // DOC on: no hint, the length row shows.
    await tester.tap(find.text(DocStrings.chip));
    await tester.pumpWidget(input());
    await tester.enterText(find.byType(TextField), 'write a guide to salt');
    await tester.pump();
    expect(find.text(DocStrings.suggest), findsNothing);
    await tester.tap(find.text(DocStrings.lengthLong));
    expect(length, DocConfig.lengthLong);
    expect(tester.takeException(), isNull);
  });
}
