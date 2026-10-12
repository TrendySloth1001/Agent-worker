import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/github_detail.dart';
import '../../../core/constants/widget_github.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/github_api.dart';
import '../../chat/widgets/github/github_common.dart';
import '../gh_actions.dart';

/// Tinted pill with the state's octicon: Open, Draft, Merged, Closed.
class GhStateChip extends StatelessWidget {
  const GhStateChip({
    super.key,
    required this.state,
    required this.isPr,
    this.reason,
  });

  final String state;
  final bool isPr;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final color = ghStateColor(context, state, isPr: isPr, reason: reason);
    return Container(
      height: GhDetailSizes.stateChipHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: GhDetailColors.tintAlpha),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Octicon(
            ghItemStateIcon(state, isPr: isPr, reason: reason),
            size: GithubSizes.octicon,
            color: color,
          ),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          Text(
            ghStateLabel(state, reason: reason),
            style: Theme.of(
              context,
            ).textTheme.labelLarge!.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Avatar + login, e.g. an assignee.
class GhPerson extends StatelessWidget {
  const GhPerson(this.user, {super.key, this.size = GhDetailSizes.avatarSmall});

  final GhUser user;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      GhAvatar(user.avatar, size: size),
      const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
      Text(user.login, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

/// Title, state, author, branches and size of a pull request or issue.
class GhDetailHeader extends StatelessWidget {
  const GhDetailHeader({
    super.key,
    required this.repo,
    required this.number,
    required this.isPr,
    required this.seedTitle,
    required this.detail,
    required this.onAsk,
  });

  final String repo;
  final int number;
  final bool isPr;
  final String seedTitle;
  final GhItemDetail? detail;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final d = detail;
    final title = d?.title ?? seedTitle;
    final who = d?.user;
    final ago = GithubStrings.ago(d?.createdAt).toLowerCase();
    return M3Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (d != null)
                GhStateChip(state: d.state, isPr: isPr, reason: d.stateReason)
              else
                const SizedBox(height: GhDetailSizes.stateChipHeight),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '$repo ${GithubStrings.issueNumber(number)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (d?.locked == true) ...[
                const SizedBox(width: AppSpacing.sm),
                AppIcon(
                  GhDetailIcons.lock,
                  size: AppIconSize.sm,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: tt.titleLarge),
          if (who != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                GhAvatar(who.avatar, size: GhDetailSizes.avatarSmall),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    d!.state == 'merged' && d.mergedBy != null
                        ? GhDetailStrings.mergedBy(
                            d.mergedBy!.login,
                            GithubStrings.ago(d.mergedAt).toLowerCase(),
                          )
                        : GhDetailStrings.opened(who.login, ago),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (isPr && d != null && d.base.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _Branches(base: d.base, head: d.head),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GhStat(
                  GithubOcticons.commit,
                  GhDetailStrings.commits(d.commits),
                ),
                GhStat(
                  GithubOcticons.fileCode,
                  GhDetailStrings.files(d.changedFiles),
                ),
                GhStat(GithubOcticons.comment, '${d.comments}'),
                GhDelta(add: d.additions, del: d.deletions),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onAsk,
            icon: const AppIcon(GhDetailIcons.ask, size: AppIconSize.md),
            label: const Text(GhDetailStrings.askSparky),
          ),
        ],
      ),
    );
  }
}

/// `base ← head` as two mono pills.
class _Branches extends StatelessWidget {
  const _Branches({required this.base, required this.head});

  final String base, head;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Flexible(child: GhChip(base, icon: GithubOcticons.branch)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            GhDetailStrings.intoArrow,
            style: context.text.label.copyWith(color: p.textTertiary),
          ),
        ),
        Flexible(child: GhChip(head, icon: GithubOcticons.branch)),
      ],
    );
  }
}

/// Labels, assignees, reviewers and milestone, each editable when allowed
/// (otherwise the pencil explains why).
class GhMetaCard extends StatelessWidget {
  const GhMetaCard({
    super.key,
    required this.detail,
    required this.onLabels,
    required this.onAssignees,
  });

  final GhItemDetail detail;
  final VoidCallback onLabels, onAssignees;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final rows = <Widget>[
      _MetaRow(
        icon: GhDetailIcons.label,
        title: GhDetailStrings.labels,
        allowed: d.can.label,
        reason: d.can.why('label'),
        reconnect: d.viewer.needsReconnect || !d.viewer.canWrite,
        onEdit: onLabels,
        child: d.labels.isEmpty
            ? null
            : Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final l in d.labels)
                    GhChip(l.name, dot: ghLabelColor(l.color)),
                ],
              ),
      ),
      _MetaRow(
        icon: GhDetailIcons.assignee,
        title: GhDetailStrings.assignees,
        allowed: d.can.assign,
        reason: d.can.why('assign'),
        reconnect: d.viewer.needsReconnect || !d.viewer.canWrite,
        onEdit: onAssignees,
        child: d.assignees.isEmpty ? null : _People(d.assignees),
      ),
      if (d.isPr)
        _MetaRow(
          icon: GhDetailIcons.reviewer,
          title: GhDetailStrings.reviewers,
          child: d.requestedReviewers.isEmpty && d.requestedTeams.isEmpty
              ? null
              : Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final u in d.requestedReviewers) GhPerson(u),
                    for (final t in d.requestedTeams) GhChip(t),
                  ],
                ),
        ),
      if (d.milestone != null)
        _MetaRow(
          icon: GhDetailIcons.milestone,
          title: GhDetailStrings.milestone,
          child: Text(
            d.milestone!.title,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
    ];
    return M3Group(children: rows);
  }
}

class _People extends StatelessWidget {
  const _People(this.users);

  final List<GhUser> users;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.xs,
    children: [for (final u in users) GhPerson(u)],
  );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.title,
    this.child,
    this.onEdit,
    this.allowed = false,
    this.reason,
    this.reconnect = false,
  });

  final AppIconData icon;
  final String title;
  final Widget? child;
  final VoidCallback? onEdit;
  final bool allowed;
  final String? reason;
  final bool reconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final edit = onEdit == null
        ? null
        : IconButton(
            tooltip: allowed ? title : reason,
            onPressed: allowed
                ? onEdit
                : () => explainDisabled(context, reason, reconnect: reconnect),
            icon: Opacity(
              opacity: allowed ? 1 : GhDetailSizes.disabledAlpha,
              child: AppIcon(
                GhDetailIcons.edit,
                size: AppIconSize.md,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        edit == null ? AppSpacing.lg : AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: AppIcon(
              icon,
              size: AppIconSize.md,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                child ??
                    Text(
                      GhDetailStrings.none,
                      style: tt.bodyMedium!.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              ],
            ),
          ),
          ?edit,
        ],
      ),
    );
  }
}

/// Inline banner: read-only access, or saved data after a failed refresh.
class GhBanner extends StatelessWidget {
  const GhBanner({
    super.key,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.icon = GhDetailIcons.warning,
  });

  final String title, body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AppIconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return M3Card(
      high: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          AppIcon(icon, size: AppIconSize.md, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  body,
                  style: tt.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
