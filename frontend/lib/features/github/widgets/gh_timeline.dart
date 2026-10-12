import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/github_detail.dart';
import '../../../core/constants/rich_cards.dart';
import '../../../core/constants/widget_github.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/github_api.dart';
import '../../chat/widgets/github/github_common.dart';
import '../../chat/widgets/markdown/app_markdown.dart';
import '../../chat/widgets/rich/rich_parsers.dart';
import '../gh_actions.dart';

/// The conversation of a pull request or issue: the description, then
/// comments, reviews (with their inline comments) and events, oldest first.
class GhTimeline extends StatelessWidget {
  const GhTimeline({
    super.key,
    required this.repo,
    required this.detail,
    required this.items,
    required this.onReact,
  });

  final String repo;
  final GhItemDetail detail;
  final List<GhTimelineItem> items;

  /// Adds a reaction to the description; null when not allowed.
  final VoidCallback? onReact;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final children = <Widget>[
      GhCommentCard(
        user: d.user,
        at: d.createdAt,
        verb: GhDetailStrings.commented,
        body: d.body.trim().isEmpty ? null : d.body,
        empty: GhDetailStrings.noDescription,
        reactions: d.reactions,
        onReact: onReact,
      ),
    ];
    for (final it in items) {
      children.add(const SizedBox(height: AppSpacing.md));
      children.add(_item(context, it));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _item(BuildContext context, GhTimelineItem it) {
    switch (it.kind) {
      case GhTimelineKind.comment:
        if (it.event == 'review_comment') {
          return GhCommentCard(
            user: it.actor,
            at: it.at,
            verb: GhDetailStrings.reviewCommented,
            body: null,
            footer: [for (final c in it.comments) GhInlineComment(comment: c)],
          );
        }
        return GhCommentCard(
          user: it.actor,
          at: it.at,
          verb: GhDetailStrings.commented,
          body: it.body,
          reactions: it.reactions,
        );
      case GhTimelineKind.review:
        final (verb, badge, tone) = switch (it.state) {
          'approved' => (
            GhDetailStrings.reviewApproved,
            GhDetailStrings.approvedBadge,
            'open',
          ),
          'changes_requested' => (
            GhDetailStrings.reviewChanges,
            GhDetailStrings.changesBadge,
            'closed',
          ),
          'dismissed' => (
            GhDetailStrings.reviewDismissed,
            GhDetailStrings.commentBadge,
            'draft',
          ),
          _ => (
            GhDetailStrings.reviewCommented,
            GhDetailStrings.commentBadge,
            'draft',
          ),
        };
        return GhCommentCard(
          user: it.actor,
          at: it.at,
          verb: verb,
          badge: badge,
          badgeColor: ghStateColor(context, tone),
          body: it.body.trim().isEmpty ? null : it.body,
          footer: [for (final c in it.comments) GhInlineComment(comment: c)],
        );
      case GhTimelineKind.commit:
        return GhEventRow(
          octicon: GithubOcticons.commit,
          actorName: it.body,
          text: it.detail,
          trailing: it.sha.length >= 7 ? it.sha.substring(0, 7) : it.sha,
          at: it.at,
          onTap: () => openGhCommit(
            context,
            repo: repo,
            sha: it.sha,
            message: it.detail,
            url: it.url,
          ),
        );
      case GhTimelineKind.event:
        final (icon, tone) = _eventLook(it.event);
        final crossRef = it.event == 'cross-referenced';
        final mergedCommit = it.event == 'merged' && it.sha.isNotEmpty;
        return GhEventRow(
          octicon: icon,
          color: tone == null ? null : ghStateColor(context, tone),
          actor: it.actor,
          text: GhDetailStrings.event(it.event, it.label?.name ?? it.detail),
          dot: it.label == null ? null : ghLabelColor(it.label!.color),
          at: it.at,
          onTap: mergedCommit
              ? () => openGhCommit(context, repo: repo, sha: it.sha)
              : crossRef && it.url.isNotEmpty
              ? () => _openRef(context, it)
              : null,
        );
    }
  }

  /// A mentioned issue / pull request opens in-app.
  void _openRef(BuildContext context, GhTimelineItem it) {
    final m = RegExp(
      r'github\.com/([^/]+/[^/]+)/(pull|issues)/(\d+)',
    ).firstMatch(it.url);
    if (m == null) return;
    openGhItem(
      context,
      repo: m[1]!,
      number: int.parse(m[3]!),
      isPr: m[2] == 'pull',
      url: it.url,
    );
  }

  static (String, String?) _eventLook(String e) => switch (e) {
    'labeled' || 'unlabeled' => (GithubOcticons.tag, null),
    'merged' => (GithubOcticons.merged, 'merged'),
    'closed' => (GithubOcticons.prClosed, 'closed'),
    'reopened' => (GithubOcticons.pr, 'open'),
    'head_ref_force_pushed' ||
    'head_ref_deleted' ||
    'head_ref_restored' ||
    'base_ref_changed' => (GithubOcticons.branch, null),
    'assigned' ||
    'unassigned' ||
    'review_requested' => (GithubOcticons.people, null),
    'ready_for_review' => (GithubOcticons.eye, null),
    'convert_to_draft' => (GithubOcticons.prDraft, null),
    'cross-referenced' || 'referenced' => (GithubOcticons.compare, null),
    'renamed' => (GithubOcticons.fileCode, null),
    'milestoned' || 'demilestoned' => (GithubOcticons.tag, null),
    _ => (GithubOcticons.comment, null),
  };
}

/// A comment or review: avatar, who and when, a badge, the markdown body,
/// reactions and anything below (inline review comments).
class GhCommentCard extends StatelessWidget {
  const GhCommentCard({
    super.key,
    required this.user,
    required this.at,
    required this.verb,
    required this.body,
    this.empty,
    this.badge,
    this.badgeColor,
    this.reactions = const {},
    this.onReact,
    this.footer = const [],
  });

