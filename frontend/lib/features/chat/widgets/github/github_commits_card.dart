import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/chat_api.dart';
import '../../../../data/github_api.dart';
import '../rich/playful_common.dart';
import '../rich/rich_frame.dart';
import 'github_branch_picker.dart';
import 'github_common.dart';

/// ```github-commits block (`owner/repo[@branch][:path]`): commit timeline;
/// tap a commit to see its changed files and diffs.
class GithubCommitsCard extends StatelessWidget {
  const GithubCommitsCard({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final lines = ghLines(source);
    final ref = lines.isEmpty ? null : parseGhRef(lines.first.split(' ').first);
    if (ref == null) {
      return GhBadBlock(
        title: GithubStrings.commits,
        source: source,
        hint: GithubStrings.badSpec,
      );
    }
    final detail = [
      ref.full,
      if (ref.ref != null) '@${ref.ref}',
      if (ref.path.isNotEmpty) ':${ref.path}',
    ].join();
    final webUrl = ref.ref == null
        ? '${ref.url}/commits'
        : '${ref.url}/commits/${ref.ref}${ref.path.isEmpty ? '' : '/${ref.path}'}';
    return RichCard(
      title: GithubStrings.titled(GithubStrings.commits, detail.toUpperCase()),
      leading: const Octicon(GithubOcticons.commit),
      actions: [
        ghVisitAction(context, webUrl),
        RichAction.copy(text: webUrl),
      ],
      child: GhCommitsPaged(repo: ref),
    );
  }
}

/// Loads one page of commits (tests replace the API).
typedef CommitPageLoader =
    Future<GhCommitPage> Function(String? branch, String q, String? after);

/// The whole history of a branch, page by page as it scrolls, with a branch
/// picker and a message / author / sha filter (GitHub commit search on the
/// default branch, else over the commits loaded so far).
class GhCommitsPaged extends StatefulWidget {
  const GhCommitsPaged({
    super.key,
    required this.repo,
    this.loader,
    this.branchLoader,
  });

  final GhRef repo;
  final CommitPageLoader? loader;
  final BranchLoader? branchLoader;

  @override
  State<GhCommitsPaged> createState() => _GhCommitsPagedState();
}

class _GhCommitsPagedState extends State<GhCommitsPaged> {
  final _items = <GhCommit>[];
  final _seen = <String>{};
  final _open = <String>{};
  late String? _branch = widget.repo.ref;
  String _filter = '';
  String? _next;
  int? _total;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  Object? _moreError;
  int _gen = 0;
  Timer? _debounce;
  final _scroll = ScrollController();

