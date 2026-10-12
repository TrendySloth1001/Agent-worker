import 'package:app/data/github_api.dart';

import 'github_fakes.dart';

String _ago(Duration d) => DateTime.now().subtract(d).toIso8601String();

Map<String, dynamic> _u(String login) => {
  'login': login,
  'avatar': '',
  'url': 'https://github.com/$login',
};

const allowAll = {
  'comment': true,
  'react': true,
  'review': true,
  'approve': true,
  'merge': true,
  'close': true,
  'reopen': false,
  'label': true,
  'assign': true,
  'edit': true,
  'markReady': false,
};

const readOnly = {
  'comment': false,
  'react': false,
  'review': false,
  'approve': false,
  'merge': false,
  'close': false,
  'reopen': false,
  'label': false,
  'assign': false,
  'edit': false,
  'markReady': false,
};

const scopeReason =
    "Your GitHub token can't write here. Reconnect GitHub with repo access";

Map<String, dynamic> pullJson({
  String state = 'open',
  Map<String, bool> can = allowAll,
  Map<String, String> why = const {},
  bool canWrite = true,
  bool needsReconnect = false,
  String mergeableState = 'clean',
}) => {
  'repo': 'nickrivera/sparky',
  'number': 214,
  'title': 'Add the Apps hub and GitHub screen',
  'state': state,
  'isPr': true,
  'body':
      'Adds an **Apps hub** with connectors and a full GitHub screen.\n\n'
      '- Repositories with search, sort and filters\n'
      '- Pull requests, issues and activity tabs\n\n'
      'Closes #198.',
  'url': 'https://github.com/nickrivera/sparky/pull/214',
  'user': _u('nickrivera'),
  'labels': [
    {'name': 'feature', 'color': '1f883d', 'description': 'New feature'},
    {'name': 'ui', 'color': '0075ca', 'description': ''},
  ],
  'assignees': [_u('nickrivera')],
  'requestedReviewers': [_u('ana-dev')],
  'requestedTeams': <String>[],
  'milestone': {'title': 'v1.2', 'dueOn': null, 'url': ''},
  'head': 'feat/apps-hub',
  'headSha': 'a1b2c3d4e5f6a7b8c9d0',
  'base': 'main',
  'createdAt': _ago(const Duration(days: 2)),
  'updatedAt': _ago(const Duration(hours: 5)),
  'commits': 3,
  'additions': 412,
  'deletions': 38,
  'changedFiles': 3,
  'comments': 4,
  'locked': false,
  'mergeable': mergeableState != 'dirty',
  'mergeableState': mergeableState,
  'mergeMethods': {'merge': true, 'squash': true, 'rebase': false},
  'reactions': {'+1': 2, 'rocket': 1},
  'can': can,
  'why': why,
  'viewer': {
    'login': 'nickrivera',
    'role': canWrite ? 'admin' : null,
    'isAuthor': true,
    'canWrite': canWrite,
    'needsReconnect': needsReconnect,
  },
};

Map<String, dynamic> issueDetailJson({
  Map<String, bool> can = allowAll,
  String state = 'open',
}) => {
  'repo': 'nickrivera/sparky',
  'number': 198,
  'title': 'Voice input stops after a long pause',
  'state': state,
  'isPr': false,
  'body':
      'When I pause for more than ~4 seconds the recording stops and the '
      'text so far is lost.\n\n**Steps**\n1. Tap the mic\n2. Wait 5 seconds\n',
  'url': 'https://github.com/nickrivera/sparky/issues/198',
  'user': _u('ana-dev'),
  'labels': [
    {'name': 'bug', 'color': 'd73a4a', 'description': ''},
    {'name': 'voice', 'color': '0075ca', 'description': ''},
  ],
  'assignees': [_u('nickrivera')],
  'milestone': null,
  'createdAt': _ago(const Duration(days: 6)),
  'comments': 2,
  'reactions': {'+1': 3},
  'can': can,
  'why': const <String, String>{},
  'viewer': {
    'login': 'nickrivera',
    'role': 'admin',
    'isAuthor': false,
    'canWrite': true,
    'needsReconnect': false,
  },
};

