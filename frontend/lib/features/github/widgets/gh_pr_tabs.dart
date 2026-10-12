import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/github_detail.dart';
import '../../../core/constants/widget_github.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/github_api.dart';
import '../../chat/widgets/github/github_common.dart';
import '../gh_actions.dart';

/// The commits of a pull request; each opens in-app.
class GhPrCommitsList extends StatelessWidget {
  const GhPrCommitsList({super.key, required this.repo, required this.commits});

  final String repo;
  final List<GhPrCommit> commits;

  @override
  Widget build(BuildContext context) {
    if (commits.isEmpty) {
      return const M3Empty(
        icon: GhDetailIcons.commit,
        title: GhDetailStrings.noCommits,
      );
    }
    return Column(
      children: [
        for (var i = 0; i < commits.length; i++)
          M3Cell(
            index: i,
            count: commits.length,
            child: _CommitRow(repo: repo, commit: commits[i]),
          ),
      ],
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({required this.repo, required this.commit});

  final String repo;
  final GhPrCommit commit;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = commit;
    return InkWell(
      onTap: () =>
          openGhCommit(context, repo: repo, sha: c.sha, message: c.message),
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
              child: GhAvatar(
                c.author?.avatar ?? '',
                size: GhDetailSizes.avatar,
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
                    [
                      c.who,
                      if (c.date != null) GithubStrings.ago(c.date),
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
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  c.shortSha,
                  style: context.text.caption.copyWith(color: scheme.onSurface),
                ),
                if (c.verified) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    GhDetailStrings.verified,
                    style: context.text.caption.copyWith(
                      color: ghStateColor(context, 'open'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

(AppIconData, Color) _checkLook(BuildContext context, GhCheckState s) {
  final p = context.palette;
  final pending = p.isDark
      ? GhDetailColors.pendingDark
      : GhDetailColors.pendingLight;
  return switch (s) {
    GhCheckState.pass => (GhDetailIcons.pass, ghStateColor(context, 'open')),
    GhCheckState.fail => (GhDetailIcons.fail, p.accent),
    GhCheckState.pending => (GhDetailIcons.pending, pending),
    _ => (GhDetailIcons.skipped, p.textSecondary),
  };
}

String _checkLabel(GhCheckState s) => switch (s) {
  GhCheckState.pass => GhDetailStrings.checkPass,
  GhCheckState.fail => GhDetailStrings.checkFail,
  GhCheckState.pending => GhDetailStrings.checkPending,
  GhCheckState.skipped => GhDetailStrings.checkSkipped,
  GhCheckState.neutral => GhDetailStrings.checkNeutral,
};

/// Check runs and commit statuses: an overall summary, then each check
/// (failures first). A check opens a sheet with its result.
class GhChecksView extends StatelessWidget {
  const GhChecksView({super.key, required this.checks, this.onReconnect});

  final GhChecks checks;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final c = checks;
    if (c.unavailable != null && c.items.isEmpty) {
      return M3Empty(
        icon: GhDetailIcons.warning,
        title: GhDetailStrings.checksUnavailable,
        hint: c.unavailable,
        action: onReconnect == null
            ? null
            : FilledButton.tonal(
                onPressed: onReconnect,
                child: const Text(GhDetailStrings.reconnect),
              ),
      );
    }
    if (c.items.isEmpty) {
      return const M3Empty(
        icon: GhDetailIcons.pass,
        title: GhDetailStrings.noChecks,
        hint: GhDetailStrings.noChecksHint,
      );
    }
    final overall = c.fail > 0
        ? GhCheckState.fail
        : c.pending > 0
        ? GhCheckState.pending
        : GhCheckState.pass;
    final (icon, color) = _checkLook(context, overall);
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3Card(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: GhDetailSizes.eventIcon + AppSpacing.md,
                height: GhDetailSizes.eventIcon + AppSpacing.md,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: GhDetailColors.tintAlpha),
                ),
                alignment: Alignment.center,
                child: AppIcon(icon, size: AppIconSize.lg, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(switch (overall) {
                      GhCheckState.fail => GhDetailStrings.checksFailing,
                      GhCheckState.pending => GhDetailStrings.checksPending,
                      _ => GhDetailStrings.checksPassed,
                    }, style: tt.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      GhDetailStrings.checkCounts(
                        c.fail,
                        c.pending,
                        c.pass,
                        c.skipped,
                      ),
                      style: tt.bodySmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < c.items.length; i++)
          M3Cell(
            index: i,
            count: c.items.length,
            child: _CheckRow(check: c.items[i]),
          ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final GhCheckRun check;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = check;
    final (icon, color) = _checkLook(context, c.status);
    final sub = [
      if (c.app.isNotEmpty) c.app,
      if (c.detail.isNotEmpty) c.detail,
    ].join('  ·  ');
    return InkWell(
      onTap: () {
        Haptics.tap();
        _showCheck(context, c);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            AppIcon(icon, size: GhDetailSizes.statusGlyph, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall,
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall!.copyWith(
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

/// One check in a sheet: its state and summary, the log on GitHub as a
/// secondary action.
Future<void> _showCheck(BuildContext context, GhCheckRun c) =>
    showM3Sheet<void>(
      context,
      builder: (ctx) {
        final (icon, color) = _checkLook(ctx, c.status);
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          top: false,
          child: Padding(
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
                Row(
                  children: [
                    AppIcon(icon, size: AppIconSize.lg, color: color),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        c.name,
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  [
                    _checkLabel(c.status),
                    if (c.app.isNotEmpty) c.app,
                  ].join('  ·  '),
                  style: Theme.of(ctx).textTheme.bodyMedium!.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (c.detail.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(c.detail, style: Theme.of(ctx).textTheme.bodyMedium),
                ],
                if (c.url.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  OutlinedButton.icon(
                    onPressed: () => ghVisit(ctx, c.url),
                    icon: const AppIcon(
                      GhDetailIcons.open,
                      size: AppIconSize.sm,
                    ),
                    label: const Text(GhDetailStrings.viewLog),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
