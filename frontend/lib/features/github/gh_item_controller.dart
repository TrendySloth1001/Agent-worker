import 'package:flutter/foundation.dart';

import '../../core/constants/github_detail.dart';
import '../../data/github_api.dart';
import 'github_controller.dart';

/// The last good data of an item, so reopening it (or a failed refresh,
/// e.g. rate limited) still shows something.
class _Memo {
  GhItemDetail? detail;
  List<GhTimelineItem>? timeline;
  List<GhPrCommit>? commits;
  (List<GhFile>, bool)? files;
  GhChecks? checks;
}

/// State of one pull request or issue screen: the header, the lazily loaded
/// tabs, and the write actions (which reload what they changed).
class GhItemController extends ChangeNotifier {
  GhItemController({
    required this.owner,
    required this.repo,
    required this.number,
    required this.isPr,
    GithubApi? api,
  }) : _api = api {
    final m = _memo[key];
    if (m != null) {
      detail = m.detail;
      timeline.data = m.timeline;
      commits.data = m.commits;
      files.data = m.files;
      checks.data = m.checks;
    }
  }

  final String owner, repo;
  final int number;
  final bool isPr;
  final GithubApi? _api;
  GithubApi get api => _api ?? GithubApi.instance;

  static final _memo = <String, _Memo>{};

  @visibleForTesting
  static void clearMemo() => _memo.clear();

  String get key => '$owner/$repo#$number';
  String get fullName => '$owner/$repo';

  GhItemDetail? detail;
  bool loading = false;

  /// The last load failed; with [detail] set, the screen shows saved data.
  Object? error;

  /// A write is running (buttons show progress, no double submit).
  bool busy = false;

  final timeline = Loadable<List<GhTimelineItem>>();
  final commits = Loadable<List<GhPrCommit>>();
  final files = Loadable<(List<GhFile>, bool)>();
  final checks = Loadable<GhChecks>();

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  _Memo get _m {
    final m = _memo.remove(key) ?? _Memo();
    _memo[key] = m; // most recent last
    while (_memo.length > GhDetailSizes.memoMax) {
      _memo.remove(_memo.keys.first);
    }
    return m;
  }

  /// Loads the header and the conversation (and refreshes opened tabs).
  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      final d = isPr
          ? await api.pullDetail(owner, repo, number)
          : await api.issueDetail(owner, repo, number);
      detail = d;
      _m.detail = d;
    } catch (e) {
      error = e;
    }
    loading = false;
    _notify();
    await Future.wait([
      loadTimeline(),
      if (commits.ready || commits.failed) loadCommits(),
      if (files.ready || files.failed) loadFiles(),
      if (checks.ready || checks.failed) loadChecks(),
    ]);
  }

  Future<void> loadTimeline() => _fill(
    timeline,
    () => api.timeline(owner, repo, number, pr: isPr),
    (v) => _m.timeline = v,
  );

  Future<void> loadCommits() => _fill(
    commits,
    () => api.pullCommits(owner, repo, number),
    (v) => _m.commits = v,
  );

  Future<void> loadFiles() => _fill(
    files,
    () => api.pullChangedFiles(owner, repo, number),
    (v) => _m.files = v,
  );

  Future<void> loadChecks() => _fill(
    checks,
    () => api.pullChecks(owner, repo, number),
    (v) => _m.checks = v,
  );

  /// Keeps old data on failure (the tab shows it with the error).
  Future<void> _fill<T>(
    Loadable<T> slot,
    Future<T> Function() fetch,
    void Function(T) remember,
  ) async {
    slot.loading = true;
    slot.error = null;
    _notify();
    try {
      final v = await fetch();
      slot.data = v;
      remember(v);
    } catch (e) {
      slot.error = e;
    }
    slot.loading = false;
    _notify();
  }

  /// Opening a tab loads it once (1 commits, 2 files, 3 checks).
  void ensureTab(int index) {
    Loadable<Object?>? slot;
    Future<void> Function()? load;
    switch (index) {
      case 1:
        (slot, load) = (commits, loadCommits);
      case 2:
        (slot, load) = (files, loadFiles);
      case 3:
        (slot, load) = (checks, loadChecks);
    }
    if (slot == null || load == null) return;
    if (!slot.ready && !slot.loading && !slot.failed) load();
  }

  /// Runs a write; on success reloads the header and conversation. Returns
  /// the error (the screen explains it) or null.
  Future<Object?> run(Future<void> Function(GithubApi api) action) async {
    if (busy) return null;
    busy = true;
    _notify();
    Object? failure;
    try {
      await action(api);
    } catch (e) {
      failure = e;
    }
    busy = false;
    _notify();
    if (failure == null) await load();
    return failure;
  }

  // ---- actions --------------------------------------------------------------

  Future<Object?> comment(String body) =>
      run((a) => a.comment(owner, repo, number, body));

  Future<Object?> review(String event, String body) =>
      run((a) => a.submitReview(owner, repo, number, event: event, body: body));

  Future<Object?> merge(String method, String title) => run(
    (a) => a.merge(
      owner,
      repo,
      number,
      method: method,
      title: title,
      sha: detail?.headSha,
    ),
  );

  Future<Object?> changeState(String state, {String? reason}) => run(
    (a) => a.updateItem(owner, repo, number, state: state, stateReason: reason),
  );

  Future<Object?> setLabels(List<String> labels) =>
      run((a) => a.updateItem(owner, repo, number, labels: labels));

  Future<Object?> setAssignees(List<String> logins) =>
      run((a) => a.updateItem(owner, repo, number, assignees: logins));

  Future<Object?> edit({String? title, String? body}) =>
      run((a) => a.updateItem(owner, repo, number, title: title, body: body));

  Future<Object?> markReady() => run((a) => a.markReady(owner, repo, number));

  Future<Object?> react(String content) =>
      run((a) => a.react(owner, repo, number, content));
}