final fakeTimeline = <Map<String, dynamic>>[
  {
    'kind': 'commit',
    'id': 'c1',
    'at': _ago(const Duration(days: 2)),
    'event': 'committed',
    'sha': 'a1b2c3d4e5f6a7b8',
    'detail': 'feat(app): Apps hub with connectors',
    'body': 'Nick Rivera',
  },
  {
    'kind': 'event',
    'id': 'e1',
    'at': _ago(const Duration(days: 2)),
    'actor': _u('nickrivera'),
    'event': 'labeled',
    'label': {'name': 'feature', 'color': '1f883d'},
  },
  {
    'kind': 'comment',
    'id': 'k1',
    'at': _ago(const Duration(days: 1)),
    'actor': _u('ana-dev'),
    'event': 'commented',
    'body': 'Nice! Could the repo list remember the **last filter**?',
    'reactions': {'heart': 1},
  },
  {
    'kind': 'review',
    'id': 'r1',
    'at': _ago(const Duration(hours: 20)),
    'actor': _u('ana-dev'),
    'event': 'reviewed',
    'state': 'changes_requested',
    'body': 'One thing to fix before merging.',
    'comments': [
      {
        'id': 9,
        'path': 'lib/features/github/github_screen.dart',
        'line': 42,
        'diffHunk':
            '@@ -38,6 +38,8 @@ class _GithubScreenState\n'
            '   final _scroll = ScrollController();\n'
            '+  final _search = TextEditingController();\n'
            '+  Timer? _debounce;',
        'body': 'Dispose the timer too.',
        'user': _u('ana-dev'),
      },
    ],
  },
  {
    'kind': 'event',
    'id': 'e2',
    'at': _ago(const Duration(hours: 8)),
    'actor': _u('nickrivera'),
    'event': 'head_ref_force_pushed',
  },
  {
    'kind': 'review',
    'id': 'r2',
    'at': _ago(const Duration(hours: 6)),
    'actor': _u('ana-dev'),
    'event': 'reviewed',
    'state': 'approved',
    'body': '',
  },
];

const fakePatch = '''@@ -1,8 +1,12 @@
 import 'package:flutter/material.dart';
+import 'dart:async';

 class GithubScreen extends StatefulWidget {
-  const GithubScreen({super.key});
+  const GithubScreen({super.key, this.connections, this.controller});
+
+  final ConnectionsController? connections;
+  final GithubHubController? controller;

   @override
   State<GithubScreen> createState() => _GithubScreenState();
 }''';

final fakeFiles = <Map<String, dynamic>>[
  {
    'filename': 'lib/features/github/github_screen.dart',
    'status': 'modified',
    'additions': 5,
    'deletions': 1,
    'patch': fakePatch,
  },
  {
    'filename': 'lib/core/constants/apps.dart',
    'status': 'added',
    'additions': 3,
    'deletions': 0,
    'patch':
        '@@ -0,0 +1,3 @@\n+abstract final class AppsStrings {\n+  static const title = \'Apps\';\n+}',
  },
  {
    'filename': 'assets/images/hub.png',
    'status': 'added',
    'additions': 0,
    'deletions': 0,
    'patch': null,
  },
];

final fakeChecks = <String, dynamic>{
  'overall': 'fail',
  'summary': {'pass': 3, 'fail': 1, 'pending': 1, 'skipped': 1, 'total': 6},
  'items': [
    {
      'name': 'test (ubuntu)',
      'status': 'fail',
      'detail': '2 tests failed',
      'url': 'https://x',
      'app': 'GitHub Actions',
    },
    {
      'name': 'deploy-preview',
      'status': 'pending',
      'detail': 'Waiting for a runner',
      'url': '',
      'app': 'GitHub Actions',
    },
    {
      'name': 'analyze',
      'status': 'pass',
      'detail': 'success',
      'url': '',
      'app': 'GitHub Actions',
    },
    {
      'name': 'build-apk',
      'status': 'pass',
      'detail': 'success',
      'url': '',
      'app': 'GitHub Actions',
    },
    {
      'name': 'license/cla',
      'status': 'pass',
      'detail': 'All signed',
      'url': '',
      'app': '',
    },
    {
      'name': 'docs',
      'status': 'skipped',
      'detail': 'skipped',
      'url': '',
      'app': 'GitHub Actions',
    },
  ],
  'unavailable': null,
};

/// [FakeGithubApi] with pull request / issue detail and recorded writes.
class FakeDetailGithubApi extends FakeGithubApi {
  FakeDetailGithubApi({
    Map<String, dynamic>? pull,
    Map<String, dynamic>? issue,
    this.failWrite,
  }) : pull = pull ?? pullJson(),
       issue = issue ?? issueDetailJson();

