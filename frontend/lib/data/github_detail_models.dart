import 'chat_api.dart';
import 'github_api.dart';

// Models of the in-app pull request / issue screens and the activity feed
// (`/github/repos/:o/:r/pulls/:n/*`, `/issues/:n*`, `/my/events`).

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
List<GhUser> _users(Object? v) => [
  for (final u in _list(v)) ?GhUser.fromJson(u),
];

/// A typed error from the GitHub routes. [code] is the backend's error code
/// (`github_scope_missing`, `github_no_permission`, `rate_limited`, …).
class GhApiException extends ApiException {
  const GhApiException(
    super.message, {
    super.status,
    super.code,
    this.retryable = false,
  });

  final bool retryable;

  /// The token lacks access: reconnecting GitHub may fix it.
  bool get needsReconnect =>
      code == 'github_scope_missing' || code == 'github_not_connected';
  bool get rateLimited => code == 'rate_limited' || status == 429;
  bool get forbidden =>
      code == 'github_no_permission' || code == 'github_scope_missing';
}

/// What the viewer may do on one pull request or issue, with the reason
/// for each action that is off.
class GhCan {
  GhCan(Map<String, dynamic> can, Map<String, dynamic> why)
    : _can = {for (final e in can.entries) e.key: e.value == true},
      _why = {for (final e in why.entries) e.key: '${e.value}'};

  const GhCan.none() : _can = const {}, _why = const {};

  final Map<String, bool> _can;
  final Map<String, String> _why;

  bool get comment => _can['comment'] ?? false;
  bool get react => _can['react'] ?? false;
  bool get review => _can['review'] ?? false;
  bool get approve => _can['approve'] ?? false;
  bool get merge => _can['merge'] ?? false;
  bool get close => _can['close'] ?? false;
  bool get reopen => _can['reopen'] ?? false;
  bool get label => _can['label'] ?? false;
  bool get assign => _can['assign'] ?? false;
  bool get edit => _can['edit'] ?? false;
  bool get markReady => _can['markReady'] ?? false;

  /// Why [key] is off (null when allowed or not applicable).
  String? why(String key) => (_can[key] ?? false) ? null : _why[key];
}

class GhViewer {
  GhViewer(Map<String, dynamic> j)
    : login = _s(j['login']),
      role = j['role'] as String?,
      isAuthor = j['isAuthor'] == true,
      canWrite = j['canWrite'] == true,
      needsReconnect = j['needsReconnect'] == true;

  const GhViewer.anonymous()
    : login = '',
      role = null,
      isAuthor = false,
      canWrite = false,
      needsReconnect = false;

  final String login;
  final String? role;
  final bool isAuthor, canWrite, needsReconnect;
}

class GhLabelFull extends GhLabel {
  GhLabelFull(Map<String, dynamic> j)
    : description = _s(j['description']),
      super(_s(j['name']), _s(j['color']));
  final String description;
}

class GhMilestone {
  GhMilestone(Map<String, dynamic> j)
    : title = _s(j['title']),
      dueOn = _date(j['dueOn']),
      url = _s(j['url']);
  final String title, url;
  final DateTime? dueOn;
}

/// The header of a pull request or issue screen.
class GhItemDetail {
  GhItemDetail(Map<String, dynamic> j)
    : repo = _s(j['repo']),
      number = _i(j['number']),
      title = _s(j['title']),
      state = _s(j['state']),
      stateReason = j['stateReason'] as String?,
      isPr = j['isPr'] == true,
      body = _s(j['body']),
      url = _s(j['url']),
      user = GhUser.fromJson(j['user']),
      labels = [for (final l in _list(j['labels'])) GhLabelFull(l)],
      assignees = _users(j['assignees']),
      requestedReviewers = _users(j['requestedReviewers']),
      requestedTeams = [
        for (final t in (j['requestedTeams'] as List? ?? const [])) '$t',
      ],
      milestone = j['milestone'] is Map<String, dynamic>
          ? GhMilestone(j['milestone'] as Map<String, dynamic>)
          : null,
      head = _s(j['head']),
      headRepo = j['headRepo'] as String?,
      headSha = _s(j['headSha']),
      base = _s(j['base']),
      createdAt = _date(j['createdAt']),
      updatedAt = _date(j['updatedAt']),
      closedAt = _date(j['closedAt']),
      mergedAt = _date(j['mergedAt']),
      mergedBy = GhUser.fromJson(j['mergedBy']),
      commits = _i(j['commits']),
      additions = _i(j['additions']),
      deletions = _i(j['deletions']),
      changedFiles = _i(j['changedFiles']),
      comments = _i(j['comments']),
      locked = j['locked'] == true,
      mergeable = j['mergeable'] as bool?,
      mergeableState = j['mergeableState'] as String?,
      mergeMethods = [
        for (final m in const ['squash', 'merge', 'rebase'])
          if (_map(j['mergeMethods'])[m] != false) m,
      ],
      reactions = {
        for (final e in _map(j['reactions']).entries) e.key: _i(e.value),
      },
      can = GhCan(_map(j['can']), _map(j['why'])),
      viewer = GhViewer(_map(j['viewer']));

