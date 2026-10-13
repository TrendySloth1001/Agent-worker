import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/error_copy.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../data/chat_api.dart';
import '../../../../data/github_api.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';
import 'github_connect_card.dart';

/// ```github-my-repos block (`all`, `private` or `public`): the repositories
/// of the account behind the server's GitHub token, private ones marked with
/// a lock.
class GithubMyReposCard extends StatelessWidget {
  const GithubMyReposCard({super.key, required this.source});

  final String source;

  String get _visibility {
    final s = source.toLowerCase();
    if (RegExp(r'\bprivate\b').hasMatch(s)) return 'private';
    if (RegExp(r'\bpublic\b').hasMatch(s)) return 'public';
    return GithubStrings.stateAll;
  }

  @override
  Widget build(BuildContext context) {
    final visibility = _visibility;
    return RichCard(
      title: GithubReviewStrings.visibilityTitle(visibility),
      leading: const Octicon(GithubOcticons.repo),
      child: GhMyRepos(key: ValueKey(visibility), visibility: visibility),
    );
  }
}

enum _Sort { recent, stars, name }

/// Every repository of the user: instant search (local first, then the
/// server's typo-tolerant ranking), owner / language / private / archived /
/// fork filters, sort, and a lazily built list with a count.
class GhMyRepos extends StatefulWidget {
  const GhMyRepos({
    super.key,
    this.visibility = GithubStrings.stateAll,
    this.loader,
    this.searcher,
  });

  final String visibility;

  /// Replace the API (tests).
  final Future<(GhMe, List<GhRepo>)> Function(bool refresh)? loader;
  final Future<GhRepoSearch> Function(String q)? searcher;

  @override
  State<GhMyRepos> createState() => _GhMyReposState();
}

class _GhMyReposState extends State<GhMyRepos> {
  GhMe? _me;
  List<GhRepo> _all = const [];
  Object? _error;
  bool _loading = true;
  int _gen = 0;

  String _q = '';

  /// Server ranking for [_q]: full names in order, and the tokens that hit.
  List<String>? _ranked;
  List<String> _tokens = const [];
  int _searchGen = 0;
  Timer? _debounce;

  _Sort _sort = _Sort.recent;
  String? _owner;
  String? _language;
  late bool _private = widget.visibility == 'private';
  late final bool _public = widget.visibility == 'public';
  bool _archived = false;
  bool _forks = false;

  @override
  void initState() {
    super.initState();
    _load(false);
  }

