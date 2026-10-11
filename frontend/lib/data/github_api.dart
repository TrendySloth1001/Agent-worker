import 'dart:convert';

import '../core/constants/app_config.dart';
import '../core/constants/widget_github.dart';
import 'chat_api.dart';
import 'api_client.dart';

// ---- models ----------------------------------------------------------------

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : const {};
List<Map<String, dynamic>> _list(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is Map<String, dynamic>) e,
];
String _s(Object? v) => v is String ? v : '';
int _i(Object? v) => v is num ? v.round() : 0;
int? _iOrNull(Object? v) => v is num ? v.round() : null;
DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

class GhUser {
  const GhUser(this.login, this.avatar, this.url);
  final String login, avatar, url;

  static GhUser? fromJson(Object? j) {
    final m = _map(j);
    if (_s(m['login']).isEmpty) return null;
    return GhUser(_s(m['login']), _s(m['avatar']), _s(m['url']));
  }
}

class GhLabel {
  const GhLabel(this.name, this.color);
  final String name, color;
}

class GhRepo {
  GhRepo(Map<String, dynamic> j)
    : fullName = _s(j['fullName']),
      owner = _s(j['owner']).isNotEmpty
          ? _s(j['owner'])
          : _s(j['fullName']).split('/').first,
      name = _s(j['name']).isNotEmpty
          ? _s(j['name'])
          : _s(j['fullName']).split('/').last,
      fork = j['fork'] == true,
      score = (j['score'] as num?)?.toDouble(),
      matched = [for (final t in (j['matched'] as List? ?? const [])) '$t'],
      avatar = _s(j['avatar']),
      description = _s(j['description']),
      url = _s(j['url']),
      homepage = j['homepage'] as String?,
      stars = _i(j['stars']),
      forks = _i(j['forks']),
      watchers = _iOrNull(j['watchers']),
      openIssues = _i(j['openIssues']),
      language = j['language'] as String?,
      topics = [for (final t in (j['topics'] as List? ?? const [])) '$t'],
      license = j['license'] as String?,
      defaultBranch = _s(j['defaultBranch']),
      archived = j['archived'] == true,
      isPrivate = j['private'] == true,
      pushedAt = _date(j['pushedAt']),
      languages = [
        for (final l in _list(j['languages']))
          (_s(l['name']), (l['pct'] as num?)?.toDouble() ?? 0),
      ],
      latestRelease = j['latestRelease'] is Map<String, dynamic>
          ? GhRelease(j['latestRelease'] as Map<String, dynamic>)
          : null,
      readme = _s(j['readme']);

  final String fullName, owner, name, avatar, description, url;
  final String defaultBranch, readme;
  final String? homepage, language, license;

  /// A fork of another repository.
  final bool fork;

  /// Search rank (higher is better) and the query tokens that hit.
  final double? score;
  final List<String> matched;
  final int stars, forks, openIssues;
  final int? watchers;
  final List<String> topics;
  final bool archived, isPrivate;
  final DateTime? pushedAt;
  final List<(String, double)> languages;
  final GhRelease? latestRelease;
}

class GhRelease {
  GhRelease(Map<String, dynamic> j)
    : tag = _s(j['tag']),
      name = _s(j['name']),
      url = _s(j['url']),
      publishedAt = _date(j['publishedAt']);
  final String tag, name, url;
  final DateTime? publishedAt;
}

class GhCommit {
  GhCommit(Map<String, dynamic> j)
    : sha = _s(j['sha']),
      shortSha = _s(j['shortSha']),
      message = _s(j['message']),
      body = _s(j['fullMessage']).isNotEmpty
          ? _s(j['fullMessage'])
          : _s(j['body']),
      author = GhUser.fromJson(j['author']),
      authorName = _s(j['authorName']),
      date = _date(j['date']),
      url = _s(j['url']),
      repo = _s(j['repo']),
      additions = _iOrNull(j['additions'] ?? _map(j['stats'])['additions']),
      deletions = _iOrNull(j['deletions'] ?? _map(j['stats'])['deletions']),
      files = [for (final f in _list(j['files'])) GhFile(f)],
      filesTruncated = j['filesTruncated'] == true;

  final String sha, shortSha, message, body, authorName, url, repo;
  final GhUser? author;
  final DateTime? date;
  final int? additions, deletions;
  final List<GhFile> files;
  final bool filesTruncated;

  String get who => author?.login ?? authorName;
}