  final GhUser? user;
  final DateTime? at;
  final String verb;
  final String? body;

  /// Shown (muted) when [body] is null; nothing when both are null.
  final String? empty;
  final String? badge;
  final Color? badgeColor;
  final Map<String, int> reactions;
  final VoidCallback? onReact;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ago = GithubStrings.ago(at).toLowerCase();
    final b = body;
    return M3Card(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhAvatar(user?.avatar ?? '', size: GhDetailSizes.avatar),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: user?.login ?? GhDetailStrings.someone,
                        style: tt.titleSmall,
                      ),
                      TextSpan(
                        text: '  $verb',
                        style: tt.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _Badge(badge!, badgeColor ?? scheme.onSurfaceVariant),
              ] else if (ago.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  ago,
                  style: context.text.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          if (b != null || empty != null) ...[
            const SizedBox(height: AppSpacing.md),
            if (b != null)
              AppMarkdown(data: b, citations: const [], streaming: false)
            else
              Text(
                empty!,
                style: tt.bodyMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
          if (reactions.isNotEmpty || onReact != null) ...[
            const SizedBox(height: AppSpacing.md),
            GhReactionsRow(reactions: reactions, onAdd: onReact),
          ],
          for (final f in footer) ...[const SizedBox(height: AppSpacing.md), f],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: GhDetailColors.tintAlpha),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(text, style: context.text.caption.copyWith(color: color)),
  );
}

/// Reaction counts with an add button.
class GhReactionsRow extends StatelessWidget {
  const GhReactionsRow({super.key, required this.reactions, this.onAdd});

