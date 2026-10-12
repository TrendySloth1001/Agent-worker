import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/apps.dart';
import '../../core/constants/connections.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/connections_api.dart';
import '../../data/github_api.dart';
import '../chat/widgets/github/github_common.dart';
import '../chat/widgets/github/github_connect_card.dart';
import '../connections/connections_controller.dart';
import '../settings/widgets/settings_kit.dart';
import 'github_controller.dart';
import 'github_repo_screen.dart';
import 'github_search_screen.dart';
import 'widgets/gh_activity.dart';
import 'widgets/gh_rows.dart';

/// The connected GitHub account: who is linked, their repositories, pull
/// requests, issues and recent commits. Not connected, it offers to connect.
class GithubScreen extends StatefulWidget {
  const GithubScreen({super.key, this.connections, this.controller});

  /// Test seams; default to the app's connection state and the live API.
  final ConnectionsController? connections;
  final GithubHubController? controller;

  @override
  State<GithubScreen> createState() => _GithubScreenState();
}

class _GithubScreenState extends State<GithubScreen>
    with SingleTickerProviderStateMixin {
  late final ConnectionsController _conn =
      widget.connections ?? ConnectionsController.instance;
  late final GithubHubController _hub =
      widget.controller ?? GithubHubController();
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _scroll = ScrollController();
  final _search = TextEditingController();

  /// While the repo search has focus the profile header steps aside, so
  /// the results sit above the keyboard.
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _conn.addListener(_sync);
    _tabs.addListener(_onTab);
    _scroll.addListener(_onScroll);
    _conn.ensureLoaded();
    _sync();
  }

  @override
  void dispose() {
    _conn.removeListener(_sync);
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _scroll.dispose();
    _search.dispose();
    if (widget.controller == null) _hub.dispose();
    super.dispose();
  }

  /// Loads the data once the account is linked (and again for a new account).
  void _sync() {
    final g = _conn.github;
    if (g == null) return;
    if (_hub.loading) return;
    if (!_hub.loaded && !_hub.failedOnce) {
      _hub.load();
    } else if (_hub.me != null && _hub.me!.login != g.login) {
      _hub.load(refresh: true);
    }
  }

  void _onTab() {
    if (_tabs.indexIsChanging) return;
    _hub.ensureTab(_tabs.index);
    setState(() {});
  }

  void _onScroll() {
    if (_tabs.index != 0 || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter < GithubHubSizes.loadMoreExtent) {
      _hub.showMore();
    }
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String keep,
    required String go,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => M3Themed(
        child: AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(keep),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(go),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _disconnect() async {
    Haptics.tap();
    final ok = await _confirm(
      title: ConnectStrings.disconnectTitle,
      body: ConnectStrings.disconnectBody,
      keep: ConnectStrings.disconnectKeep,
      go: ConnectStrings.disconnect,
    );
    if (!ok) return;
    try {
      await _conn.disconnectGithub();
      if (mounted) _toast(ConnectStrings.disconnected);
    } catch (_) {
      if (mounted) _toast(ConnectStrings.failed);
    }
  }

  Future<void> _reconnect() async {
    Haptics.tap();
    final ok = await _confirm(
      title: GithubHubStrings.reconnectTitle,
      body: GithubHubStrings.reconnectBody,
      keep: ConnectStrings.disconnectKeep,
      go: GithubHubStrings.reconnectAction,
    );
    if (!ok) return;
    try {
      await _conn.disconnectGithub();
      await _conn.connectGithub();
    } catch (_) {
      if (mounted) _toast(ConnectStrings.failed);
    }
  }

  Future<void> _refresh() async {
    await _conn.refresh();
    if (_conn.github != null) await _hub.refreshAll();
  }

  void _openRepo(GhRepo r) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => GithubRepoScreen(seed: r)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_conn, _hub]),
      builder: (context, _) {
        final linked = _conn.github != null;
        if (!linked) return _disconnected(context);
        return M3Page(
          title: GithubHubStrings.title,
          controller: _scroll,
          onRefresh: _refresh,
          actions: [
            IconButton(
              tooltip: GithubHubStrings.search,
              icon: const AppIcon(AppIcons.search, size: AppIconSize.lg),
              onPressed: () {
                Haptics.tap();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GithubSearchScreen(),
                  ),
                );
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: GithubHubStrings.tabRepos),
              Tab(text: GithubHubStrings.tabPulls),
              Tab(text: GithubHubStrings.tabIssues),
              Tab(text: GithubHubStrings.tabActivity),
            ],
          ),
          slivers: [
            if (!_searching)
              SliverPadding(
                key: const ValueKey('gh-header'),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.sm,
                  AppSpacing.screenPadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _Header(
                    connection: _conn.github!,
                    me: _hub.me,
                    onOpen: () {
                      final url = _hub.me?.url;
                      ghVisit(
                        context,
                        url == null || url.isEmpty
                            ? ConnectStrings.profileUrl(_conn.github!.login)
                            : url,
                      );
                    },
                    onReconnect: _reconnect,
                    onDisconnect: _disconnect,
                  ),
                ),
              ),
            ..._tab(context),
          ],
        );
      },
    );
  }

  // ---- not connected -----------------------------------------------------

  Widget _disconnected(BuildContext context) {
    final loading = _conn.githubPhase == GithubPhase.loading;
    return M3Page(
      title: GithubHubStrings.title,
      onRefresh: _conn.refresh,
      slivers: [
        M3Body(
          children: [
            if (loading)
              const GhSkeletonCells(count: 3)
            else ...[
              M3Card(
                padding: EdgeInsets.zero,
                child: GithubConnectPanel(
                  paper: Theme.of(context).colorScheme.surfaceContainer,
                ),
              ),
              M3Group(
                title: _WhatYouGet.title,
                children: [
                  for (final row in _WhatYouGet.rows)
                    SettingsTile(icon: row.$1, title: row.$2, summary: row.$3),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ---- connected tabs ------------------------------------------------------

  List<Widget> _tab(BuildContext context) {
    switch (_tabs.index) {
      case 1:
        return _list<GhIssue>(
          _hub.pulls,
          _hub.loadPulls,
          (c, i) => GhItemTile(item: i),
          GithubHubStrings.noPulls,
          GithubHubStrings.noPullsHint,
          GithubHubIcons.pulls,
        );
      case 2:
        return _list<GhIssue>(
          _hub.issues,
          _hub.loadIssues,
          (c, i) => GhItemTile(item: i),
          GithubHubStrings.noIssues,
          GithubHubStrings.noIssuesHint,
          GithubHubIcons.issues,
        );
      case 3:
        final feed = _hub.feed.data;
        if (feed != null) {
          return [
            M3Body(children: [GhActivityFeed(items: feed)]),
          ];
        }
        // The events API failed: the latest commits instead.
        if (_hub.feed.failed &&
            (_hub.activity.ready || _hub.activity.loading)) {
          return _list<GhCommit>(
            _hub.activity,
            _hub.loadActivity,
            (c, i) => GhCommitTile(commit: i),
            GithubHubStrings.noActivity,
            GithubHubStrings.noActivityHint,
            GithubHubIcons.activity,
          );
        }
        return _list<GhActivity>(
          _hub.feed,
          _hub.loadActivity,
          (c, i) => GhActivityTile(item: i),
          GithubHubStrings.noActivity,
          GithubHubStrings.noActivityHint,
          GithubHubIcons.activity,
        );
    }
    return _repos(context);
  }

  List<Widget> _list<T>(
    Loadable<List<T>> state,
    VoidCallback retry,
    Widget Function(BuildContext, T) cell,
    String emptyTitle,
    String emptyHint,
    AppIconData icon,
  ) => [
    M3Body(
      children: [
        GhLoadableList<T>(
          state: state,
          onRetry: retry,
          cell: cell,
          emptyTitle: emptyTitle,
          emptyHint: emptyHint,
          emptyIcon: icon,
        ),
      ],
    ),
  ];

  List<Widget> _repos(BuildContext context) {
    final h = _hub;
    final shown = h.shown;
    final total = h.filtered.length;
    Widget? message;
    if (h.error != null && !h.loaded) {
      message = M3Empty(
        icon: GithubHubIcons.repo,
        title: GithubHubStrings.loadFailed,
        action: FilledButton.tonal(
          onPressed: () => h.load(),
          child: const Text(GithubHubStrings.retry),
        ),
      );
    } else if (!h.loaded) {
      message = const GhSkeletonCells();
    } else if (total == 0) {
      message = h.repos.isEmpty
          ? const M3Empty(
              icon: GithubHubIcons.repo,
              title: GithubHubStrings.noRepos,
              hint: GithubHubStrings.noReposHint,
            )
          : M3Empty(
              icon: AppIcons.search,
              title: GithubHubStrings.noMatches,
              hint: h.query.isEmpty
                  ? null
                  : GithubHubStrings.noMatchesHint(h.query),
              action: FilledButton.tonal(
                onPressed: () {
                  _search.clear();
                  h.setQuery('');
                  h.setFilter(RepoFilter.all);
                },
                child: const Text(GithubHubStrings.clearSearch),
              ),
            );
    }
    return [
      SliverPadding(
        key: const ValueKey('gh-repo-controls'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.lg,
          AppSpacing.screenPadding,
          AppSpacing.sm,
        ),
        sliver: SliverToBoxAdapter(
          child: _RepoControls(
            hub: h,
            search: _search,
            onFocusChange: (focused) {
              if (focused == _searching) return;
              setState(() => _searching = focused);
              if (focused && _scroll.hasClients) {
                _scroll.animateTo(
                  0,
                  duration: GithubHubDurations.focus,
                  curve: Curves.easeOutCubic,
                );
              }
            },
          ),
        ),
      ),
      if (message != null)
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          sliver: SliverToBoxAdapter(child: message),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          sliver: SliverList.builder(
            itemCount: shown.length + (h.hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= shown.length) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: Text(GithubHubStrings.loadingMore)),
                );
              }
              return M3Cell(
                index: i,
                count: shown.length + (h.hasMore ? 1 : 0),
                child: GhRepoTile(
                  repo: shown[i],
                  onTap: () => _openRepo(shown[i]),
                ),
              );
            },
          ),
        ),
    ];
  }
}

abstract final class _WhatYouGet {
  static const title = 'What you get';
  static const rows = <(AppIconData, String, String)>[
    (
      GithubHubIcons.repo,
      'Browse your code',
      'Repositories, branches, files and commit history.',
    ),
    (
      GithubHubIcons.pulls,
      'Follow your work',
      'Pull requests and issues you are involved in.',
    ),
    (
      GithubHubIcons.ask,
      'Ask Sparky',
      'Start a chat about any repository with one tap.',
    ),
  ];
}

/// Avatar, name, login and status, with the account actions.
class _Header extends StatelessWidget {
  const _Header({
    required this.connection,
    required this.me,
    required this.onOpen,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final Connection connection;
  final GhMe? me;
  final VoidCallback onOpen, onReconnect, onDisconnect;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final login = me?.login.isNotEmpty == true ? me!.login : connection.login;
    final name = me?.name.isNotEmpty == true ? me!.name : login;
    final avatar = me?.avatar.isNotEmpty == true
        ? me!.avatar
        : connection.avatarUrl;
    final counts = me == null
        ? null
        : GithubHubStrings.publicPrivate(me!.publicRepos, me!.privateRepos);
    return M3Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhAvatar(avatar, size: GithubHubSizes.avatar),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleLarge,
                    ),
                    Text(
                      ConnectStrings.account(login),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.label.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        const M3Tag(
                          GithubHubStrings.connectedStatus,
                          accent: true,
                        ),
                        if (counts != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              counts,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.caption.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (connection.missingScopes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              GithubHubStrings.fullAccessHint,
              style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onReconnect,
              icon: const AppIcon(
                GithubHubIcons.fullAccess,
                size: AppIconSize.sm,
              ),
              label: const Text(GithubHubStrings.fullAccess),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          // The full-access prompt takes the filled slot when it shows.
          if (connection.missingScopes.isEmpty)
            FilledButton.icon(
              onPressed: onOpen,
              icon: const AppIcon(AppIcons.openExternal, size: AppIconSize.sm),
              label: const Text(GithubHubStrings.openOnGithub),
            )
          else
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const AppIcon(AppIcons.openExternal, size: AppIconSize.sm),
              label: const Text(GithubHubStrings.openOnGithub),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReconnect,
                  icon: const AppIcon(
                    GithubHubIcons.reconnect,
                    size: AppIconSize.sm,
                  ),
                  label: const Text(GithubHubStrings.reconnect),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.accent,
                  ),
                  onPressed: onDisconnect,
                  child: const Text(GithubHubStrings.disconnect),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Search, sort and filter of the repository list.
class _RepoControls extends StatelessWidget {
  const _RepoControls({
    required this.hub,
    required this.search,
    this.onFocusChange,
  });

  final GithubHubController hub;
  final TextEditingController search;
  final ValueChanged<bool>? onFocusChange;

  static String _sortLabel(RepoSort s) => switch (s) {
    RepoSort.pushed => GithubHubStrings.sortPushed,
    RepoSort.name => GithubHubStrings.sortName,
    RepoSort.stars => GithubHubStrings.sortStars,
  };

  static String _filterLabel(RepoFilter f) => switch (f) {
    RepoFilter.all => GithubHubStrings.filterAll,
    RepoFilter.public => GithubHubStrings.filterPublic,
    RepoFilter.private => GithubHubStrings.filterPrivate,
    RepoFilter.forks => GithubHubStrings.filterForks,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GhPillSearch(
          hint: GithubHubStrings.filterRepos,
          controller: search,
          onChanged: hub.setQuery,
          onFocusChange: onFocusChange,
        ),
        const SizedBox(height: AppSpacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              PopupMenuButton<RepoSort>(
                tooltip: GithubHubStrings.sortLabel,
                initialValue: hub.sort,
                onSelected: (s) {
                  Haptics.tap();
                  hub.setSort(s);
                },
                itemBuilder: (_) => [
                  for (final s in RepoSort.values)
                    PopupMenuItem(value: s, child: Text(_sortLabel(s))),
                ],
                child: Chip(
                  avatar: AppIcon(
                    GithubHubIcons.sort,
                    size: AppIconSize.sm,
                    color: scheme.onSurface,
                  ),
                  label: Text(_sortLabel(hub.sort)),
                ),
              ),
              for (final f in RepoFilter.values) ...[
                const SizedBox(width: AppSpacing.sm),
                ChoiceChip(
                  label: Text(_filterLabel(f)),
                  selected: hub.filter == f,
                  showCheckmark: false,
                  onSelected: (_) {
                    Haptics.tap();
                    hub.setFilter(f);
                  },
                ),
              ],
            ],
          ),
        ),
        if (hub.loaded) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            GithubHubStrings.repoCount(hub.filtered.length, hub.repos.length),
            style: context.text.caption.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