class GhFile {
  GhFile(Map<String, dynamic> j)
    : filename = _s(j['filename']),
      previousFilename = j['previousFilename'] as String?,
      status = _s(j['status']),
      additions = _i(j['additions']),
      deletions = _i(j['deletions']),
      patch = j['patch'] as String?,
      patchTruncated = j['patchTruncated'] == true;

  final String filename, status;
  final String? previousFilename, patch;
  final int additions, deletions;
  final bool patchTruncated;
}

class GhCompare {
  GhCompare(Map<String, dynamic> j)
    : status = _s(j['status']),
      aheadBy = _i(j['aheadBy']),
      behindBy = _i(j['behindBy']),
      totalCommits = _i(j['totalCommits']),
      url = _s(j['url']),
      additions = _i(_map(j['stats'])['additions']),
      deletions = _i(_map(j['stats'])['deletions']),
      changedFiles = _i(_map(j['stats'])['changedFiles']),
      commits = [for (final c in _list(j['commits'])) GhCommit(c)],
      files = [for (final f in _list(j['files'])) GhFile(f)],
      filesTruncated = j['filesTruncated'] == true;

  final String status, url;
  final int aheadBy, behindBy, totalCommits, additions, deletions;
  final int changedFiles;
  final List<GhCommit> commits;
  final List<GhFile> files;
  final bool filesTruncated;
}

enum GhEntryType { dir, file, symlink, submodule }

class GhEntry {
  GhEntry(Map<String, dynamic> j)
    : name = _s(j['name']),
      path = _s(j['path']),
      size = _i(j['size']),
      type = GhEntryType.values.firstWhere(
        (t) => t.name == j['type'],
        orElse: () => GhEntryType.file,
      );
  final String name, path;
  final int size;
  final GhEntryType type;
}

class GhTree {
  GhTree(Map<String, dynamic> j)
    : ref = _s(j['ref']),
      path = _s(j['path']),
      truncated = j['truncated'] == true,
      entries = [for (final e in _list(j['entries'])) GhEntry(e)];
  final String ref, path;
  final bool truncated;
  final List<GhEntry> entries;
}

class GhContent {
  GhContent(Map<String, dynamic> j)
    : path = _s(j['path']),
      name = _s(j['name']),
      size = _i(j['size']),
      url = _s(j['url']),
      language = _s(j['language']),
      binary = j['binary'] == true,
      tooLarge = j['tooLarge'] == true,
      truncated = j['truncated'] == true,
      text = _s(j['text']);
  final String path, name, url, language, text;
  final int size;
  final bool binary, tooLarge, truncated;
}

/// An issue or pull request.
class GhIssue {
  GhIssue(Map<String, dynamic> j)
    : number = _i(j['number']),
      title = _s(j['title']),
      state = _s(j['state']),
      stateReason = j['stateReason'] as String?,
      isPr = j['isPr'] == true,
      user = GhUser.fromJson(j['user']),
      labels = [
        for (final l in _list(j['labels']))
          GhLabel(_s(l['name']), _s(l['color'])),
      ],
      comments = _iOrNull(j['comments']),
      updatedAt = _date(j['updatedAt']),
      url = _s(j['url']),
      body = _s(j['body']),
      repo = _s(j['repo']),
      head = _s(j['head']),
      base = _s(j['base']);

  final int number;
  final String title, state, url, body, repo, head, base;
  final String? stateReason;
  final bool isPr;
  final GhUser? user;
  final List<GhLabel> labels;
  final int? comments;
  final DateTime? updatedAt;
}

class GhCodeHit {
  GhCodeHit(Map<String, dynamic> j)
    : name = _s(j['name']),
      path = _s(j['path']),
      repo = _s(j['repo']),
      avatar = _s(j['avatar']),
      url = _s(j['url']),
      fragments = [for (final f in (j['fragments'] as List? ?? const [])) '$f'];
  final String name, path, repo, avatar, url;
  final List<String> fragments;
}

/// One finding of an AI pull request review.
class GhReviewComment {
  GhReviewComment(Map<String, dynamic> j)
    : file = _s(j['file']),
      line = _iOrNull(j['line']),
      severity = _s(j['severity']),
      title = _s(j['title']),
      body = _s(j['body']),
      suggestion = j['suggestion'] as String?;

  final String file, severity, title, body;
  final int? line;
  final String? suggestion;
}

