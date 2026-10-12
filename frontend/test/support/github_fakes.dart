import 'dart:io';

import 'package:app/data/connections_api.dart';
import 'package:app/data/github_api.dart';
import 'package:app/features/chat/widgets/markdown/inline_icon.dart';
import 'package:app/features/connections/connections_controller.dart';

/// Loads the brand and octicon glyphs from `test/support/icons` so
/// screenshots draw them without the network.
void seedIcons() {
  final dir = Directory('test/support/icons');
  for (final f in dir.listSync().whereType<File>()) {
    final base = f.uri.pathSegments.last.replaceAll('.svg', '');
    final parts = base.split('__');
    IconCache.seed(parts[0], parts[1], f.readAsStringSync());
  }
}

DateTime _ago(Duration d) => DateTime.now().subtract(d);

Map<String, dynamic> repoJson(
  String full, {
  String description = '',
  String? language,
  int stars = 0,
  bool fork = false,
  bool isPrivate = false,
  bool archived = false,
  Duration pushed = const Duration(days: 1),
  List<String> topics = const [],
  String readme = '',
}) {
  final owner = full.split('/').first;
  return {
    'fullName': full,
    'owner': owner,
    'name': full.split('/').last,
    'avatar': '',
    'description': description,
    'url': 'https://github.com/$full',
    'stars': stars,
    'forks': stars ~/ 6,
    'watchers': stars ~/ 20,
    'openIssues': 4,
    'language': language,
    'topics': topics,
    'license': 'MIT',
    'defaultBranch': 'main',
    'archived': archived,
    'fork': fork,
    'private': isPrivate,
    'pushedAt': _ago(pushed).toIso8601String(),
    'languages': language == null
        ? <Map<String, dynamic>>[]
        : [
            {'name': language, 'pct': 71.0},
            {'name': 'Shell', 'pct': 18.0},
            {'name': 'Dockerfile', 'pct': 11.0},
          ],
    'readme': readme,
  };
}

const sampleReadme = '''
# sparky-worker

A small queue worker that **pulls jobs** and runs them in the background.

## Getting started

```bash
pnpm install
pnpm dev
```

- Retries with exponential backoff
- Per-user rate limits
- Structured logs
''';

final fakeRepos = <Map<String, dynamic>>[
  repoJson(
    'nickrivera/sparky',
    description: 'A personal AI assistant app with a Nothing-inspired look.',
    language: 'Dart',
    stars: 128,
    pushed: const Duration(hours: 3),
    topics: ['flutter', 'ai', 'assistant'],
    readme: sampleReadme,
  ),
  repoJson(
    'nickrivera/sparky-worker',
    description: 'Background job runner for Sparky.',
    language: 'TypeScript',
    stars: 12,
    isPrivate: true,
    pushed: const Duration(days: 2),
    readme: sampleReadme,
  ),
  repoJson(
    'cloudnsofts/platform',
    description: 'Project tracker, docs and channels for small teams.',
    language: 'TypeScript',
    stars: 842,
    pushed: const Duration(days: 5),
  ),
  repoJson(
    'cloudnsofts/design-tokens',
    description: 'Shared colors, type and spacing.',
    language: 'CSS',
    stars: 31,
    pushed: const Duration(days: 12),
  ),
  repoJson(
    'nickrivera/dotfiles',
    description: 'Shell, git and editor setup.',
    language: 'Shell',
    stars: 3,
    pushed: const Duration(days: 40),
  ),
  repoJson(
    'nickrivera/flutter',
    description: 'Fork of flutter/flutter for local patches.',
    language: 'Dart',
    stars: 0,
    fork: true,
    pushed: const Duration(days: 90),
  ),
  repoJson(
    'nickrivera/old-blog',
    description: 'Retired static blog.',
    language: 'HTML',
    stars: 1,
    archived: true,
    pushed: const Duration(days: 700),
  ),
  for (var i = 0; i < 40; i++)
    repoJson(
      'nickrivera/experiment-$i',
      description: 'Scratch repository number $i.',
      language: i.isEven ? 'Python' : 'Go',
      stars: i,
      pushed: Duration(days: 100 + i),
    ),
];

Map<String, dynamic> issueJson(
  int n,
  String title, {
  bool pr = false,
  String state = 'open',
  String repo = 'nickrivera/sparky',
  int comments = 0,
  List<Map<String, String>> labels = const [],
  Duration updated = const Duration(hours: 5),
}) => {
  'number': n,
  'title': title,
  'state': state,
  'isPr': pr,
  'user': {'login': 'nickrivera', 'avatar': '', 'url': ''},
  'labels': labels,
  'comments': comments,
  'updatedAt': _ago(updated).toIso8601String(),
  'url': 'https://github.com/$repo/${pr ? 'pull' : 'issues'}/$n',
  'repo': repo,
};

