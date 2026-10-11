import 'package:flutter/painting.dart' show Color;
import 'package:hugeicons/hugeicons.dart';

import 'app_colors.dart';
import 'app_icons.dart';

/// Fenced languages of the live GitHub widgets.
abstract final class GithubLang {
  static const repo = 'github-repo';
  static const search = 'github-search';
  static const commits = 'github-commits';
  static const tree = 'github-tree';
  static const compare = 'github-compare';
  static const prs = 'github-prs';
  static const issues = 'github-issues';
}

abstract final class GithubStrings {
  static const repo = 'GITHUB REPO';
  static const search = 'GITHUB SEARCH';
  static const commits = 'COMMITS';
  static const tree = 'FILES';
  static const compare = 'COMPARE';
  static const prs = 'PULL REQUESTS';
  static const issues = 'ISSUES';

  static const visit = 'VISIT';
  static const open = 'OPEN';
  static const copy = 'COPY';
  static const retry = 'RETRY';
  static const loadMore = 'SHOW MORE';
  static const showLess = 'SHOW LESS';
  static const stars = 'STARS';
  static const forks = 'FORKS';
  static const issuesShort = 'ISSUES';
  static const watchers = 'WATCHING';
  static const languages = 'LANGUAGES';
  static const topics = 'TOPICS';
  static const latestRelease = 'LATEST RELEASE';
  static const license = 'LICENSE';
  static const archived = 'ARCHIVED';
  static const readme = 'README';
  static const files = 'FILES CHANGED';
  static const commitsShort = 'COMMITS';
  static const ahead = 'AHEAD';
  static const behind = 'BEHIND';
  static const changed = 'CHANGED';
  static const noResults = 'Nothing found.';
  static const noPatch = 'No text diff (binary or too large).';
  static const patchTruncated = '…diff truncated';
  static const filesTruncated = 'More files on GitHub.';
  static const binaryFile = 'Binary file, open it on GitHub.';
  static const largeFile = 'File too large to preview, open it on GitHub.';
  static const fileTruncated = '…file truncated';
  static const treeTruncated = 'Listing truncated.';
  static const emptyBody = 'No description.';
  static const badSpec = 'Expected owner/repo';
  static const badCompare = 'Expected owner/repo base...head';
  static const badSearch = 'Expected a search query';
  static const loadFailed = 'Could not load from GitHub.';
  static const root = 'ROOT';
  static const up = '..';
  static const by = 'by';
  static const into = '→';
  static const prerelease = 'PRE';
  static const total = 'RESULTS';
  static const typeRepos = 'repos';
  static const typeCode = 'code';
  static const typeIssues = 'issues';
  static const typeCommits = 'commits';

  static const stateOpen = 'open';
  static const stateClosed = 'closed';
  static const stateAll = 'all';
  static const stateMerged = 'merged';
  static const stateDraft = 'draft';

  static const keyType = 'type';
  static const keyQuery = 'q';
  static const keyQueryLong = 'query';
  static const keySort = 'sort';
  static const keyState = 'state';

  static String titled(String base, String detail) => '$base / $detail';
  static String countOf(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1)}M'
      : n >= 10000
      ? '${(n / 1000).round()}k'
      : n >= 1000
      ? '${(n / 1000).toStringAsFixed(1)}k'
      : '$n';
  static String plus(int n) => '+$n';
  static String minus(int n) => '−$n';
  static String issueNumber(int n) => '#$n';
  static String commentsCount(int n) => '$n';
  static String pct(double v) => '${v.toStringAsFixed(v >= 10 ? 0 : 1)}%';
  static String bytes(int b) => b >= 1048576
      ? '${(b / 1048576).toStringAsFixed(1)} MB'
      : b >= 1024
      ? '${(b / 1024).toStringAsFixed(1)} KB'
      : '$b B';

  /// Compact age, e.g. `3H`, `2D`, `5MO`.
  static String ago(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'NOW';
    if (d.inHours < 1) return '${d.inMinutes}M';
    if (d.inDays < 1) return '${d.inHours}H';
    if (d.inDays < 30) return '${d.inDays}D';
    if (d.inDays < 365) return '${d.inDays ~/ 30}MO';
    return '${d.inDays ~/ 365}Y';
  }

  static String preparing(String name) => 'PREPARING $name…';
}

