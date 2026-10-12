import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/apps.dart';
import '../../../core/constants/widget_github.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/github_api.dart';
import '../../chat/widgets/github/github_common.dart';
import '../gh_actions.dart';
import '../github_controller.dart';

export 'gh_search_pill.dart';

/// A repository as one grouped cell: owner avatar, name, description and the
/// facts that matter (language, stars, last push).
class GhRepoTile extends StatelessWidget {
  const GhRepoTile({super.key, required this.repo, required this.onTap});

  final GhRepo repo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final r = repo;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GhAvatar(r.avatar, size: GithubHubSizes.rowAvatar),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${r.owner}/',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              TextSpan(text: r.name),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium,
                        ),
                      ),
                      if (r.isPrivate) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const M3Tag(GithubHubStrings.privateBadge),
                      ] else if (r.fork) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const M3Tag(GithubHubStrings.forkBadge),
                      ] else if (r.archived) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const M3Tag(GithubHubStrings.archivedBadge),
                      ],
                    ],
                  ),
                  if (r.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      r.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (r.language != null) _Lang(r.language!),
                      GhStat(
                        GithubOcticons.star,
                        GithubStrings.countOf(r.stars),
                      ),
                      if (r.pushedAt != null)
                        GhStat(
                          GithubOcticons.commit,
                          GithubStrings.ago(r.pushedAt),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lang extends StatelessWidget {
  const _Lang(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: GithubSizes.labelDot,
          height: GithubSizes.labelDot,
          decoration: BoxDecoration(
            color: p.textSecondary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          name,
          style: context.text.caption.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

/// A pull request or issue as one grouped cell.
class GhItemTile extends StatelessWidget {
  const GhItemTile({super.key, required this.item, this.showRepo = true});

  final GhIssue item;

  /// The repository line; off inside a repository's own list.
  final bool showRepo;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = context.palette;
    final i = item;
    final merged = i.state == GithubStrings.stateMerged;
    final open =
        i.state == GithubStrings.stateOpen ||
        i.state == GithubStrings.stateDraft;
    final icon = i.isPr
        ? (merged
              ? GithubOcticons.merged
              : i.state == GithubStrings.stateDraft
              ? GithubOcticons.prDraft
              : open
              ? GithubOcticons.pr
              : GithubOcticons.prClosed)
        : (open ? GithubOcticons.issueOpen : GithubOcticons.issueClosed);
    final tint = merged
        ? p.accent
        : open
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    final where = [
      if (showRepo && i.repo.isNotEmpty) i.repo,
      GithubStrings.issueNumber(i.number),
      if (i.updatedAt != null) GithubStrings.ago(i.updatedAt),
    ].join('  ·  ');
    return InkWell(
      onTap: () => openGhItem(
        context,
        repo: i.repoFullName,
        number: i.number,
        isPr: i.isPr,
        title: i.title,
        url: i.url,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Octicon(icon, size: GithubHubSizes.rowIcon, color: tint),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (i.labels.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final l in i.labels.take(3))
                          GhChip(l.name, dot: ghLabelColor(l.color)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if ((i.comments ?? 0) > 0) ...[
              const SizedBox(width: AppSpacing.md),
              GhStat(GithubOcticons.comment, '${i.comments}'),
            ],
          ],
        ),
      ),
    );
  }
}

/// A commit of the Activity tab: message, repository, sha and age.
class GhCommitTile extends StatelessWidget {
  const GhCommitTile({super.key, required this.commit});

  final GhCommit commit;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = commit;
    final where = [
      if (c.repo.isNotEmpty) c.repo,
      c.shortSha,
      if (c.date != null) GithubStrings.ago(c.date),
    ].join('  ·  ');
    return InkWell(
      onTap: () => openGhCommit(
        context,
        repo: c.repo.isNotEmpty ? c.repo : _repoOfUrl(c.url),
        sha: c.sha,
        message: c.message,
        url: c.url,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Octicon(
                GithubOcticons.commit,
                size: GithubHubSizes.rowIcon,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _repoOfUrl(String url) {
  final m = RegExp(r'github\.com/([^/]+)/([^/]+)/').firstMatch(url);
  return m == null ? '' : '${m[1]}/${m[2]}';
}

/// Placeholder cells while a list loads.
class GhSkeletonCells extends StatelessWidget {
  const GhSkeletonCells({super.key, this.count = GithubHubSizes.skeletonRows});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bar(double factor, [double h = GithubHubSizes.skeletonBar]) =>
        FractionallySizedBox(
          widthFactor: factor,
          alignment: Alignment.centerLeft,
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        );
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          M3Cell(
            index: i,
            count: count,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: GithubHubSizes.rowAvatar,
                    height: GithubHubSizes.rowAvatar,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      children: [
                        bar(GithubSizes.skeletonWidths[i % 3]),
                        const SizedBox(height: AppSpacing.sm),
                        bar(0.4, GithubSizes.skeletonBar - 2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The body of a list that loads on demand: placeholders, the error with a
/// retry, an empty state, or the cells built by [cell].
class GhLoadableList<T> extends StatelessWidget {
  const GhLoadableList({
    super.key,
    required this.state,
    required this.onRetry,
    required this.cell,
    required this.emptyTitle,
    required this.emptyHint,
    required this.emptyIcon,
  });

  final Loadable<List<T>> state;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T item) cell;
  final String emptyTitle, emptyHint;
  final AppIconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    if (data == null) {
      if (state.failed) {
        return M3Empty(
          icon: emptyIcon,
          title: GithubHubStrings.loadFailed,
          hint: state.message,
          action: FilledButton.tonal(
            onPressed: onRetry,
            child: const Text(GithubHubStrings.retry),
          ),
        );
      }
      return const GhSkeletonCells();
    }
    if (data.isEmpty) {
      return M3Empty(icon: emptyIcon, title: emptyTitle, hint: emptyHint);
    }
    return Column(
      children: [
        for (var i = 0; i < data.length; i++)
          M3Cell(index: i, count: data.length, child: cell(context, data[i])),
      ],
    );
  }
}