/// AI review of a pull request (`POST /pulls/:n/review`).
class GhReview {
  GhReview(Map<String, dynamic> j)
    : owner = _s(j['owner']),
      repo = _s(j['repo']),
      number = _i(j['number']),
      title = _s(j['title']),
      author = GhUser.fromJson(j['author']),
      url = _s(j['url']),
      state = _s(j['state']),
      head = _s(j['head']),
      base = _s(j['base']),
      additions = _i(j['additions']),
      deletions = _i(j['deletions']),
      changedFiles = _i(j['changedFiles']),
      summary = _s(j['summary']),
      verdict = _s(j['verdict']),
      risk = _s(j['risk']),
      comments = [for (final c in _list(j['comments'])) GhReviewComment(c)],
      tests = [for (final t in (j['tests'] as List? ?? const [])) '$t'],
      skippedFiles = [
        for (final f in (j['skippedFiles'] as List? ?? const [])) '$f',
      ],
      files = [for (final f in _list(j['files'])) GhFile(f)],
      model = _s(j['model']),
      cached = j['cached'] == true;

  final String owner, repo, title, url, state, head, base;
  final String summary, verdict, risk, model;
  final int number, additions, deletions, changedFiles;
  final GhUser? author;
  final List<GhReviewComment> comments;
  final List<String> tests, skippedFiles;
  final List<GhFile> files;
  final bool cached;

  GhFile? fileFor(String name) =>
      files.where((f) => f.filename == name).firstOrNull;
}

/// One commit of the git graph (`GET /repos/:o/:r/graph`).
class GhGraphCommit {
  GhGraphCommit(Map<String, dynamic> j)
    : sha = _s(j['sha']),
      parents = [for (final p in (j['parents'] as List? ?? const [])) '$p'],
      subject = _s(j['subject']),
      author = _s(j['author']),
      authorAvatar = _s(j['authorAvatar']),
      date = _date(j['date']),
      refs = [for (final r in (j['refs'] as List? ?? const [])) '$r'];

  final String sha, subject, author, authorAvatar;
  final List<String> parents, refs;
  final DateTime? date;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

class GhGraphBranch {
  GhGraphBranch(Map<String, dynamic> j)
    : name = _s(j['name']),
      sha = _s(j['sha']),
      isDefault = j['isDefault'] == true;
  final String name, sha;
  final bool isDefault;
}

/// One page of the commit DAG of the default branch plus selected branches.
class GhGraph {
  GhGraph(Map<String, dynamic> j)
    : repo = _s(j['repo']),
      defaultBranch = _s(j['defaultBranch']),
      branches = [for (final b in _list(j['branches'])) GhGraphBranch(b)],
      commits = [for (final c in _list(j['commits'])) GhGraphCommit(c)],
      truncated = j['truncated'] == true,
      nextCursor = j['nextCursor'] as String?,
      totalCount = _iOrNull(j['totalCount']);

  final String repo, defaultBranch;
  final List<GhGraphBranch> branches;
  final List<GhGraphCommit> commits;
  final bool truncated;

  /// Older history: pass back as `after`; null when every branch is done.
  final String? nextCursor;

  /// Commits on the shown branches, when GitHub reports it.
  final int? totalCount;

  String? get defaultHead =>
      branches.where((b) => b.isDefault).firstOrNull?.sha;
}

/// One page of commit history (`GET /repos/:o/:r/commits`).
class GhCommitPage {
  GhCommitPage(Map<String, dynamic> j)
    : items = [for (final c in _list(j['items'])) GhCommit(c)],
      totalCount = _iOrNull(j['totalCount']),
      nextCursor = j['nextCursor'] as String?;
  final List<GhCommit> items;
  final int? totalCount;
  final String? nextCursor;
}

/// A branch with its head commit date.
class GhBranch {
  GhBranch(Map<String, dynamic> j)
    : name = _s(j['name']),
      sha = _s(j['sha']),
      date = _date(j['date']),
      isDefault = j['default'] == true;
  final String name, sha;
  final DateTime? date;
  final bool isDefault;
}

/// One page of every branch (default first, then newest; or ranked by `q`).
class GhBranchPage {
  GhBranchPage(Map<String, dynamic> j)
    : defaultBranch = _s(j['defaultBranch']),
      totalCount = _i(j['totalCount']),
      matchCount = _i(j['matchCount']),
      items = [for (final b in _list(j['items'])) GhBranch(b)],
      nextCursor = j['nextCursor'] as String?;
  final String defaultBranch;
  final int totalCount, matchCount;
  final List<GhBranch> items;
  final String? nextCursor;
}

/// Ranked repository search results.
class GhRepoSearch {
  GhRepoSearch(Map<String, dynamic> j)
    : total = _i(j['total']),
      items = [for (final r in _list(j['items'])) GhRepo(r)],
      tokens = [for (final t in (j['tokens'] as List? ?? const [])) '$t'],
      corrected = j['corrected'] as String?,
      confident = j['confident'] == true;
  final int total;
  final List<GhRepo> items;
  final List<String> tokens;

