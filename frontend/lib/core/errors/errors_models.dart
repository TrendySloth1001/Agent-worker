// Owner-side models for /admin/errors and /admin/health/builds.

enum ErrorStatus { open, resolved, ignored }

ErrorStatus _status(Object? v) => ErrorStatus.values.firstWhere(
  (s) => s.name == v,
  orElse: () => ErrorStatus.open,
);

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class ErrorGroup {
  const ErrorGroup({
    required this.fingerprint,
    required this.title,
    required this.kind,
    required this.status,
    required this.count,
    required this.users,
    required this.firstBuild,
    required this.lastBuild,
    required this.lastSeen,
    this.buildCount,
    this.buildUsers,
  });

  final String fingerprint;
  final String title;
  final String kind;
  final ErrorStatus status;
  final int count;
  final int users;
  final int firstBuild;
  final int lastBuild;
  final DateTime? lastSeen;

  /// Counts for the selected build (null when listing all builds).
  final int? buildCount;
  final int? buildUsers;

  int get shownUsers => buildUsers ?? users;
  int get shownCount => buildCount ?? count;

  factory ErrorGroup.fromJson(Map<String, dynamic> j) => ErrorGroup(
    fingerprint: j['fingerprint'] as String? ?? '',
    title: j['title'] as String? ?? '',
    kind: j['kind'] as String? ?? 'dart',
    status: _status(j['status']),
    count: _int(j['count']),
    users: _int(j['users']),
    firstBuild: _int(j['firstBuild']),
    lastBuild: _int(j['lastBuild']),
    lastSeen: DateTime.tryParse(j['lastSeen'] as String? ?? ''),
    buildCount: (j['buildCount'] as num?)?.toInt(),
    buildUsers: (j['buildUsers'] as num?)?.toInt(),
  );
}

class ErrorGroupList {
  const ErrorGroupList({required this.groups, required this.builds});

  final List<ErrorGroup> groups;
  final List<int> builds;

  factory ErrorGroupList.fromJson(Map<String, dynamic> j) => ErrorGroupList(
    groups: [
      for (final g in (j['groups'] as List? ?? const []))
        ErrorGroup.fromJson(g as Map<String, dynamic>),
    ],
    builds: [for (final b in (j['builds'] as List? ?? const [])) _int(b)],
  );
}

class ErrorBuildRow {
  const ErrorBuildRow(this.build, this.count, this.users);

  final int build;
  final int count;
  final int users;
}

class ErrorSample {
  const ErrorSample({
    required this.id,
    required this.build,
    required this.at,
    required this.kind,
    required this.message,
    required this.stack,
    required this.breadcrumbs,
    required this.device,
    required this.user,
  });

  final String id;
  final int build;
  final DateTime? at;
  final String kind;
  final String message;
  final String stack;
  final List<String> breadcrumbs;
  final Map<String, dynamic> device;

  /// The first 8 characters of the user id; the e-mail is fetched on tap.
  final String user;

  factory ErrorSample.fromJson(Map<String, dynamic> j) => ErrorSample(
    id: '${j['id']}',
    build: _int(j['build']),
    at: DateTime.tryParse(j['at'] as String? ?? ''),
    kind: j['kind'] as String? ?? '',
    message: j['message'] as String? ?? '',
    stack: j['stack'] as String? ?? '',
    breadcrumbs: [
      for (final c in (j['breadcrumbs'] as List? ?? const []))
        if (c is Map) '${c['c'] ?? ''} ${c['m'] ?? ''}'.trim(),
    ],
    device: (j['device'] as Map?)?.cast<String, dynamic>() ?? const {},
    user: j['user'] as String? ?? '',
  );
}

class ErrorGroupDetail {
  const ErrorGroupDetail({
    required this.group,
    required this.builds,
    required this.samples,
  });

  final ErrorGroup group;
  final List<ErrorBuildRow> builds;
  final List<ErrorSample> samples;

  factory ErrorGroupDetail.fromJson(Map<String, dynamic> j) => ErrorGroupDetail(
    group: ErrorGroup.fromJson(j['group'] as Map<String, dynamic>),
    builds: [
      for (final b in (j['builds'] as List? ?? const []))
        ErrorBuildRow(
          _int((b as Map)['build']),
          _int(b['count']),
          _int(b['users']),
        ),
    ],
    samples: [
      for (final s in (j['samples'] as List? ?? const []))
        ErrorSample.fromJson(s as Map<String, dynamic>),
    ],
  );
}

class BuildHealth {
  const BuildHealth({
    required this.build,
    required this.sessions,
    required this.users,
    required this.crashed,
    required this.crashFree,
    required this.errorGroups,
  });

  final int build;
  final int sessions;
  final int users;
  final int crashed;

  /// 0..1, null without sessions.
  final double? crashFree;
  final int errorGroups;

  factory BuildHealth.fromJson(Map<String, dynamic> j) => BuildHealth(
    build: _int(j['build']),
    sessions: _int(j['sessions']),
    users: _int(j['users']),
    crashed: _int(j['crashed']),
    crashFree: (j['crashFree'] as num?)?.toDouble(),
    errorGroups: _int(j['errorGroups']),
  );
}