  final Map<String, int> reactions;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget pill(Widget child, {VoidCallback? onTap}) => Material(
      color: scheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: GhDetailSizes.reactionChipHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final e in reactions.entries)
          pill(
            Text(
              '${GhReactions.emoji(e.key)} ${e.value}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        if (onAdd != null)
          Semantics(
            button: true,
            label: GhDetailStrings.react,
            child: pill(
              AppIcon(
                GhDetailIcons.react,
                size: AppIconSize.sm,
                color: scheme.onSurfaceVariant,
              ),
              onTap: () {
                Haptics.tap();
                onAdd!();
              },
            ),
          ),
      ],
    );
  }
}

/// One inline review comment: file and line, the end of the diff hunk, and
/// the comment.
class GhInlineComment extends StatelessWidget {
  const GhInlineComment({super.key, required this.comment});

  final GhThreadComment comment;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final c = comment;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                const Octicon(GithubOcticons.fileCode),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    GhDetailStrings.line(c.path, c.line),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (c.diffHunk.isNotEmpty) GhHunkPreview(hunk: c.diffHunk),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.user != null) ...[
                  Row(
                    children: [
                      GhAvatar(c.user!.avatar, size: GhDetailSizes.avatarSmall),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        c.user!.login,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                AppMarkdown(
                  data: c.body,
                  citations: const [],
                  streaming: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The last lines of a diff hunk, colored, scrolling sideways.
class GhHunkPreview extends StatelessWidget {
  const GhHunkPreview({super.key, required this.hunk});

  final String hunk;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final green = p.isDark ? DiffStyle.addDark : DiffStyle.addLight;
    final lines = hunk.split('\n');
    final tail = lines.length > GhDetailSizes.hunkLines
        ? lines.sublist(lines.length - GhDetailSizes.hunkLines)
        : lines;
    final code = context.text.code.copyWith(
      fontSize: DiffStyle.fontSize,
      height: DiffStyle.lineHeight,
    );
    return Container(
      color: p.codeBackground,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final l in tail)
                () {
                  final kind = diffKind(l, inHunk: true);
                  final (Color? bg, Color fg) = switch (kind) {
                    DiffKind.added => (
                      green.withValues(alpha: DiffStyle.addAlpha),
                      p.textPrimary,
                    ),
                    DiffKind.removed => (
                      p.accent.withValues(alpha: DiffStyle.removeAlpha),
                      p.accent,
                    ),
                    DiffKind.hunk => (null, p.textTertiary),
                    _ => (null, p.synPlain),
                  };
                  return Container(
                    color: bg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Text(
                      l.isEmpty ? ' ' : l,
                      softWrap: false,
                      style: code.copyWith(color: fg),
                    ),
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line event: icon, who, what, when; tappable when it leads
/// somewhere (a commit, a mentioned issue).
class GhEventRow extends StatelessWidget {
  const GhEventRow({
    super.key,
    required this.octicon,
    required this.text,
    required this.at,
    this.actor,
    this.actorName = '',
    this.color,
    this.dot,
    this.trailing,
    this.onTap,
  });

  final String octicon;
  final String text;
  final DateTime? at;
  final GhUser? actor;
  final String actorName;
  final Color? color;
  final Color? dot;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final who = actor?.login ?? actorName;
    final ago = GithubStrings.ago(at).toLowerCase();
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: GhDetailSizes.eventIcon,
            height: GhDetailSizes.eventIcon,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  color?.withValues(alpha: GhDetailColors.tintAlpha) ??
                  scheme.surfaceContainerHighest,
            ),
            alignment: Alignment.center,
            child: Octicon(
              octicon,
              size: GhDetailSizes.eventGlyph,
              color: color ?? scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (dot != null) ...[
            Container(
              width: GithubSizes.labelDot,
              height: GithubSizes.labelDot,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (who.isNotEmpty)
                    TextSpan(text: '$who ', style: tt.labelLarge),
                  TextSpan(
                    text: text,
                    style: tt.bodySmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              trailing!,
              style: context.text.caption.copyWith(color: scheme.onSurface),
            ),
          ],
          if (ago.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              ago,
              style: context.text.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: row,
    );
  }
}