  /// The typo-repaired query, when one was used.
  final String? corrected;
  final bool confident;
}

/// The account the backend's token belongs to.
class GhMe {
  GhMe(Map<String, dynamic> j)
    : login = _s(j['login']),
      avatar = _s(j['avatar']),
      url = _s(j['url']),
      publicRepos = _i(j['publicRepos']),
      privateRepos = _iOrNull(j['privateRepos']),
      scopes = j['scopes'] is List
          ? [for (final s in j['scopes'] as List) '$s']
          : null,
      canReadPrivate = j['canReadPrivate'] == true;

  final String login, avatar, url;
  final int publicRepos;
  final int? privateRepos;
  final List<String>? scopes;
  final bool canReadPrivate;
}

class GhSearch<T> {
  const GhSearch(this.total, this.items);
  final int total;
  final List<T> items;
}

// ---- client ----------------------------------------------------------------

/// Live GitHub data through the backend's `/github` routes.
class GithubApi {
  GithubApi._();
  static final instance = GithubApi._();

  final _client = AuthClient();

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/github$path').replace(
      queryParameters: query == null || query.isEmpty
          ? null
          : {
              for (final e in query.entries)
                if (e.value.isNotEmpty) e.key: e.value,
            },
    );
    final res = await _client
        .get(uri, headers: apiHeaders())
        .timeout(GithubDurations.timeout);
    if (res.statusCode >= 400) {
      throw ApiException(
        errorMessage(res.body, res.statusCode),
        status: res.statusCode,
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Duration timeout) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/github$path');
    final res = await _client.post(uri, headers: apiHeaders()).timeout(timeout);
    if (res.statusCode >= 400) {
      throw ApiException(
        errorMessage(res.body, res.statusCode),
        status: res.statusCode,
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Reviews pull request [number] with a strong model (slow, cached per
  /// head commit on the server).
  Future<GhReview> review(
    String owner,
    String repo,
    int number, {
    bool fresh = false,
  }) async => GhReview(
    await _post(
      '${_repo(owner, repo)}/pulls/$number/review${fresh ? '?fresh=1' : ''}',
      GithubReviewDurations.reviewTimeout,
    ),
  );

  Future<GhMe> me() async => GhMe(await _get('/me'));

  /// Every repository the user can access ([visibility]: all, private or
  /// public); [refresh] skips the server's 5 minute cache.
  Future<List<GhRepo>> myRepos({
    String visibility = 'all',
    bool refresh = false,
  }) async {
    final j = await _get('/my/repos', {
      'visibility': visibility,
      'sort': 'pushed',
      if (refresh) 'refresh': '1',
    });
    return [for (final r in _list(j['items'])) GhRepo(r)];
  }

  /// The user's repositories ranked for loose text (typos, partial names).
  Future<GhRepoSearch> searchMyRepos(String q) async => GhRepoSearch(
    await _get('/my/repos/search', {
      'q': q,
      'limit': '${GithubSearchLimits.myRepoMatches}',
    }),
  );

  String _repo(String owner, String repo) =>
      '/repos/${Uri.encodeComponent(owner)}/${Uri.encodeComponent(repo)}';

  Future<GhRepo> repo(String owner, String repo) async =>
      GhRepo(await _get(_repo(owner, repo)));

  Future<List<GhCommit>> commits(
    String owner,
    String repo, {
    String? sha,
    String? path,
    int perPage = GithubLimits.pageCommits,
  }) async {
    final j = await _get('${_repo(owner, repo)}/commits', {
      'sha': sha ?? '',
      'path': path ?? '',
      'per_page': '$perPage',
    });
    return [for (final c in _list(j['items'])) GhCommit(c)];
  }

  /// Commit graph; [branches] empty = the default and recently pushed ones.
  /// [after] = a previous page's `nextCursor` (older history).
  Future<GhGraph> graph(
    String owner,
    String repo, {
    List<String> branches = const [],
    int limit = GithubGraphLimits.defaultLimit,
    String? after,
  }) async => GhGraph(
    await _get('${_repo(owner, repo)}/graph', {
      'branches': after == null ? branches.join(',') : '',
      'limit': '$limit',
      'after': after ?? '',
    }),
  );

  /// One page of history; [q] filters by message, author or sha.
  Future<GhCommitPage> commitPage(
    String owner,
    String repo, {
    String? sha,
    String? path,
    String? q,
    String? after,
    int perPage = GithubLimits.pageCommitsInfinite,
  }) async => GhCommitPage(
    await _get('${_repo(owner, repo)}/commits', {
      'sha': sha ?? '',
      'path': path ?? '',
      'q': q ?? '',
      'after': after ?? '',
      'per_page': '$perPage',
    }),
  );

  /// Every branch (paged), default first then newest, or ranked for [q].
  Future<GhBranchPage> branches(
    String owner,
    String repo, {
    String q = '',
    String? after,
    int limit = GithubBranchLimits.page,
  }) async => GhBranchPage(
    await _get('${_repo(owner, repo)}/branches', {
      'q': q,
      'after': after ?? '',
      'limit': '$limit',
    }),
  );

  Future<GhCommit> commit(String owner, String repo, String sha) async =>
      GhCommit(
        await _get('${_repo(owner, repo)}/commits/${Uri.encodeComponent(sha)}'),
      );

  Future<GhCompare> compare(
    String owner,
    String repo,
    String base,
    String head,
  ) async => GhCompare(
    await _get(
      '${_repo(owner, repo)}/compare/'
      '${Uri.encodeComponent('$base...$head')}',
    ),
  );

  Future<GhTree> tree(
    String owner,
    String repo,
    String ref, {
    String path = '',
  }) async => GhTree(
    await _get('${_repo(owner, repo)}/tree/${Uri.encodeComponent(ref)}', {
      'path': path,
    }),
  );

  Future<GhContent> contents(
    String owner,
    String repo,
    String ref,
    String path,
  ) async => GhContent(
    await _get('${_repo(owner, repo)}/contents/${Uri.encodeComponent(ref)}', {
      'path': path,
    }),
  );

  Future<List<GhIssue>> pulls(String owner, String repo, String state) async {
    final j = await _get('${_repo(owner, repo)}/pulls', {
      'state': state,
      'per_page': '${GithubLimits.pageItems}',
    });
    return [for (final i in _list(j['items'])) GhIssue(i)];
  }

  Future<List<GhIssue>> issues(String owner, String repo, String state) async {
    final j = await _get('${_repo(owner, repo)}/issues', {
      'state': state,
      'per_page': '${GithubLimits.pageItems}',
    });
    return [for (final i in _list(j['items'])) GhIssue(i)];
  }

  /// Files changed by pull request [number].
  Future<List<GhFile>> pullFiles(String owner, String repo, int number) async {
    final j = await _get('${_repo(owner, repo)}/pulls/$number');
    return [for (final f in _list(j['files'])) GhFile(f)];
  }

  /// Ranked repository search ([sort]: best-match, stars or updated).
  Future<GhRepoSearch> searchRepos(String q, {String? sort}) async =>
      GhRepoSearch(
        await _get('/search/repos', {
          'q': q,
          'sort': sort ?? '',
          'per_page': '${GithubSearchLimits.repos}',
        }),
      );

  Future<GhSearch<GhCodeHit>> searchCode(String q) async {
    final j = await _get('/search/code', {
      'q': q,
      'per_page': '${GithubLimits.pageRepos}',
    });
    return GhSearch(_i(j['total']), [
      for (final r in _list(j['items'])) GhCodeHit(r),
    ]);
  }

  Future<GhSearch<GhIssue>> searchIssues(String q) async {
    final j = await _get('/search/issues', {
      'q': q,
      'per_page': '${GithubLimits.pageRepos}',
    });
    return GhSearch(_i(j['total']), [
      for (final r in _list(j['items'])) GhIssue(r),
    ]);
  }

  Future<GhSearch<GhCommit>> searchCommits(String q) async {
    final j = await _get('/search/commits', {
      'q': q,
      'per_page': '${GithubLimits.pageRepos}',
    });
    return GhSearch(_i(j['total']), [
      for (final r in _list(j['items'])) GhCommit(r),
    ]);
  }
}
