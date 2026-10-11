import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/github_api.dart';
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
}