  final String repo, title, state, body, url, head, headSha, base;
  final int number, commits, additions, deletions, changedFiles, comments;
  final String? stateReason, headRepo, mergeableState;
  final bool isPr, locked;
  final bool? mergeable;
  final GhUser? user, mergedBy;
  final List<GhLabelFull> labels;
  final List<GhUser> assignees, requestedReviewers;
  final List<String> requestedTeams;
  final GhMilestone? milestone;
  final DateTime? createdAt, updatedAt, closedAt, mergedAt;

  /// Allowed merge methods, squash first.
  final List<String> mergeMethods;
  final Map<String, int> reactions;
  final GhCan can;
  final GhViewer viewer;

  String get owner => repo.split('/').first;
  String get name => repo.split('/').last;
  bool get isOpen => state == 'open' || state == 'draft';
}

class GhThreadComment {
  GhThreadComment(Map<String, dynamic> j)
    : id = _i(j['id']),
      path = _s(j['path']),
      line = _iOrNull(j['line']),
      diffHunk = _s(j['diffHunk']),
      body = _s(j['body']),
      user = GhUser.fromJson(j['user']),
      at = _date(j['at']),
      url = _s(j['url']);
  final int id;
  final String path, diffHunk, body, url;
  final int? line;
  final GhUser? user;
  final DateTime? at;
}

enum GhTimelineKind { comment, review, commit, event }

class GhTimelineItem {
  GhTimelineItem(Map<String, dynamic> j)
    : kind = GhTimelineKind.values.firstWhere(
        (k) => k.name == j['kind'],
        orElse: () => GhTimelineKind.event,
      ),
      id = _s(j['id']),
      at = _date(j['at']),
      actor = GhUser.fromJson(j['actor']),
      event = _s(j['event']),
      body = _s(j['body']),
      state = _s(j['state']),
      label = j['label'] is Map<String, dynamic>
          ? GhLabel(_s(j['label']['name']), _s(j['label']['color']))
          : null,
      detail = _s(j['detail']),
      sha = _s(j['sha']),
      url = _s(j['url']),
      reactions = {
        for (final e in _map(j['reactions']).entries) e.key: _i(e.value),
      },
      comments = [for (final c in _list(j['comments'])) GhThreadComment(c)];

  final GhTimelineKind kind;
  final String id, event, body, state, detail, sha, url;
  final DateTime? at;
  final GhUser? actor;
  final GhLabel? label;
  final Map<String, int> reactions;
  final List<GhThreadComment> comments;
}

class GhPrCommit {
  GhPrCommit(Map<String, dynamic> j)
    : sha = _s(j['sha']),
      shortSha = _s(j['shortSha']),
      message = _s(j['message']),
      author = GhUser.fromJson(j['author']),
      authorName = _s(j['authorName']),
      date = _date(j['date']),
      verified = j['verified'] == true;
  final String sha, shortSha, message, authorName;
  final GhUser? author;
  final DateTime? date;
  final bool verified;

  String get who => author?.login ?? authorName;
}

enum GhCheckState { pass, fail, pending, skipped, neutral }

class GhCheckRun {
  GhCheckRun(Map<String, dynamic> j)
    : name = _s(j['name']),
      status = GhCheckState.values.firstWhere(
        (s) => s.name == j['status'],
        orElse: () => GhCheckState.pending,
      ),
      detail = _s(j['detail']),
      url = _s(j['url']),
      app = _s(j['app']);
  final String name, detail, url, app;
  final GhCheckState status;
}

class GhChecks {
  GhChecks(Map<String, dynamic> j)
    : overall = _s(j['overall']),
      pass = _i(_map(j['summary'])['pass']),
      fail = _i(_map(j['summary'])['fail']),
      pending = _i(_map(j['summary'])['pending']),
      skipped = _i(_map(j['summary'])['skipped']),
      items = [for (final c in _list(j['items'])) GhCheckRun(c)],
      unavailable = j['unavailable'] as String?;
  final String overall;
  final int pass, fail, pending, skipped;
  final List<GhCheckRun> items;

  /// Set when the token may not read checks here.
  final String? unavailable;
}

/// One item of the account's activity feed (`/my/events`).
class GhActivity {
  GhActivity(Map<String, dynamic> j)
    : id = _s(j['id']),
      type = _s(j['type']),
      action = _s(j['action']),
      repo = _s(j['repo']),
      at = _date(j['at']),
      title = _s(j['title']),
      number = _iOrNull(j['number']),
      isPr = j['isPr'] == true,
      sha = j['sha'] as String?,
      ref = j['ref'] as String?,
      url = _s(j['url']),
      body = _s(j['body']),
      commits = [
        for (final c in _list(j['commits'])) (_s(c['sha']), _s(c['message'])),
      ],
      releaseTag = _s(_map(j['release'])['tag']),
      releaseName = _s(_map(j['release'])['name']);

  final String id, type, action, repo, title, url, body;
  final String releaseTag, releaseName;
  final DateTime? at;
  final int? number;
  final bool isPr;
  final String? sha, ref;
  final List<(String, String)> commits;
}