  final Map<String, dynamic> pull;
  final Map<String, dynamic> issue;

  /// Thrown by every write when set.
  final Object? failWrite;
  final writes = <String>[];

  Future<void> _write(String what) async {
    writes.add(what);
    if (failWrite != null) throw failWrite!;
  }

  @override
  Future<GhItemDetail> pullDetail(String owner, String repo, int n) async =>
      GhItemDetail(pull);

  @override
  Future<GhItemDetail> issueDetail(String owner, String repo, int n) async =>
      GhItemDetail(issue);

  @override
  Future<List<GhTimelineItem>> timeline(
    String owner,
    String repo,
    int n, {
    required bool pr,
  }) async => [
    for (final t in pr ? fakeTimeline : fakeTimeline.skip(2).take(1))
      GhTimelineItem(t),
  ];

  @override
  Future<List<GhPrCommit>> pullCommits(
    String owner,
    String repo,
    int n,
  ) async => [
    GhPrCommit({
      'sha': 'a1b2c3d4e5f6a7b8',
      'shortSha': 'a1b2c3d',
      'message': 'feat(app): Apps hub with connectors',
      'author': _u('nickrivera'),
      'date': _ago(const Duration(days: 2)),
      'verified': true,
    }),
    GhPrCommit({
      'sha': 'b2c3d4e5f6a7b8c9',
      'shortSha': 'b2c3d4e',
      'message': 'feat(github): repository search with filters',
      'author': _u('nickrivera'),
      'date': _ago(const Duration(days: 1)),
    }),
    GhPrCommit({
      'sha': 'c3d4e5f6a7b8c9d0',
      'shortSha': 'c3d4e5f',
      'message': 'fix: dispose the debounce timer',
      'author': _u('nickrivera'),
      'date': _ago(const Duration(hours: 8)),
    }),
  ];

  @override
  Future<(List<GhFile>, bool)> pullChangedFiles(
    String owner,
    String repo,
    int n,
  ) async => ([for (final f in fakeFiles) GhFile(f)], false);

  @override
  Future<GhChecks> pullChecks(String owner, String repo, int n) async =>
      GhChecks(fakeChecks);

  @override
  Future<GhCommit> commit(String owner, String repo, String sha) async =>
      GhCommit({
        'sha': sha,
        'shortSha': sha.substring(0, 7),
        'message': 'feat(app): Apps hub with connectors',
        'fullMessage':
            'feat(app): Apps hub with connectors\n\nOne place for GitHub, '
            'knowledge and memory.',
        'author': _u('nickrivera'),
        'date': _ago(const Duration(hours: 2)),
        'url': 'https://github.com/$owner/$repo/commit/$sha',
        'stats': {'additions': 8, 'deletions': 1},
        'files': fakeFiles.take(2).toList(),
      });

  @override
  Future<List<GhLabelFull>> repoLabels(String owner, String repo) async => [
    GhLabelFull({
      'name': 'bug',
      'color': 'd73a4a',
      'description': "Something isn't working",
    }),
    GhLabelFull({
      'name': 'feature',
      'color': '1f883d',
      'description': 'New feature',
    }),
    GhLabelFull({'name': 'ui', 'color': '0075ca', 'description': ''}),
  ];

  @override
  Future<List<GhUser>> repoAssignees(String owner, String repo) async => [
    const GhUser('nickrivera', '', ''),
    const GhUser('ana-dev', '', ''),
  ];

  @override
  Future<void> comment(String owner, String repo, int n, String body) =>
      _write('comment:$body');

  @override
  Future<void> submitReview(
    String owner,
    String repo,
    int n, {
    required String event,
    String body = '',
  }) => _write('review:$event');

  @override
  Future<void> merge(
    String owner,
    String repo,
    int n, {
    required String method,
    String? title,
    String? sha,
  }) => _write('merge:$method');

  @override
  Future<void> updateItem(
    String owner,
    String repo,
    int n, {
    String? state,
    String? stateReason,
    String? title,
    String? body,
    List<String>? labels,
    List<String>? assignees,
  }) => _write(
    'update:${[if (state != null) 'state=$state', if (stateReason != null) 'reason=$stateReason', if (labels != null) 'labels=${labels.join(',')}', if (assignees != null) 'assignees=${assignees.join(',')}'].join(';')}',
  );

  @override
  Future<void> react(String owner, String repo, int n, String content) =>
      _write('react:$content');

  @override
  Future<void> markReady(String owner, String repo, int n) => _write('ready');
}