  /// Server-side search covers the default branch only.
  bool get _serverFilter => _branch == null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeMore);
    _reload();
  }

  @override
  void dispose() {
    _gen++;
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<GhCommitPage> _fetch(String? after) {
    final q = _serverFilter ? _filter : '';
    final custom = widget.loader;
    if (custom != null) return custom(_branch, q, after);
    final r = widget.repo;
    return GithubApi.instance.commitPage(
      r.owner,
      r.repo,
      sha: _branch,
      path: r.path.isEmpty ? null : r.path,
      q: q,
      after: after,
    );
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _fetch(null);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items.clear();
        _seen.clear();
        _open.clear();
        _moreError = null;
        _add(page);
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _checkFill();
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _add(GhCommitPage page) {
    for (final c in page.items) {
      if (_seen.add(c.sha)) _items.add(c);
    }
    _next = page.nextCursor;
    _total = page.totalCount ?? _total;
  }

  void _checkFill() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _maybeMore();
  });

  void _maybeMore() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < GithubPagingSizes.prefetchExtent) {
      _more();
    }
  }

  Future<void> _more() async {
    final cursor = _next;
    if (cursor == null || _loading || _loadingMore || _moreError != null) {
      return;
    }
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(cursor);
      if (!mounted || gen != _gen) return;
      setState(() {
        _loadingMore = false;
        _add(page);
      });
      _checkFill();
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loadingMore = false;
        _moreError = e;
      });
    }
  }

  void _onFilter(String text) {
    _debounce?.cancel();
    _debounce = Timer(AppDurations.searchDebounce, () {
      if (!mounted) return;
      final v = text.trim();
      if (v == _filter) return;
      setState(() => _filter = v);
      if (_serverFilter) _reload();
    });
  }

  Future<void> _pickBranch() async {
    final picked = await showBranchPicker(
      context,
      repo: widget.repo,
      selected: {?_branch},
      multi: false,
      loader: widget.branchLoader,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _branch = picked.first);
    _reload();
  }

  /// Commits shown: everything, or the local filter over loaded pages.
  List<GhCommit> get _shown {
    if (_serverFilter || _filter.isEmpty) return _items;
    final q = _filter.toLowerCase();
    return [
      for (final c in _items)
        if (c.message.toLowerCase().contains(q) ||
            c.who.toLowerCase().contains(q) ||
            c.authorName.toLowerCase().contains(q) ||
            c.sha.startsWith(q))
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final shown = _shown;
    final local = !_serverFilter && _filter.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GithubSizes.pad,
            GithubSizes.pad,
            GithubSizes.pad,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              GhFilterChip(
                label: _branch ?? GithubBranchStrings.pick,
                on: _branch != null,
                picker: true,
                onTap: _pickBranch,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: GhSearchField(
                  hint: GithubPagingStrings.commitFilterHint,
                  onChanged: _onFilter,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GithubSizes.pad),
          child: Text(
            [
              GithubPagingStrings.commitsOf(
                shown.length,
                local ? null : _total,
              ),
              if (local) GithubPagingStrings.filteredLocally,
            ].join(' · '),
            style: t.caption,
          ),
        ),
        SizedBox(
          height: GithubPagingSizes.commitListHeight,
          child: _list(context, shown),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, List<GhCommit> shown) {
    final e = _error;
    if (e != null) {
      return Align(
        alignment: Alignment.topCenter,
        child: GhError(
          message: e is ApiException ? e.message : GithubStrings.loadFailed,
          onRetry: _reload,
        ),
      );
    }
    if (_loading && _items.isEmpty) return const GhSkeleton(rows: 5);
    if (shown.isEmpty && _next == null) {
      return Padding(
        padding: const EdgeInsets.all(GithubSizes.pad),
        child: Text(GithubStrings.noResults, style: context.text.bodySmall),
      );
    }
    final tail = _next != null;
    return AnimatedOpacity(
      duration: GithubDurations.expand,
      opacity: _loading ? GithubGraphColors.mergeTextAlpha : 1,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(GithubSizes.pad),
        itemCount: shown.length + (tail ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= shown.length) {
            final err = _moreError;
            if (err != null) {
              return GhError(
                message: err is ApiException
                    ? err.message
                    : GithubStrings.loadFailed,
                onRetry: () {
                  setState(() => _moreError = null);
                  _more();
                },
              );
            }
            return const GhLoadingRow(label: GithubPagingStrings.loadingMore);
          }
          final c = shown[i];
          return _CommitRow(
            key: ValueKey(c.sha),
            repo: widget.repo,
            commit: c,
            first: i == 0,
            last: i == shown.length - 1 && !tail,
            open: _open.contains(c.sha),
            onTap: () => setState(() {
              if (!_open.remove(c.sha)) _open.add(c.sha);
            }),
          );
        },
      ),
    );
  }
}

/// Vertical rail of commits; each expands into its files (loaded lazily).
class GhCommitTimeline extends StatefulWidget {
  const GhCommitTimeline({
    super.key,
    required this.repo,
    required this.commits,
    this.padded = true,
  });

  final GhRef repo;
  final List<GhCommit> commits;

  /// False when the parent already pads (compare card).
  final bool padded;

  @override
  State<GhCommitTimeline> createState() => _GhCommitTimelineState();
}

