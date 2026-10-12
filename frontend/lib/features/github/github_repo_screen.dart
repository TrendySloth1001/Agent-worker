import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/apps.dart';
import '../../core/constants/widget_github.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/chat_api.dart';
import '../../data/github_api.dart';
import 'gh_actions.dart';
import '../chat/widgets/github/github_branch_picker.dart';
import '../chat/widgets/github/github_commits_card.dart';
import '../chat/widgets/github/github_common.dart';
import '../chat/widgets/github/github_graph_card.dart';
import '../chat/widgets/github/github_repo_card.dart';
import '../chat/widgets/github/github_tree_card.dart';
import '../chat/widgets/markdown/app_markdown.dart';
import 'github_controller.dart';
import 'widgets/gh_rows.dart';

/// One repository: overview and README, files, commits, the git graph, and
/// its open pull requests and issues. "Ask Sparky" starts a chat about it.
class GithubRepoScreen extends StatefulWidget {
  const GithubRepoScreen({super.key, required this.seed});

  /// What is already known (from a list); the full detail loads on top.
  final GhRepo seed;

  @override
  State<GithubRepoScreen> createState() => _GithubRepoScreenState();
}

class _GithubRepoScreenState extends State<GithubRepoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });

  GhRepo? _detail;
  Object? _error;
  bool _loading = true;

  final _pulls = Loadable<List<GhIssue>>();
  final _issues = Loadable<List<GhIssue>>();

  /// Branch shown in the file browser; null = the default branch.
  String? _branch;

  /// Bumped by pull-to-refresh so every embedded list reloads.
  int _epoch = 0;

  GhRepo get _repo => _detail ?? widget.seed;
  GhRef get _ref => GhRef(_repo.owner, _repo.name);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await GithubApi.instance.repo(
        widget.seed.owner,
        widget.seed.name,
      );
      if (!mounted) return;
      setState(() {
        _detail = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _fill(
    Loadable<List<GhIssue>> slot,
    Future<List<GhIssue>> Function() fetch,
  ) async {
    setState(() {
      slot.loading = true;
      slot.error = null;
    });
    try {
      final data = await fetch();
      if (mounted) setState(() => slot.data = data);
    } catch (e) {
      if (mounted) setState(() => slot.error = e);
    }
    if (mounted) setState(() => slot.loading = false);
  }

  Future<void> _loadPulls() => _fill(
    _pulls,
    () => GithubApi.instance.pulls(_repo.owner, _repo.name, 'open'),
  );

  Future<void> _loadIssues() => _fill(
    _issues,
    () => GithubApi.instance.issues(_repo.owner, _repo.name, 'open'),
  );

  Future<void> _refresh() async {
    setState(() => _epoch++);
    _pulls.data = null;
    _issues.data = null;
    await _load();
    if (_tabs.index == 4) await _loadPulls();
    if (_tabs.index == 5) await _loadIssues();
  }

  void _ask() => askSparky(context, GithubRepoStrings.prompt(_repo.fullName));

  Future<void> _pickBranch() async {
    final picked = await showBranchPicker(
      context,
      repo: _ref,
      selected: {?_branch},
      multi: false,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _branch = picked.first);
  }

  @override
  Widget build(BuildContext context) {
    final r = _repo;
    return M3Page(
      title: r.name,
      onRefresh: _refresh,
      actions: [
        IconButton(
          tooltip: GithubRepoStrings.share,
          icon: const AppIcon(AppIcons.openExternal, size: AppIconSize.lg),
          onPressed: () => ghVisit(context, r.url.isEmpty ? _ref.url : r.url),
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        onTap: (i) {
          if (i == 4 && !_pulls.ready && !_pulls.loading) _loadPulls();
          if (i == 5 && !_issues.ready && !_issues.loading) _loadIssues();
        },
        tabs: const [
          Tab(text: GithubRepoStrings.tabOverview),
          Tab(text: GithubRepoStrings.tabFiles),
          Tab(text: GithubRepoStrings.tabCommits),
          Tab(text: GithubRepoStrings.tabGraph),
          Tab(text: GithubRepoStrings.tabPulls),
          Tab(text: GithubRepoStrings.tabIssues),
        ],
      ),
      slivers: [
        M3Body(
          children: [
            const SizedBox(height: AppSpacing.sm),
            _RepoHeader(repo: r, onAsk: _ask),
            const SizedBox(height: AppSpacing.lg),
            ..._content(context),
          ],
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context) {
    final key = ValueKey('$_epoch-${_tabs.index}-$_branch');
    switch (_tabs.index) {
      case 1:
        return [
          Align(
            alignment: Alignment.centerLeft,
            child: GhFilterChip(
              label: _branch ?? _repo.defaultBranch,
              on: _branch != null,
              picker: true,
              onTap: _pickBranch,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GithubTreeCard(
            key: key,
            source: _branch == null ? _ref.full : '${_ref.full}@$_branch',
          ),
        ];
      case 2:
        return [
          M3Card(
            padding: EdgeInsets.zero,
            child: GhCommitsPaged(key: key, repo: _ref),
          ),
        ];
      case 3:
        return [
          M3Card(
            padding: EdgeInsets.zero,
            child: GhGraphView(
              key: key,
              spec: GhGraphSpec(_ref),
              height: GithubGraphSizes.cardHeight,
            ),
          ),
        ];
      case 4:
        return [
          GhLoadableList<GhIssue>(
            state: _pulls,
            onRetry: _loadPulls,
            cell: (c, i) => GhItemTile(item: i, showRepo: false),
            emptyTitle: GithubRepoStrings.noPulls,
            emptyHint: GithubRepoStrings.noPullsHint,
            emptyIcon: GithubHubIcons.pulls,
          ),
        ];
      case 5:
        return [
          GhLoadableList<GhIssue>(
            state: _issues,
            onRetry: _loadIssues,
            cell: (c, i) => GhItemTile(item: i, showRepo: false),
            emptyTitle: GithubRepoStrings.noIssues,
            emptyHint: GithubRepoStrings.noIssuesHint,
            emptyIcon: GithubHubIcons.issues,
          ),
        ];
    }
    return _overview(context);
  }

  List<Widget> _overview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = _detail;
    if (_loading && detail == null) return const [GhSkeletonCells(count: 3)];
    if (detail == null) {
      final e = _error;
      return [
        M3Empty(
          icon: GithubHubIcons.repo,
          title: GithubHubStrings.loadFailed,
          hint: e is ApiException ? e.message : null,
          action: FilledButton.tonal(
            onPressed: _load,
            child: const Text(GithubHubStrings.retry),
          ),
        ),
      ];
    }
    return [
      M3Card(child: GhRepoBody(repo: detail, compact: true)),
      const SizedBox(height: AppSpacing.lg),
      M3Group(
        title: GithubRepoStrings.readme,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: detail.readme.trim().isEmpty
                ? Text(
                    GithubRepoStrings.noReadme,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : AppMarkdown(
                    data: detail.readme,
                    citations: const [],
                    streaming: false,
                  ),
          ),
        ],
      ),
    ];
  }
}

/// Avatar, full name, description and the Ask Sparky action.
class _RepoHeader extends StatelessWidget {
  const _RepoHeader({required this.repo, required this.onAsk});

  final GhRepo repo;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final r = repo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GhAvatar(r.avatar, size: GithubHubSizes.rowAvatar),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                r.fullName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.titleMedium!.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (r.isPrivate) const M3Tag(GithubHubStrings.privateBadge),
            if (!r.isPrivate && r.archived)
              const M3Tag(GithubHubStrings.archivedBadge),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: onAsk,
          icon: const AppIcon(GithubHubIcons.ask, size: AppIconSize.md),
          label: const Text(GithubRepoStrings.askSparky),
        ),
      ],
    );
  }
}
