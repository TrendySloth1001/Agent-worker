/// What kind of update a release is. Order is severity, lowest first.
enum UpdateKind {
  patch,
  feature,
  major,
  critical;

  static UpdateKind parse(Object? raw) =>
      values.where((k) => k.name == raw).firstOrNull ?? UpdateKind.feature;

  /// Patch updates never interrupt; the rest may show the sheet.
  bool get promptsSheet => this == feature || this == major;
}

/// The public face of a live release (`GET /app/update`).
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.build,
    required this.kind,
    this.title = '',
    this.notes = const [],
    this.size = 0,
    this.sha256 = '',
    this.url = '',
  });

  final String version;
  final int build;
  final UpdateKind kind;
  final String title;
  final List<String> notes;

  /// Bytes.
  final int size;
  final String sha256;

  /// Presigned download link (valid about an hour).
  final String url;

  factory UpdateRelease.fromJson(Map<String, dynamic> j) => UpdateRelease(
    version: j['version'] as String? ?? '',
    build: (j['build'] as num?)?.toInt() ?? 0,
    kind: UpdateKind.parse(j['kind']),
    title: j['title'] as String? ?? '',
    notes: [
      for (final n in j['notes'] as List? ?? const [])
        if (n is String && n.trim().isNotEmpty) n.trim(),
    ],
    size: (j['size'] as num?)?.toInt() ?? 0,
    sha256: (j['sha256'] as String? ?? '').toLowerCase(),
    url: j['url'] as String? ?? '',
  );
}

/// The answer of the update check.
class UpdateInfo {
  const UpdateInfo({
    required this.current,
    this.latest,
    this.minSupportedBuild,
    this.required = false,
  });

  final int current;
  final UpdateRelease? latest;
  final int? minSupportedBuild;

  /// Blocking: a critical update, or this build is below the minimum.
  final bool required;

  bool get hasUpdate => latest != null;

  factory UpdateInfo.fromJson(Map<String, dynamic> j) {
    final latest = j['latest'];
    return UpdateInfo(
      current: (j['current'] as num?)?.toInt() ?? 0,
      latest: latest is Map<String, dynamic>
          ? UpdateRelease.fromJson(latest)
          : null,
      minSupportedBuild: (j['minSupportedBuild'] as num?)?.toInt(),
      required: j['required'] == true,
    );
  }
}

/// Lifecycle of a release, owner side.
enum ReleaseStatus {
  draft,
  live,
  pulled;

  static ReleaseStatus parse(Object? raw) =>
      values.where((s) => s.name == raw).firstOrNull ?? ReleaseStatus.draft;
}

/// A release as the owner sees it (`/app/releases`).
class OwnerRelease {
  const OwnerRelease({
    required this.id,
    required this.release,
    required this.status,
    this.minSupportedBuild,
    this.createdAt,
    this.publishedAt,
  });

  final String id;
  final UpdateRelease release;
  final ReleaseStatus status;
  final int? minSupportedBuild;
  final DateTime? createdAt, publishedAt;

  String get version => release.version;
  int get build => release.build;
  UpdateKind get kind => release.kind;
  String get title => release.title;
  List<String> get notes => release.notes;
  int get size => release.size;

  /// Only drafts and pulled releases may be deleted.
  bool get canDelete => status != ReleaseStatus.live;

  factory OwnerRelease.fromJson(Map<String, dynamic> j) => OwnerRelease(
    id: j['id'] as String? ?? '',
    release: UpdateRelease.fromJson(j),
    status: ReleaseStatus.parse(j['status']),
    minSupportedBuild: (j['minSupportedBuild'] as num?)?.toInt(),
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
    publishedAt: DateTime.tryParse(j['publishedAt'] as String? ?? ''),
  );
}

/// How many people run one build.
class AdoptionRow {
  const AdoptionRow({
    required this.build,
    required this.version,
    required this.users,
  });

  final int build;
  final String version;
  final int users;

  factory AdoptionRow.fromJson(Map<String, dynamic> j) => AdoptionRow(
    build: (j['build'] as num?)?.toInt() ?? 0,
    version: j['version'] as String? ?? '',
    users: (j['users'] as num?)?.toInt() ?? 0,
  );
}

/// Install attempts reported for one target build.
class InstallStats {
  const InstallStats({
    required this.build,
    this.stages = const {},
    this.successRate,
  });

  final int build;

  /// Event count per stage name (`install_ok`, `download_fail`, ...).
  final Map<String, int> stages;

  /// install_ok / (install_ok + install_fail + verify_fail); null with none.
  final double? successRate;

  int count(String stage) => stages[stage] ?? 0;

  /// Download or install attempts that ended badly.
  int get failures =>
      count('download_fail') +
      count('verify_fail') +
      count('signature_mismatch') +
      count('install_fail');

  bool get isEmpty => stages.isEmpty;

  factory InstallStats.fromJson(Map<String, dynamic> j) => InstallStats(
    build: (j['build'] as num?)?.toInt() ?? 0,
    stages: {
      for (final s in j['stages'] as List? ?? const [])
        if (s is Map<String, dynamic> && s['stage'] is String)
          s['stage'] as String: (s['count'] as num?)?.toInt() ?? 0,
    },
    successRate: (j['successRate'] as num?)?.toDouble(),
  );
}

/// `GET /app/releases`.
class ReleaseList {
  const ReleaseList({
    this.releases = const [],
    this.adoption = const [],
    this.installs = const [],
  });

  final List<OwnerRelease> releases;
  final List<AdoptionRow> adoption;
  final List<InstallStats> installs;

  /// Install stats for [build], or null when nothing was reported.
  InstallStats? installsFor(int build) =>
      installs.where((i) => i.build == build).firstOrNull;

  factory ReleaseList.fromJson(Map<String, dynamic> j) => ReleaseList(
    releases: [
      for (final r in j['releases'] as List? ?? const [])
        if (r is Map<String, dynamic>) OwnerRelease.fromJson(r),
    ],
    adoption: [
      for (final r in j['adoption'] as List? ?? const [])
        if (r is Map<String, dynamic>) AdoptionRow.fromJson(r),
    ],
    installs: [
      for (final r in j['installs'] as List? ?? const [])
        if (r is Map<String, dynamic>) InstallStats.fromJson(r),
    ],
  );
}

/// Fields of a release edit; only what is set is sent.
class ReleaseEdit {
  const ReleaseEdit({
    this.status,
    this.kind,
    this.title,
    this.notes,
    this.minSupportedBuild,
    this.clearMin = false,
  });

  final ReleaseStatus? status;
  final UpdateKind? kind;
  final String? title;
  final List<String>? notes;
  final int? minSupportedBuild;

  /// Sends `minSupportedBuild: null`.
  final bool clearMin;

  Map<String, dynamic> toJson() => {
    'status': ?status?.name,
    'kind': ?kind?.name,
    'title': ?title,
    'notes': ?notes,
    if (clearMin)
      'minSupportedBuild': null
    else
      'minSupportedBuild': ?minSupportedBuild,
  };
}
