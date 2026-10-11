import 'package:app/core/constants/app_sizes.dart';
import 'package:app/core/constants/widget_github.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/github_api.dart';
import 'package:app/features/chat/widgets/github/github_commits_card.dart';
import 'package:app/features/chat/widgets/github/github_common.dart';
import 'package:app/features/chat/widgets/github/github_my_repos_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> commit(int i) => {
  'sha': 'c$i'.padRight(40, '0'),
  'shortSha': 'c$i'.padRight(7, '0'),
  'message': 'Commit number $i',
  'authorName': i.isEven ? 'alice' : 'bob',
  'date': '2026-10-11T16:40:00Z',
};

GhRepo repo(String full, {bool private = false, String? lang, int stars = 0}) {
  final parts = full.split('/');
  return GhRepo({
    'fullName': full,
    'owner': parts[0],
    'name': parts[1],
    'description': 'About $full',
    'private': private,
    'language': lang,
    'stars': stars,
    'pushedAt': '2026-10-01T00:00:00Z',
  });
}

Future<void> pump(WidgetTester tester, Widget child, ThemeData theme) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  test('highlight ranges merge overlapping tokens', () {
    expect(GhHighlight.ranges('report-card-generator', ['report', 'card']), [
      (0, 6),
      (7, 11),
    ]);
    expect(GhHighlight.ranges('Vector DB', ['vector', 'ector']), [(0, 6)]);
    expect(GhHighlight.ranges('abc', ['x']), isEmpty);
  });

  test('count strings', () {
    expect(
      GithubPagingStrings.commitsOf(120, 1485074),
      '120 OF 1,485,074 COMMITS',
    );
    expect(GithubPagingStrings.commitsOf(5, null), '5 COMMITS');
    expect(GithubPagingStrings.reposOf(3, 69), '3 OF 69 REPOS');
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'commits page in as the list fills (${theme.brightness.name})',
      (tester) async {
        final afters = <String?>[];
        await pump(
          tester,
          GhCommitsPaged(
            repo: const GhRef('o', 'r'),
            loader: (branch, q, after) async {
              afters.add(after);
              final start = after == null ? 0 : int.parse(after);
              return GhCommitPage({
                'items': [for (var i = start; i < start + 3; i++) commit(i)],
                'totalCount': 6,
                'nextCursor': start == 0 ? '3' : null,
              });
            },
          ),
          theme,
        );
        await tester.pump();
        await tester.pump();
        expect(afters, [null, '3']);
        expect(find.text('Commit number 5'), findsOneWidget);
        expect(find.text('6 OF 6 COMMITS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'my repos: search, filters and count (${theme.brightness.name})',
      (tester) async {
        final repos = [
          repo('nick/report-card-generator', lang: 'Dart'),
          repo('nick/keepit', private: true, lang: 'TypeScript', stars: 5),
          repo('acme/tools', lang: 'Go', stars: 9),
        ];
        await pump(
          tester,
          GhMyRepos(
            loader: (_) async => (
              GhMe({'login': 'nick', 'url': 'https://github.com/nick'}),
              repos,
            ),
            searcher: (q) async => GhRepoSearch({
              'items': [
                {
                  'fullName': 'nick/report-card-generator',
                  'matched': ['report'],
                },
              ],
              'tokens': ['reprot'],
            }),
          ),
          theme,
        );
        expect(find.text('3 REPOS'), findsOneWidget);
        final privateChip = find.widgetWithText(
          GhFilterChip,
          GithubRepoFilterStrings.privateOnly,
        );
        await tester.ensureVisible(privateChip);
        await tester.pump();
        await tester.tap(privateChip);
        await tester.pump();
        expect(find.text('1 OF 3 REPOS'), findsOneWidget);
        await tester.tap(privateChip);
        await tester.pump();
        // Typo: nothing matches locally, the server ranking finds it.
        await tester.enterText(find.byType(TextField), 'reprot');
        await tester.pump();
        expect(find.text('0 OF 3 REPOS'), findsOneWidget);
        await tester.pump(AppDurations.searchDebounce);
        await tester.pump();
        expect(find.text('1 OF 3 REPOS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
