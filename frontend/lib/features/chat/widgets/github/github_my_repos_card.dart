import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/github_api.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';

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
    final api = GithubApi.instance;
    return RichCard(
      title: GithubReviewStrings.visibilityTitle(visibility),
      leading: const Octicon(GithubOcticons.repo),
      child: GhFuture<(GhMe, List<GhRepo>)>(
        key: ValueKey(visibility),
        skeletonRows: 5,
        load: () async {
          final r = await Future.wait([
            api.me(),
            api.myRepos(visibility: visibility),
          ]);
          return (r[0] as GhMe, r[1] as List<GhRepo>);
        },
        builder: (context, data) {
          final (me, repos) = data;
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
                const GhDivider(),
                _RepoList(repos: repos),
              ],
            ),
          );
        },
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

class _RepoList extends StatefulWidget {
  const _RepoList({required this.repos});

  final List<GhRepo> repos;

  @override
  State<_RepoList> createState() => _RepoListState();
}

class _RepoListState extends State<_RepoList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final repos = widget.repos;
    if (repos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(GithubReviewStrings.empty, style: t.bodySmall),
      );
    }
    final shown = _all
        ? repos.length
        : repos.length.clamp(0, GithubLimits.initialVisible);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown; i++) ...[
          if (i > 0) const GhDivider(),
          _RepoRow(repo: repos[i]),
        ],
        if (repos.length > GithubLimits.initialVisible)
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
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo});

  final GhRepo repo;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final r = repo;
    final meta = [
      ?r.language,
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
                        child: Text(
                          r.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                    Text(
                      r.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