final fakePulls = [
  issueJson(
    214,
    'Add the Apps hub and GitHub screen',
    pr: true,
    comments: 3,
    labels: [
      {'name': 'feature', 'color': '1f883d'},
    ],
  ),
  issueJson(
    212,
    'Fix drawer footer overflow on short screens',
    pr: true,
    state: 'draft',
    updated: const Duration(days: 1),
  ),
  issueJson(
    77,
    'Bump queue retries and add jitter',
    pr: true,
    state: 'merged',
    repo: 'nickrivera/sparky-worker',
    updated: const Duration(days: 3),
  ),
];

final fakeIssues = [
  issueJson(
    198,
    'Voice input stops after a long pause',
    comments: 5,
    labels: [
      {'name': 'bug', 'color': 'd73a4a'},
      {'name': 'voice', 'color': '0075ca'},
    ],
  ),
  issueJson(
    190,
    'Support attaching a whole repo to a chat',
    repo: 'cloudnsofts/platform',
    updated: const Duration(days: 2),
  ),
];

Map<String, dynamic> commitJson(
  String sha,
  String message, {
  String repo = 'nickrivera/sparky',
  Duration ago = const Duration(hours: 2),
}) => {
  'sha': sha,
  'shortSha': sha.substring(0, 7),
  'message': message,
  'author': {'login': 'nickrivera', 'avatar': '', 'url': ''},
  'authorName': 'Nick Rivera',
  'date': _ago(ago).toIso8601String(),
  'url': 'https://github.com/$repo/commit/$sha',
  'repo': repo,
  'parents': <String>[],
};

final fakeCommits = [
  commitJson('a1b2c3d4e5f6a7b8', 'feat(app): Apps hub with connectors'),
  commitJson(
    'b2c3d4e5f6a7b8c9',
    'fix(chat): keep scroll position while streaming',
    ago: const Duration(hours: 9),
  ),
  commitJson(
    'c3d4e5f6a7b8c9d0',
    'chore(worker): retry jobs with jitter',
    repo: 'nickrivera/sparky-worker',
    ago: const Duration(days: 1),
  ),
];

/// A [GithubApi] that answers from memory.
class FakeGithubApi extends GithubApi {
  FakeGithubApi({
    this.repos,
    this.failMe = false,
    this.delay = Duration.zero,
  }) : super.fake();

  final List<Map<String, dynamic>>? repos;
  final bool failMe;
  final Duration delay;

  @override
  Future<GhMe> me() async {
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    if (failMe) throw Exception('nope');
    return GhMe({
      'login': 'nickrivera',
      'name': 'Nick Rivera',
      'avatar': '',
      'url': 'https://github.com/nickrivera',
      'publicRepos': 47,
      'privateRepos': 9,
      'canReadPrivate': true,
    });
  }

  @override
  Future<List<GhRepo>> myRepos({
    String visibility = 'all',
    bool refresh = false,
  }) async => [for (final r in repos ?? fakeRepos) GhRepo(r)];

  @override
  Future<GhSearch<GhIssue>> involvedPulls(String login) async =>
      GhSearch(fakePulls.length, [for (final p in fakePulls) GhIssue(p)]);

  @override
  Future<GhSearch<GhIssue>> involvedIssues(String login) async =>
      GhSearch(fakeIssues.length, [for (final p in fakeIssues) GhIssue(p)]);

  @override
  Future<GhSearch<GhCommit>> activity(String login) async =>
      GhSearch(fakeCommits.length, [for (final c in fakeCommits) GhCommit(c)]);

  @override
  Future<GhRepo> repo(String owner, String repo) async {
    final j = (repos ?? fakeRepos).firstWhere(
      (r) => r['fullName'] == '$owner/$repo',
      orElse: () => fakeRepos.first,
    );
    return GhRepo(j);
  }

  @override
  Future<GhCommitPage> commitPage(
    String owner,
    String repo, {
    String? sha,
    String? path,
    String? q,
    String? after,
    int perPage = 0,
  }) async => GhCommitPage({
    'items': fakeCommits,
    'totalCount': fakeCommits.length,
    'nextCursor': null,
  });

  @override
  Future<GhBranchPage> branches(
    String owner,
    String repo, {
    String q = '',
    String? after,
    int limit = 0,
  }) async => GhBranchPage({
    'defaultBranch': 'main',
    'totalCount': 2,
    'matchCount': 2,
    'items': [
      {'name': 'main', 'sha': 'a1b2c3d', 'default': true},
      {'name': 'feature/apps', 'sha': 'b2c3d4e'},
    ],
  });