class _GhCommitTimelineState extends State<GhCommitTimeline> {
  final _open = <int>{};
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final list = widget.commits;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(GithubSizes.pad),
        child: Text(GithubStrings.noResults, style: t.bodySmall),
      );
    }
    final shown = _all
        ? list.length
        : list.length.clamp(0, GithubLimits.initialVisible);
    return Padding(
      padding: EdgeInsets.all(widget.padded ? GithubSizes.pad : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown; i++)
            _CommitRow(
              repo: widget.repo,
              commit: list[i],
              first: i == 0,
              last: i == shown - 1,
              open: _open.contains(i),
              onTap: () => setState(() {
                if (!_open.remove(i)) _open.add(i);
              }),
            ),
          if (list.length > GithubLimits.initialVisible)
            GhTap(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: [
                    AppIcon(
                      _all ? GithubIcons.collapse : GithubIcons.expand,
                      size: AppIconSize.sm,
                      color: p.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _all ? GithubStrings.showLess : GithubStrings.loadMore,
                      style: t.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({
    super.key,
    required this.repo,
    required this.commit,
    required this.first,
    required this.last,
    required this.open,
    required this.onTap,
  });

  final GhRef repo;
  final GhCommit commit;
  final bool first, last, open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final c = commit;
    const center = GithubSizes.avatar / 2;
    final dot = Container(
      width: GithubSizes.avatar,
      height: GithubSizes.avatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.codeBackground,
        border: Border.all(
          color: open ? p.accent : p.borderStrong,
          width: AppBorder.thick,
        ),
      ),
      child: GhAvatar(c.author?.avatar ?? '', size: GithubSizes.avatarSmall),
    );
    return Stack(
      children: [
        if (!(first && last && !open))
          Positioned(
            left: center - AppBorder.thin / 2,
            top: first ? center : 0,
            bottom: last && !open ? null : 0,
            height: last && !open ? center : null,
            child: Container(width: AppBorder.thin, color: p.borderStrong),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            dot,
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: GithubSizes.pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GhTap(
                      onTap: onTap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.message,
                            maxLines: open ? null : 2,
                            overflow: open ? null : TextOverflow.ellipsis,
                            style: t.bodySmall.copyWith(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              GhChip(c.shortSha),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '${c.who} · ${GithubStrings.ago(c.date)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.caption,
                                ),
                              ),
                              if (c.additions != null && c.deletions != null)
                                GhDelta(add: c.additions!, del: c.deletions!),
                              const SizedBox(width: AppSpacing.xs),
                              AppIcon(
                                open
                                    ? GithubIcons.collapse
                                    : GithubIcons.expand,
                                size: AppIconSize.sm,
                                color: p.textTertiary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: GithubDurations.expand,
                      alignment: Alignment.topCenter,
                      child: open
                          ? GhCommitDetail(repo: repo, sha: c.sha)
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Body of the commit and its changed files (loaded on demand); shared with
/// the git graph.
class GhCommitDetail extends StatelessWidget {
  const GhCommitDetail({super.key, required this.repo, required this.sha});

  final GhRef repo;
  final String sha;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return GhFuture<GhCommit>(
      load: () => GithubApi.instance.commit(repo.owner, repo.repo, sha),
      builder: (context, c) {
        final body = c.body
            .split('\n')
            .skip(c.body.startsWith(c.message) ? 1 : 0)
            .join('\n')
            .trim();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (body.isNotEmpty)
                Text(
                  body,
                  maxLines: GithubSizes.bodyLines,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
              GhSection(
                '${GithubStrings.files} ${c.files.length}',
                trailing: GhDelta(add: c.additions ?? 0, del: c.deletions ?? 0),
              ),
              GhFilesList(
                files: c.files,
                truncated: c.filesTruncated,
                moreUrl: c.url,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  PlayfulButton(
                    label: GithubStrings.visit,
                    icon: GithubIcons.visit,
                    onTap: () => ghVisit(context, c.url),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PlayfulButton(
                    label: GithubStrings.copy,
                    icon: GithubIcons.copy,
                    onTap: () => ghCopy(context, c.sha),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