/// Iconify `octicon:` ids (GitHub's own glyphs), drawn via InlineIcon.
abstract final class GithubOcticons {
  static const set = 'octicon';
  static const mark = 'mark-github-16';
  static const repo = 'repo-16';
  static const star = 'star-16';
  static const fork = 'repo-forked-16';
  static const eye = 'eye-16';
  static const issueOpen = 'issue-opened-16';
  static const issueClosed = 'issue-closed-16';
  static const issueSkipped = 'skip-16';
  static const commit = 'git-commit-16';
  static const branch = 'git-branch-16';
  static const pr = 'git-pull-request-16';
  static const prClosed = 'git-pull-request-closed-16';
  static const prDraft = 'git-pull-request-draft-16';
  static const merged = 'git-merge-16';
  static const compare = 'git-compare-16';
  static const fileCode = 'file-code-16';
  static const file = 'file-16';
  static const dir = 'file-directory-fill-16';
  static const dirOpen = 'file-directory-open-fill-16';
  static const submodule = 'file-submodule-16';
  static const symlink = 'file-symlink-file-16';
  static const added = 'diff-added-16';
  static const removed = 'diff-removed-16';
  static const modified = 'diff-modified-16';
  static const renamed = 'diff-renamed-16';
  static const law = 'law-16';
  static const tag = 'tag-16';
  static const search = 'search-16';
  static const code = 'code-16';
  static const comment = 'comment-16';
  static const people = 'people-16';
}

/// Hugeicons for actions and chrome around the GitHub widgets.
abstract final class GithubIcons {
  static const github = HugeIcons.strokeRoundedGithub;
  static const branch = HugeIcons.strokeRoundedGitBranch;
  static const commit = HugeIcons.strokeRoundedGitCommit;
  static const pr = HugeIcons.strokeRoundedGitPullRequest;
  static const compare = HugeIcons.strokeRoundedGitCompare;
  static const fork = HugeIcons.strokeRoundedGitFork;
  static const merge = HugeIcons.strokeRoundedGitMerge;
  static const star = HugeIcons.strokeRoundedStar;
  static const folder = HugeIcons.strokeRoundedFolder01;
  static const file = HugeIcons.strokeRoundedFile01;
  static const code = HugeIcons.strokeRoundedSourceCode;
  static const tag = HugeIcons.strokeRoundedTag01;
  static const visit = AppIcons.visit;
  static const open = AppIcons.openExternal;
  static const copy = AppIcons.copy;
  static const retry = AppIcons.regenerate;
  static const expand = AppIcons.expand;
  static const collapse = AppIcons.collapse;
  static const back = AppIcons.back;
  static const search = AppIcons.search;
  static const refresh = AppIcons.regenerate;
  static const fullscreen = AppIcons.fullscreen;
}

abstract final class GithubSizes {
  static const pad = 12.0;
  static const rowGap = 8.0;
  static const avatar = 28.0;
  static const avatarSmall = 18.0;
  static const avatarLarge = 40.0;
  static const octicon = 14.0;
  static const octiconSmall = 12.0;
  static const langBar = 6.0;
  static const langGap = 1.0;
  static const chipHeight = 22.0;
  static const chipPadH = 8.0;
  static const labelDot = 8.0;
  static const skeletonBar = 10.0;
  static const skeletonRows = 3;
  static const skeletonWidths = [0.9, 0.6, 0.75];
  static const codeMaxHeight = 420.0;
  static const treeIndent = 14.0;
  static const treeMaxHeight = 420.0;
  static const listMaxHeight = 520.0;
  static const fragmentLines = 6;
  static const descriptionLines = 3;
  static const bodyLines = 12;
  static const shaWidth = 64.0;

  /// Alpha steps for the monochrome language bar (largest first).
  static const langAlphas = [0.9, 0.6, 0.42, 0.3, 0.2, 0.14, 0.1, 0.07];
  static const labelAlpha = 0.14;
  static const skeletonAlpha = 0.5;
}

