import 'package:app/core/app_scope.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/doc_models.dart';
import 'package:app/features/chat/widgets/markdown/app_markdown.dart';
import 'package:app/features/chat/widgets/markdown/citation_chip.dart';
import 'package:app/features/docs/doc_export.dart';
import 'package:app/features/docs/doc_highlights.dart';
import 'package:app/features/docs/doc_references.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sources = [
  Citation(
    id: 'W1',
    title: 'Hooks API',
    url: 'https://github.com/acme/widget',
    site: 'github.com',
  ),
  Citation(
    id: 'W2',
    title: 'Sodium',
    url: 'https://en.wikipedia.org/wiki/Sodium',
    site: 'en.wikipedia.org',
  ),
  Citation(
    id: 'W3',
    title: 'Docs',
    url: 'https://developer.mozilla.org/x',
    site: 'developer.mozilla.org',
  ),
  Citation(
    id: 'W4',
    title: 'Another page',
    url: 'https://en.wikipedia.org/wiki/Salt',
    site: 'en.wikipedia.org',
  ),
  Citation(
    id: 'W120',
    title: 'Late',
    url: 'https://late.dev',
    site: 'late.dev',
  ),
  Citation(
    id: 'K1',
    kind: CitationKind.kb,
    title: 'My notes',
    url: '',
    site: '',
  ),
];

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _md(String data, {bool streaming = false}) =>
    _host(AppMarkdown(data: data, citations: _sources, streaming: streaming));

Finder _text(String s) => find.textContaining(s, findRichText: true);

void main() {
  group('inline chips in doc sections', () {
    testWidgets('a tag becomes a chip with the site name, not [W1]', (
      tester,
    ) async {
      await tester.pumpWidget(_md('Sodium is a mineral [W2] and more.'));
      expect(find.byType(CitationChip), findsOneWidget);
      expect(_text('wikipedia'), findsOneWidget);
      expect(_text('[W2]'), findsNothing);
      expect(_text('Sodium is a mineral'), findsOneWidget);
    });

    testWidgets('three-digit ids, KB tags and GitHub repo names', (
      tester,
    ) async {
      await tester.pumpWidget(_md('One [W120]. Two [K1]. Three [W1].'));
      expect(find.byType(CitationChip), findsNWidgets(3));
      expect(_text('late'), findsOneWidget);
      expect(_text('My notes'), findsOneWidget);
      expect(_text('widget'), findsOneWidget);
      expect(_text('[W'), findsNothing);
    });

    testWidgets('adjacent tags collapse into one chip with +N', (tester) async {
      await tester.pumpWidget(_md('Claim [W1][W3] and again [W2], [W4].'));
      // [W1][W3] -> one chip "widget +1"; [W2], [W4] share a site -> one.
      expect(find.byType(CitationChip), findsNWidgets(2));
      expect(_text('+1'), findsOneWidget);
      expect(_text('widget'), findsOneWidget);
      expect(_text('wikipedia'), findsOneWidget);
      expect(_text('[W'), findsNothing);
    });

    testWidgets('a bracketed list [W1, W3] is also one chip', (tester) async {
      await tester.pumpWidget(_md('Claim [W1, W3].'));
      expect(find.byType(CitationChip), findsOneWidget);
      expect(_text('+1'), findsOneWidget);
    });

    testWidgets('streaming: chip once the tag closes, nothing before', (
      tester,
    ) async {
      await tester.pumpWidget(_md('Streaming text [W', streaming: true));
      expect(_text('[W'), findsNothing);
      expect(find.byType(CitationChip), findsNothing);
      await tester.pumpWidget(_md('Streaming text [W2]', streaming: true));
      expect(find.byType(CitationChip), findsOneWidget);
      expect(_text('wikipedia'), findsOneWidget);
    });

    testWidgets('tapping a grouped chip lists its sources', (tester) async {
      await tester.pumpWidget(_md('Claim [W1][W3].'));
      await tester.tap(find.byType(CitationChip));
      await tester.pumpAndSettle();
      expect(find.text('Hooks API'), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
      expect(find.text('mozilla'), findsOneWidget);
    });

    test('prepareCitations groups runs and drops unknown ids', () {
      expect(prepareCitations('a [W1][W3] b', _sources), 'a [W1+W3] b');
      expect(prepareCitations('a [W2] [W4] b', _sources), 'a [W2] b');
      expect(prepareCitations('a [W9] b', _sources), 'a  b');
      expect(
        prepareCitations(
          '`[W1]`\n```\n[W1][W3]\n```',
          _sources,
        ).contains('[W1+W3]'),
        isFalse,
      );
    });
  });

  group('selection and highlights with chips', () {
    test('a quote across a cited sentence still finds its text', () {
      const md = 'Salt raises pressure [W1][W3] in most adults [W2].';
      final section = DocSection(id: 's1', markdown: md);
      // Selecting over the chips copies object characters.
      final h = anchorHighlight(section, 'pressure ￼ in most adults');
      expect(h.quote, 'pressure in most adults');
      expect(h.prefix, endsWith('raises '));
      final out = applyHighlights(md, [h.quote]);
      expect(out, 'Salt raises ==pressure== [W1][W3] ==in most adults== [W2].');
    });

    testWidgets('highlighted text with a chip still renders both', (
      tester,
    ) async {
      final out = applyHighlights('Salt raises pressure [W2] a lot.', [
        'raises pressure a lot',
      ]);
      await tester.pumpWidget(_md(out));
      expect(find.byType(CitationChip), findsOneWidget);
      expect(_text('=='), findsNothing);
    });
  });

  group('references', () {
    final doc = Doc(
      id: 'd1',
      title: 'T',
      sources: _sources,
      sections: [
        DocSection(
          id: 's1',
          markdown: 'A [W2] b [W1][W2] c [K1].',
          status: 'done',
        ),
      ],
    );

    test('cite counts and first-use order', () {
      expect(doc.references.map((c) => c.id), ['W2', 'W1', 'K1']);
      expect(doc.citeCounts, {'W2': 2, 'W1': 1, 'K1': 1});
      final groups = groupReferences(doc.references);
      expect(groups.map((g) => g.$1), [RefGroup.web, RefGroup.knowledge]);
    });

    testWidgets('grouped rows: name, title, domain, count', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsController.load();
      await tester.pumpWidget(
        AppScope(
          settings: settings,
          usage: UsageController(UsageApi('http://localhost:1')),
          api: ChatApi(),
          baseUrl: 'http://localhost:1',
          child: _host(
            DocReferences(references: doc.references, counts: doc.citeCounts),
          ),
        ),
      );
      expect(find.text('wikipedia'), findsOneWidget);
      expect(find.text('Sodium'), findsOneWidget);
      expect(find.text('en.wikipedia.org'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
      expect(find.text('WEB  2'), findsOneWidget);
      expect(find.text('KNOWLEDGE BASE  1'), findsOneWidget);
      await tester.tap(find.text('Sodium'));
      await tester.pumpAndSettle();
      expect(find.text('VISIT'), findsOneWidget);
    });
  });

  group('export text', () {
    test('numberCitations: links, collapsed, unknown dropped', () {
      const nums = {'W2': 1, 'W1': 2};
      expect(
        numberCitations('A [W2] b [W1][W2] c [W9].', nums, links: true),
        'A<sup>[1](#ref-1)</sup> b<sup>[1](#ref-1),[2](#ref-2)</sup> c.',
      );
      expect(
        numberCitations('A [W2], [W1] b.', nums, links: false),
        'A [1,2] b.',
      );
    });
  });
}