  @override
  void dispose() {
    _gen++;
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load(bool refresh) async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final custom = widget.loader;
      final (me, repos) = custom != null
          ? await custom(refresh)
          : await (() async {
              final api = GithubApi.instance;
              final r = await Future.wait([
                api.me(),
                api.myRepos(refresh: refresh),
              ]);
              return (r[0] as GhMe, r[1] as List<GhRepo>);
            })();
      if (!mounted || gen != _gen) return;
      setState(() {
        _me = me;
        _all = repos;
        _loading = false;
      });
      if (_q.isNotEmpty) _search(_q);
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onQuery(String text) {
    final q = text.trim();
    setState(() {
      _q = q;
      _ranked = null;
      _tokens = q.isEmpty ? const [] : q.toLowerCase().split(RegExp(r'\s+'));
    });
    _debounce?.cancel();
    if (q.isEmpty) return;
    _debounce = Timer(AppDurations.searchDebounce, () => _search(q));
  }

  Future<void> _search(String q) async {
    final gen = ++_searchGen;
    try {
      final res =
          await (widget.searcher?.call(q) ??
              GithubApi.instance.searchMyRepos(q));
      if (!mounted || gen != _searchGen || q != _q) return;
      setState(() {
        _ranked = [for (final r in res.items) r.fullName];
        _tokens = res.tokens.isEmpty ? _tokens : res.tokens;
      });
    } catch (_) {
      // Keep the instant local matches.
    }
  }

  /// Local match while the server ranks: every word in name or description.
  bool _localMatch(GhRepo r) {
    final hay = '${r.fullName} ${r.description} ${r.topics.join(' ')}'
        .toLowerCase()
        .replaceAll(RegExp(r'[-_.]'), ' ');
    final compact = hay.replaceAll(' ', '');
    return _q
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every((w) => hay.contains(w) || compact.contains(w));
  }

  bool _passes(GhRepo r) =>
      (!_private || r.isPrivate) &&
      (!_public || !r.isPrivate) &&
      (!_archived || r.archived) &&
      (!_forks || r.fork) &&
      (_owner == null || r.owner == _owner) &&
      (_language == null || r.language == _language);

  List<GhRepo> get _shown {
    final ranked = _ranked;
    if (_q.isNotEmpty && ranked != null) {
      final byName = {for (final r in _all) r.fullName: r};
      return ranked.map((n) => byName[n]).nonNulls.where(_passes).toList();
    }
    final list = [
      for (final r in _all)
        if (_passes(r) && (_q.isEmpty || _localMatch(r))) r,
    ];
    if (_q.isNotEmpty) return list;
    int byDate(GhRepo a, GhRepo b) =>
        (b.pushedAt ?? DateTime(0)).compareTo(a.pushedAt ?? DateTime(0));
    switch (_sort) {
      case _Sort.recent:
        list.sort(byDate);
      case _Sort.stars:
        list.sort(
          (a, b) => b.stars - a.stars != 0 ? b.stars - a.stars : byDate(a, b),
        );
      case _Sort.name:
        list.sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
    }
    return list;
  }

  String _sortLabel(_Sort s) => switch (s) {
    _Sort.recent => GithubRepoFilterStrings.sortRecent,
    _Sort.stars => GithubRepoFilterStrings.sortStars,
    _Sort.name => GithubRepoFilterStrings.sortName,
  };

  Future<void> _pickSort() async {
    final v = await ghPickOne(
      context,
      title: GithubRepoFilterStrings.sortRecent,
      options: [for (final s in _Sort.values) _sortLabel(s)],
      selected: _sortLabel(_sort),
    );
    if (v == null || !mounted) return;
    setState(() => _sort = _Sort.values.firstWhere((s) => _sortLabel(s) == v));
  }

  Future<void> _pickOwner() async {
    final owners = {for (final r in _all) r.owner}.toList()..sort();
    final v = await ghPickOne(
      context,
      title: GithubRepoFilterStrings.owner,
      options: [GithubRepoFilterStrings.any, ...owners],
      selected: _owner ?? GithubRepoFilterStrings.any,
    );
    if (v == null || !mounted) return;
    setState(() => _owner = v == GithubRepoFilterStrings.any ? null : v);
  }

  Future<void> _pickLanguage() async {
    final langs = {for (final r in _all) ?r.language}.toList()..sort();
    final v = await ghPickOne(
      context,
      title: GithubRepoFilterStrings.language,
      options: [GithubRepoFilterStrings.any, ...langs],
      selected: _language ?? GithubRepoFilterStrings.any,
    );
    if (v == null || !mounted) return;
    setState(() => _language = v == GithubRepoFilterStrings.any ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final e = _error;
    if (e != null) {
      if (e is ApiException && e.status == 409) {
        return GithubConnectPanel(paper: context.palette.codeBackground);
      }
      return GhError(
        message: e is ApiException
            ? friendlyException(e)
            : GithubStrings.loadFailed,
        onRetry: () => _load(false),
      );
    }
    final me = _me;
    if (me == null) return const GhSkeleton(rows: 5);
    final t = context.text;
    final shown = _shown;
    return Padding(
      padding: const EdgeInsets.all(GithubSizes.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GhTap(
            onTap: () => ghVisit(context, me.url),
            child: _Account(me: me),
          ),
          const SizedBox(height: AppSpacing.sm),
          GhSearchField(
            hint: GithubRepoFilterStrings.searchHint,
            onChanged: _onQuery,
          ),
          SizedBox(
            height: GithubPagingSizes.filterBarHeight,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                for (final chip in [
                  GhFilterChip(
                    label: _q.isEmpty
                        ? _sortLabel(_sort)
                        : GithubRepoFilterStrings.sortBest,
                    on: false,
                    picker: true,
                    onTap: _pickSort,
                  ),
                  GhFilterChip(
                    label: _owner ?? GithubRepoFilterStrings.owner,
                    on: _owner != null,
                    picker: true,
                    onTap: _pickOwner,
                  ),
                  GhFilterChip(
                    label: _language ?? GithubRepoFilterStrings.language,
                    on: _language != null,
                    picker: true,
                    onTap: _pickLanguage,
                  ),
                  GhFilterChip(
                    label: GithubRepoFilterStrings.privateOnly,
                    on: _private,
                    onTap: () => setState(() => _private = !_private),
                  ),
                  GhFilterChip(
                    label: GithubRepoFilterStrings.archived,
                    on: _archived,
                    onTap: () => setState(() => _archived = !_archived),
                  ),
                  GhFilterChip(
                    label: GithubRepoFilterStrings.forks,
                    on: _forks,
                    onTap: () => setState(() => _forks = !_forks),
                  ),
                  GhFilterChip(
                    label: GithubRepoFilterStrings.refresh,
                    on: false,
                    onTap: _loading ? () {} : () => _load(true),
                  ),
                ]) ...[chip, const SizedBox(width: AppSpacing.xs)],
              ],
            ),
          ),
          Text(
            GithubPagingStrings.reposOf(shown.length, _all.length),
            style: t.caption,
          ),
          const GhDivider(),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _all.isEmpty
                    ? GithubReviewStrings.empty
                    : GithubStrings.noResults,
                style: t.bodySmall,
              ),
            )
          else
            AnimatedOpacity(
              duration: GithubDurations.expand,
              opacity: _loading ? GithubGraphColors.mergeTextAlpha : 1,
              child: SizedBox(
                height: GithubPagingSizes.repoListHeight,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const GhDivider(),
                  itemBuilder: (context, i) =>
                      _RepoRow(repo: shown[i], tokens: _tokens),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Account extends StatelessWidget {
  const _Account({required this.me});

  final GhMe me;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Row(
      children: [
        GhAvatar(me.avatar),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                GithubReviewStrings.byAuthor(me.login),
                style: t.bodySmall.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  '${me.publicRepos} ${GithubStrings.typeRepos}',
                  if (me.privateRepos != null)
                    '${me.privateRepos} ${GithubReviewStrings.privateBadge.toLowerCase()}',
                ].join(' · '),
                style: t.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo, this.tokens = const []});

  final GhRepo repo;

  /// Search words to highlight.
  final List<String> tokens;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final r = repo;
    final meta = [
      ?r.language,
      if (r.archived) GithubStrings.archived,
      if (r.fork) GithubRepoFilterStrings.forkBadge,
      GithubStrings.ago(r.pushedAt),
    ].where((s) => s.isNotEmpty).join(' · ');
    return GhTap(
      onTap: () => ghVisit(context, r.url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GithubSizes.rowGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Octicon(
                r.isPrivate ? GithubReviewOcticons.lock : GithubOcticons.repo,
                color: r.isPrivate ? p.textPrimary : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: GhHighlight(
                          r.fullName,
                          tokens: tokens,
                          maxLines: 1,
                          style: t.bodySmall.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (r.isPrivate) ...[
                        const SizedBox(width: AppSpacing.xs),
                        GhChip(
                          GithubReviewStrings.privateBadge,
                          icon: GithubReviewOcticons.lock,
                        ),
                      ],
                    ],
                  ),
                  if (r.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    GhHighlight(
                      r.description,
                      tokens: tokens,
                      maxLines: 2,
                      style: t.bodySmall,
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(meta, style: t.caption),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GhStat(GithubOcticons.star, GithubStrings.countOf(r.stars)),
          ],
        ),
      ),
    );
  }
}