abstract final class GithubLimits {
  static const pageRepos = 8;
  static const pageCommits = 15;
  static const pageItems = 15;
  static const initialVisible = 6;
  static const topics = 8;
  static const languages = 6;
  static const filesVisible = 8;
}

abstract final class GithubDurations {
  static const timeout = Duration(seconds: 25);
  static const expand = Duration(milliseconds: 200);
}

// ---- PR review + my repositories ---------------------------------------------

/// Fenced languages of the review and account widgets.
abstract final class GithubLangExtra {
  static const review = 'github-review';
  static const myRepos = 'github-my-repos';
}

abstract final class GithubReviewStrings {
  static const title = 'PR REVIEW';
  static const myRepos = 'MY REPOS';
  static const review = 'REVIEW';
  static const reviewing = 'REVIEWING THE DIFF…';
  static const reviewingHint =
      'A large model reads every changed file. '
      'This usually takes under a minute.';
  static const rerun = 'RE-RUN';
  static const copyAll = 'COPY';
  static const badSpec = 'Expected owner/repo#123';
  static const summary = 'SUMMARY';
  static const tests = 'SUGGESTED TESTS';
  static const comments = 'COMMENTS';
  static const noComments = 'No problems found.';
  static const suggestion = 'SUGGESTION';
  static const risk = 'RISK';
  static const hunkMissing = 'No diff hunk for this line.';
  static const skipped = 'NOT REVIEWED';
  static const cached = 'CACHED';
  static const privateBadge = 'PRIVATE';
  static const empty = 'No repositories.';

  static const verdictApprove = 'APPROVE';
  static const verdictComment = 'COMMENT';
  static const verdictChanges = 'CHANGES REQUESTED';

  static const sevBlocker = 'BLOCKER';
  static const sevMajor = 'MAJOR';
  static const sevMinor = 'MINOR';
  static const sevNit = 'NIT';

  static const riskLow = 'LOW';
  static const riskMedium = 'MEDIUM';
  static const riskHigh = 'HIGH';

  static String verdict(String v) => switch (v) {
    'approve' => verdictApprove,
    'request_changes' => verdictChanges,
    _ => verdictComment,
  };

  static String severity(String s) => switch (s) {
    'blocker' => sevBlocker,
    'major' => sevMajor,
    'nit' => sevNit,
    _ => sevMinor,
  };

  static String riskLabel(String r) => switch (r) {
    'high' => riskHigh,
    'low' => riskLow,
    _ => riskMedium,
  };

  static String lineOf(int line) => 'L$line';
  static String spec(String owner, String repo, int n) => '$owner/$repo#$n';
  static String byAuthor(String login) => '@$login';
  static String visibilityTitle(String v) =>
      v == 'all' ? myRepos : '$myRepos / ${v.toUpperCase()}';

  /// The whole review as markdown, for COPY.
  static String markdownHeader(String title, String spec, String verdict) =>
      '## Review: $title ($spec)\n\n**Verdict:** $verdict';
}

/// Octicons for review severities and verdicts.
abstract final class GithubReviewOcticons {
  static const blocker = 'stop-16';
  static const major = 'alert-16';
  static const minor = 'info-16';
  static const nit = 'dot-16';
  static const approve = 'check-circle-16';
  static const changes = 'x-circle-16';
  static const comment = 'comment-discussion-16';
  static const shield = 'shield-16';
  static const lock = 'lock-16';
  static const beaker = 'beaker-16';
  static const light = 'light-bulb-16';
  static const person = 'person-16';

  static String severity(String s) => switch (s) {
    'blocker' => blocker,
    'major' => major,
    'nit' => nit,
    _ => minor,
  };

  static String verdict(String v) => switch (v) {
    'approve' => approve,
    'request_changes' => changes,
    _ => comment,
  };
}