  @override
  Future<GhGraph> graph(
    String owner,
    String repo, {
    List<String> branches = const [],
    int limit = 0,
    String? after,
  }) async => GhGraph({
    'repo': '$owner/$repo',
    'defaultBranch': 'main',
    'branches': [
      {'name': 'main', 'sha': 'a1b2c3d4e5f6a7b8', 'isDefault': true},
    ],
    'commits': [
      {
        'sha': 'a1b2c3d4e5f6a7b8',
        'parents': ['b2c3d4e5f6a7b8c9'],
        'subject': 'feat(app): Apps hub with connectors',
        'author': 'Nick Rivera',
        'date': _ago(const Duration(hours: 2)).toIso8601String(),
        'refs': ['main'],
      },
      {
        'sha': 'b2c3d4e5f6a7b8c9',
        'parents': ['c3d4e5f6a7b8c9d0'],
        'subject': 'fix(chat): keep scroll position',
        'author': 'Nick Rivera',
        'date': _ago(const Duration(hours: 9)).toIso8601String(),
        'refs': <String>[],
      },
      {
        'sha': 'c3d4e5f6a7b8c9d0',
        'parents': <String>[],
        'subject': 'chore: initial commit',
        'author': 'Nick Rivera',
        'date': _ago(const Duration(days: 4)).toIso8601String(),
        'refs': <String>[],
      },
    ],
  });

  @override
  Future<GhTree> tree(
    String owner,
    String repo,
    String ref, {
    String path = '',
  }) async => GhTree({
    'ref': ref,
    'path': path,
    'entries': [
      {'name': 'lib', 'path': 'lib', 'type': 'dir'},
      {'name': 'test', 'path': 'test', 'type': 'dir'},
      {'name': 'README.md', 'path': 'README.md', 'type': 'file', 'size': 2048},
      {'name': 'pubspec.yaml', 'path': 'pubspec.yaml', 'type': 'file', 'size': 900},
    ],
  });

  @override
  Future<List<GhIssue>> pulls(String owner, String repo, String state) async =>
      [for (final p in fakePulls) GhIssue(p)];

  @override
  Future<List<GhIssue>> issues(String owner, String repo, String state) async =>
      [for (final p in fakeIssues) GhIssue(p)];

  @override
  Future<GhRepoSearch> searchRepos(String q, {String? sort}) async =>
      GhRepoSearch({
        'total': 2,
        'items': [fakeRepos[0], fakeRepos[2]],
      });

  @override
  Future<List<GhActivity>> myEvents() async => [
    for (final e in fakeEvents) GhActivity(e),
  ];
}

/// The account's activity feed: today, yesterday and older.
final fakeEvents = <Map<String, dynamic>>[
  {
    'id': '1',
    'type': 'push',
    'action': 'pushed',
    'repo': 'nickrivera/sparky',
    'at': _ago(const Duration(hours: 2)).toIso8601String(),
    'title': 'feat(app): Apps hub with connectors',
    'sha': 'a1b2c3d4e5f6a7b8',
    'ref': 'main',
    'url': 'https://github.com/nickrivera/sparky/commit/a1b2c3d4e5f6a7b8',
    'commits': [
      {'sha': 'a1b2c3d4e5f6a7b8', 'message': 'feat(app): Apps hub with connectors'},
      {'sha': 'b2c3d4e5f6a7b8c9', 'message': 'fix(chat): keep scroll position'},
    ],
  },
  {
    'id': '2',
    'type': 'pr',
    'action': 'opened',
    'repo': 'nickrivera/sparky',
    'at': _ago(const Duration(hours: 3)).toIso8601String(),
    'title': 'Add the Apps hub and GitHub screen',
    'number': 214,
    'isPr': true,
    'url': 'https://github.com/nickrivera/sparky/pull/214',
  },
  {
    'id': '3',
    'type': 'review',
    'action': 'approved',
    'repo': 'cloudnsofts/platform',
    'at': _ago(const Duration(days: 1, hours: 1)).toIso8601String(),
    'title': 'Channels: unread markers',
    'number': 88,
    'isPr': true,
    'url': 'https://github.com/cloudnsofts/platform/pull/88',
  },
  {
    'id': '4',
    'type': 'issue',
    'action': 'opened',
    'repo': 'nickrivera/sparky',
    'at': _ago(const Duration(days: 1, hours: 4)).toIso8601String(),
    'title': 'Voice input stops after a long pause',
    'number': 198,
    'url': 'https://github.com/nickrivera/sparky/issues/198',
  },
  {
    'id': '5',
    'type': 'release',
    'action': 'published',
    'repo': 'nickrivera/sparky',
    'at': _ago(const Duration(days: 4)).toIso8601String(),
    'title': 'v1.1.0',
    'url': 'https://github.com/nickrivera/sparky/releases/tag/v1.1.0',
    'body': '## Highlights\n\n- Apps hub\n- GitHub screen',
    'release': {'tag': 'v1.1.0', 'name': 'v1.1.0'},
  },
];

/// Puts the app's connection state in a known place without any network.
void fakeConnected({
  bool connected = true,
  List<String> missingScopes = const [],
}) {
  ConnectionsController.instance.state = ConnectionsState({
    'items': [
      if (connected)
        {
          'provider': 'github',
          'accountLogin': 'nickrivera',
          'avatarUrl': '',
          'scopes': ['repo'],
          'missingScopes': missingScopes,
        },
    ],
    'providers': {
      'github': {'configured': true, 'web': true},
    },
    'isOwner': false,
  });
}
