import 'package:flutter/foundation.dart';

import '../../core/constants/apps.dart';
import '../../data/chat_api.dart';
import '../../data/github_api.dart';

enum RepoSort { pushed, name, stars }

enum RepoFilter { all, public, private, forks }

/// The state of one lazily loaded list.
class Loadable<T> {
  Loadable({this.data, this.error, this.loading = false});

  T? data;
  Object? error;
  bool loading;

  bool get failed => error != null;
  bool get ready => data != null;

  /// A message for the error state.
  String get message {
    final e = error;
    return e is ApiException && e.message.isNotEmpty
        ? e.message
        : GithubHubStrings.loadFailed;
  }
}

/// What the GitHub screen shows: the account, every repository with search,
/// sort and filter, and the pull requests, issues and commits tabs.
class GithubHubController extends ChangeNotifier {
  GithubHubController({GithubApi? api}) : _api = api;

  final GithubApi? _api;
  GithubApi get api => _api ?? GithubApi.instance;

  GhMe? me;
  List<GhRepo> repos = const [];
  bool loading = false;
  bool loaded = false;
  Object? error;

  String query = '';
  RepoSort sort = RepoSort.pushed;
  RepoFilter filter = RepoFilter.all;

  /// How many of the filtered repositories are on screen (grows on scroll).
  int visible = GithubHubSizes.reposPage;

  final pulls = Loadable<List<GhIssue>>();
  final issues = Loadable<List<GhIssue>>();
  final activity = Loadable<List<GhCommit>>();

  bool get failedOnce => error != null;

  bool _disposed = false;
  int _gen = 0;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool refresh = false}) async {
    final gen = ++_gen;
    loading = true;
    error = null;
    _notify();
    try {
      final r = await Future.wait([
        api.me(),
        api.myRepos(refresh: refresh),
      ]);
      if (gen != _gen) return;
      me = r[0] as GhMe;
      repos = r[1] as List<GhRepo>;
      loaded = true;
      visible = GithubHubSizes.reposPage;
    } catch (e) {
      if (gen != _gen) return;
      error = e;
    }
    loading = false;
    _notify();
  }

  /// Reloads the account and whatever tabs were opened.
  Future<void> refreshAll() async {
    await Future.wait([
      load(refresh: true),
      if (pulls.ready || pulls.failed) loadPulls(),
      if (issues.ready || issues.failed) loadIssues(),
      if (activity.ready || activity.failed) loadActivity(),
    ]);
  }

  // ---- repositories ------------------------------------------------------

  void setQuery(String value) {
    if (value == query) return;
    query = value;
    visible = GithubHubSizes.reposPage;
    _notify();
  }

  void setSort(RepoSort value) {
    sort = value;
    visible = GithubHubSizes.reposPage;
    _notify();
  }

  void setFilter(RepoFilter value) {
    filter = value;
    visible = GithubHubSizes.reposPage;
    _notify();
  }

  /// Repositories matching the query and filter, in the chosen order.
  List<GhRepo> get filtered {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    bool matches(GhRepo r) {
      switch (filter) {
        case RepoFilter.all:
          break;
        case RepoFilter.public:
          if (r.isPrivate) return false;
        case RepoFilter.private:
          if (!r.isPrivate) return false;
        case RepoFilter.forks:
          if (!r.fork) return false;
      }
      if (words.isEmpty) return true;
      final hay = [
        r.fullName,
        r.description,
        r.language ?? '',
        ...r.topics,
      ].join(' ').toLowerCase();
      return words.every(hay.contains);
    }

    final list = [
      for (final r in repos)
        if (matches(r)) r,
    ];
    int pushed(GhRepo a, GhRepo b) => (b.pushedAt ?? DateTime(0)).compareTo(
      a.pushedAt ?? DateTime(0),
    );
    switch (sort) {
      case RepoSort.pushed:
        list.sort(pushed);
      case RepoSort.name:
        list.sort(
          (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
      case RepoSort.stars:
        list.sort((a, b) {
          final c = b.stars.compareTo(a.stars);
          return c != 0 ? c : pushed(a, b);
        });
    }
    return list;
  }

  List<GhRepo> get shown => filtered.take(visible).toList();
  bool get hasMore => visible < filtered.length;

  void showMore() {
    if (!hasMore) return;
    visible += GithubHubSizes.reposPage;
    _notify();
  }

  // ---- tabs ---------------------------------------------------------------

  Future<void> loadPulls() => _fill<List<GhIssue>>(
    pulls,
    () async => (await api.involvedPulls(me!.login)).items,
  );

  Future<void> loadIssues() => _fill<List<GhIssue>>(
    issues,
    () async => (await api.involvedIssues(me!.login)).items,
  );

  Future<void> loadActivity() => _fill<List<GhCommit>>(
    activity,
    () async => (await api.activity(me!.login)).items,
  );

  Future<void> _fill<T>(Loadable<T> slot, Future<T> Function() fetch) async {
    if (me == null) return;
    slot.loading = true;
    slot.error = null;
    _notify();
    try {
      slot.data = await fetch();
    } catch (e) {
      slot.error = e;
    }
    slot.loading = false;
    _notify();
  }

  /// Opening a tab loads it once.
  void ensureTab(int index) {
    switch (index) {
      case 1 when !pulls.ready && !pulls.loading && !pulls.failed:
        loadPulls();
      case 2 when !issues.ready && !issues.loading && !issues.failed:
        loadIssues();
      case 3 when !activity.ready && !activity.loading && !activity.failed:
        loadActivity();
    }
  }
}
