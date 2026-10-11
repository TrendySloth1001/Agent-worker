import 'dart:async';

import 'package:app/core/constants/widget_github.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/github_api.dart';
import 'package:app/features/chat/widgets/github/github_commits_card.dart';
import 'package:app/features/chat/widgets/github/github_common.dart';
import 'package:app/features/chat/widgets/github/github_graph_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> c(
  String sha,
  List<String> parents, {
  List<String> refs = const [],
}) => {
  'sha': sha.padRight(40, '0'),
  'parents': [for (final p in parents) p.padRight(40, '0')],
  'subject': 'Commit $sha with a fairly long subject line to test ellipsis',
  'author': 'octocat',
  'date': '2026-10-11T16:40:00Z',
  'refs': refs,
};

GhGraph sample() => GhGraph({
  'repo': 'o/r',
  'defaultBranch': 'main',
  'branches': [
    {'name': 'main', 'sha': 'a'.padRight(40, '0'), 'isDefault': true},
    {'name': 'feature/x', 'sha': 'f'.padRight(40, '0'), 'isDefault': false},
  ],
  'commits': [
    c('f', ['e'], refs: ['feature/x']),
    c('a', ['b', 'd'], refs: ['main']),
    c('d', ['e']),
    c('b', ['e']),
    c('e', ['gone']),
  ],
  'truncated': true,
});

void main() {
  test('block parsing', () {
    final s = GhGraphSpec.parse(
      'vercel/next.js\nbranches: canary, x\nlimit: 999',
    )!;
    expect(s.ref.full, 'vercel/next.js');
    expect(s.branches, ['canary', 'x']);
    expect(s.limit, 300);
    expect(GhGraphSpec.parse('not a repo'), isNull);
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('renders rows, pills and chips (${theme.brightness.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: GhGraphView(
              spec: const GhGraphSpec(GhRef('o', 'r')),
              height: 480,
              loader: (_) async => sample(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('feature/x'), findsNWidgets(2)); // chip + ref pill
      expect(find.text('a000000'), findsOneWidget);
      expect(find.textContaining('5 COMMITS'), findsOneWidget);
    });
  }
  pagingTests();
}

GhGraph page(List<Map<String, dynamic>> commits, {String? next, int? total}) =>
    GhGraph({
      'repo': 'o/r',
      'defaultBranch': 'main',
      'branches': [
        {'name': 'main', 'sha': 'a'.padRight(40, '0'), 'isDefault': true},
      ],
      'commits': commits,
      'truncated': next != null,
      'nextCursor': next,
      'totalCount': total,
    });

Future<void> pumpView(
  WidgetTester tester,
  GhGraphView view, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: view),
    ),
  );
  await tester.pump();
}

void pagingTests() {
  testWidgets('appends older pages until the history ends', (tester) async {
    final cursors = <String>[];
    await pumpView(
      tester,
      GhGraphView(
        spec: const GhGraphSpec(GhRef('o', 'r')),
        height: 480,
        loader: (_) async => page(
          [
            c('a', ['b'], refs: ['main']),
            c('b', ['c']),
          ],
          next: 'p2',
          total: 4,
        ),
        pageLoader: (cursor) async {
          cursors.add(cursor);
          return page([
            c('c', ['d']),
            c('d', []),
          ], total: 4);
        },
      ),
    );
    // The short first page does not fill the view: the next one loads.
    await tester.pump();
    await tester.pump();
    expect(cursors, ['p2']);
    expect(find.text('d000000'), findsOneWidget);
    expect(find.textContaining('4 OF 4 COMMITS'), findsOneWidget);
    expect(find.text(GithubPagingStrings.loadAll), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LOAD ALL shows while older history remains', (tester) async {
    await pumpView(
      tester,
      GhGraphView(
        spec: const GhGraphSpec(GhRef('o', 'r')),
        height: 480,
        loader: (_) async => page(
          [
            c('a', ['b'], refs: ['main']),
          ],
          next: 'p2',
          total: 900,
        ),
        pageLoader: (_) => Completer<GhGraph>().future,
      ),
    );
    expect(find.text(GithubPagingStrings.loadAll), findsOneWidget);
    expect(find.textContaining('1 OF 900 COMMITS'), findsOneWidget);
    expect(find.text(GithubPagingStrings.loadingMore), findsOneWidget);
  });

  testWidgets('an open commit spans the width below its row', (tester) async {
    await pumpView(
      tester,
      GhGraphView(
        spec: const GhGraphSpec(GhRef('o', 'r')),
        height: 480,
        loader: (_) async => sample(),
      ),
    );
    await tester.tap(find.textContaining('Commit d with'));
    await tester.pump();
    final detail = find.byType(GhCommitDetail);
    expect(detail, findsOneWidget);
    // Not inside the sideways-panned text columns.
    expect(
      find.ancestor(of: detail, matching: find.byType(OverflowBox)),
      findsNothing,
    );
    final box = tester.getRect(detail);
    expect(box.right, lessThanOrEqualTo(360));
    expect(box.width, greaterThan(240));
    await tester.pump(const Duration(seconds: 1));
  });
}