abstract final class GithubReviewSizes {
  static const riskSegments = 3;
  static const riskSegmentWidth = 14.0;
  static const riskSegmentHeight = 6.0;
  static const riskGap = 2.0;
  static const hunkMaxHeight = 280.0;
  static const commentIndent = GithubSizes.octicon + 8.0;
  static const progressHeight = 2.0;
}

abstract final class GithubReviewLimits {
  static const pageMyRepos = 30;
}

abstract final class GithubReviewDurations {
  static const reviewTimeout = Duration(minutes: 4);
}

// ---- git graph (```github-graph) ---------------------------------------------

/// Fenced language and block keys of the git graph widget.
abstract final class GithubGraphLang {
  static const graph = 'github-graph';
  static const keyBranches = 'branches';
  static const keyLimit = 'limit';
}

abstract final class GithubGraphStrings {
  static const title = 'GIT GRAPH';
  static const colGraph = 'GRAPH';
  static const colSubject = 'DESCRIPTION';
  static const colDate = 'DATE';
  static const colAuthor = 'AUTHOR';
  static const colSha = 'COMMIT';
  static const refresh = 'REFRESH';
  static const fullscreen = 'FULLSCREEN';
  static const back = 'Back';
  static const empty = 'No commits on these branches.';
  static const notFound =
      'Repository not found. Check owner/repo; '
      'private repos need GitHub connected.';
  static const truncated = 'OLDER HISTORY NOT LOADED';
  static const overflow = 'MORE LANES';

  static String commits(int n) => '$n COMMITS';
  static String branches(int n) => n == 1 ? '1 BRANCH' : '$n BRANCHES';
  static String moreRefs(int n) => '+$n';
  static String webUrl(String repo) => 'https://github.com/$repo/network';

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  /// `2026-10-11 16:40` in local time.
  static String dateTime(DateTime? d) => d == null
      ? ''
      : '${d.year}-${_pad2(d.month)}-${_pad2(d.day)} ${_pad2(d.hour)}:${_pad2(d.minute)}';
}

/// Lane colors: distinguishable on both the light and the dark theme.
/// Index 0 (the app's red) is reserved for the default branch.
abstract final class GithubGraphColors {
  static const defaultLane = 0;
  static const lanes = <Color>[
    AppColors.red,
    Color(0xFF3D7EFF), // blue
    Color(0xFF1FA35B), // green
    Color(0xFFE09B12), // amber
    Color(0xFF9B5DE5), // violet
    Color(0xFF12A4B8), // cyan
    Color(0xFFE0529C), // pink
    Color(0xFF7C8BA1), // slate
  ];

  static Color lane(int i) => lanes[i % lanes.length];

  /// Ref pill fill behind the lane-colored label.
  static const pillFillAlpha = 0.14;

  /// Stubs to parents outside the loaded history.
  static const danglingAlpha = 0.35;

  /// Text of merge rows.
  static const mergeTextAlpha = 0.55;
}

abstract final class GithubGraphSizes {
  static const rowHeight = 28.0;
  static const laneWidth = 14.0;
  static const graphPad = 10.0;
  static const line = 2.0;
  static const dot = 4.0;
  static const mergeDotStroke = 2.0;
  static const headRing = 2.5;

  /// Curve control points as a share of the row gap (0.5 = smooth S).
  static const curve = 0.6;
  static const overflowDot = 1.5;
  static const overflowGap = 4.0;

  static const cardHeight = 480.0;
  static const toolbarHeight = 40.0;
  static const headerHeight = 24.0;
  static const colGap = 8.0;
  static const subjectMin = 240.0;
  static const dateWidth = 118.0;
  static const authorWidth = 104.0;
  static const shaWidth = 78.0;
  static const pillHeight = 16.0;
  static const pillPadH = 5.0;
  static const pillMaxWidth = 140.0;
  static const chipDot = 8.0;
  static const fullscreenPad = 12.0;
  static const skeletonRows = 10;
}

abstract final class GithubGraphLimits {
  static const defaultLimit = 150;
  static const maxLimit = 300;
  static const minLimit = 10;

  /// Lanes drawn side by side; more collapse into the last one.
  static const maxLanes = 8;
  static const refsShown = 2;
}
