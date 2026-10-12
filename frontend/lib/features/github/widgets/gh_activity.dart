import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/apps.dart';
import '../../../core/constants/github_detail.dart';
import '../../../core/constants/widget_github.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/github_api.dart';
import '../../chat/widgets/github/github_common.dart';
import '../../chat/widgets/markdown/app_markdown.dart';
import '../../settings/widgets/settings_kit.dart';
import '../gh_actions.dart';
import '../github_repo_screen.dart';

/// The account's activity feed grouped by day. Every item opens in-app:
/// a push its head commit, a pull request / issue / review / comment its
/// screen, a release its notes, anything else the repository. Each row has
/// Ask Sparky.
class GhActivityFeed extends StatelessWidget {
  const GhActivityFeed({super.key, required this.items, this.now});

  final List<GhActivity> items;

  /// Test seam for the day headers.
  final DateTime? now;

  static String dayLabel(DateTime d, DateTime now) {
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return GhActivityStrings.today;
    if (diff == 1) return GhActivityStrings.yesterday;
    return GhActivityStrings.day(d);
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const M3Empty(
        icon: GhDetailIcons.commit,
        title: GhActivityStrings.empty,
        hint: GhActivityStrings.emptyHint,
      );
    }
    final n = now ?? DateTime.now();
    final groups = <String, List<GhActivity>>{};
    for (final it in items) {
      final at = it.at;
      groups.putIfAbsent(at == null ? '' : dayLabel(at, n), () => []).add(it);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups.entries) ...[
          if (g.key.isNotEmpty) SettingsGroupHeader(g.key),
          for (var i = 0; i < g.value.length; i++)
            M3Cell(
              index: i,
              count: g.value.length,
              child: GhActivityTile(item: g.value[i]),
            ),
        ],
      ],
    );
  }
}

String _octicon(GhActivity a) => switch (a.type) {
  'push' => GithubOcticons.commit,
  'pr' when a.action == 'merged' => GithubOcticons.merged,
  'pr' when a.action == 'closed' => GithubOcticons.prClosed,
  'pr' || 'review' => GithubOcticons.pr,
  'issue' when a.action == 'closed' => GithubOcticons.issueClosed,
  'issue' => GithubOcticons.issueOpen,
  'comment' => GithubOcticons.comment,
  'release' => GithubOcticons.tag,
  'create' || 'delete' => GithubOcticons.branch,
  'fork' => GithubOcticons.fork,
  'star' => GithubOcticons.star,
  _ => GithubOcticons.repo,
};

/// The chat prompt for an activity item.
String activityPrompt(GhActivity a) => switch (a.type) {
  'pr' || 'review' || 'comment' when a.isPr && a.number != null =>
    GhPrompts.pull(a.repo, a.number!, a.title),
  'issue' || 'comment' when a.number != null => GhPrompts.issue(
    a.repo,
    a.number!,
    a.title,
  ),
  'push' => GhPrompts.push(a.repo, a.ref ?? ''),
  'release' => GhPrompts.release(a.repo, a.releaseTag),
  _ => GhPrompts.repo(a.repo),
};

/// Opens [a] in the matching in-app screen.
void openActivity(BuildContext context, GhActivity a) {
  final n = a.number;
  switch (a.type) {
    case 'pr' || 'review' || 'comment' || 'issue' when n != null:
      openGhItem(
        context,
        repo: a.repo,
        number: n,
        isPr: a.isPr,
        title: a.title,
        url: a.url,
      );
    case 'push' when (a.sha ?? '').isNotEmpty:
      openGhCommit(
        context,
        repo: a.repo,
        sha: a.sha!,
        message: a.commits.isEmpty ? '' : a.commits.first.$2,
        url: a.url,
      );
    case 'release':
      Haptics.tap();
      showReleaseSheet(context, a);
    default:
      Haptics.tap();
      final repo = a.type == 'fork' && a.title.contains('/') ? a.title : a.repo;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GithubRepoScreen(seed: GhRepo({'fullName': repo})),
        ),
      );
  }
}

class GhActivityTile extends StatelessWidget {
  const GhActivityTile({super.key, required this.item});

  final GhActivity item;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = context.palette;
    final a = item;
    final verb = GhActivityStrings.verb(
      a.type,
      a.action,
      a.number,
      a.isPr,
      a.ref ?? '',
      a.commits.length,
    );
    final tint = a.action == 'merged'
        ? ghStateColor(context, 'merged')
        : a.type == 'release'
        ? p.accent
        : scheme.onSurface;
    return InkWell(
      onTap: () => openActivity(context, a),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Octicon(
                _octicon(a),
                size: GithubHubSizes.rowIcon,
                color: tint,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    verb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (a.title.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    [
                      a.repo,
                      if (a.at != null) GithubStrings.ago(a.at),
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: GhDetailStrings.askSparky,
              onPressed: () => askSparky(context, activityPrompt(a)),
              icon: AppIcon(
                GhDetailIcons.ask,
                size: AppIconSize.md,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A release's notes, with Ask Sparky; GitHub is the secondary action.
Future<void> showReleaseSheet(BuildContext context, GhActivity a) =>
    showM3Sheet<void>(
      context,
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                a.releaseName.isEmpty ? a.releaseTag : a.releaseName,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${a.repo}  ·  ${a.releaseTag}',
                style: ctx.text.caption.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (a.body.trim().isEmpty)
                Text(
                  GhActivityStrings.releaseNoNotes,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                )
              else
                AppMarkdown(
                  data: a.body,
                  citations: const [],
                  streaming: false,
                ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () =>
                    askSparky(ctx, GhPrompts.release(a.repo, a.releaseTag)),
                icon: const AppIcon(GhDetailIcons.ask, size: AppIconSize.md),
                label: const Text(GhDetailStrings.askSparky),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => ghVisit(ctx, a.url),
                icon: const AppIcon(GhDetailIcons.open, size: AppIconSize.sm),
                label: const Text(GhDetailStrings.openOnGithub),
              ),
            ],
          ),
        ),
      ),
    );
