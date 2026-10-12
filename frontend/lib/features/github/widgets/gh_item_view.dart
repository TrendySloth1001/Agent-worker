import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/github_detail.dart';
import '../../../core/haptics.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../chat/widgets/github/github_common.dart';
import '../gh_actions.dart';
import '../gh_item_controller.dart';
import 'gh_detail_header.dart';
import 'gh_rows.dart';
import 'gh_sheets.dart';
import 'gh_timeline.dart';

/// Pieces shared by the pull request and issue screens: banners for
/// read-only / stale states, the action bar, the conversation and the
/// overflow menu.

/// A button that is never dead: when the action is off it stays tappable
/// (dimmed) and explains why.
class GhGatedButton extends StatelessWidget {
  const GhGatedButton({
    super.key,
    required this.label,
    required this.icon,
    required this.allowed,
    required this.onPressed,
    this.reason,
    this.reconnect = false,
    this.filled = false,
    this.busy = false,
  });

  final String label;
  final AppIconData icon;
  final bool allowed, reconnect, filled, busy;
  final String? reason;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tap = busy
        ? null
        : allowed
        ? onPressed
        : () => explainDisabled(context, reason, reconnect: reconnect);
    final child = Opacity(
      opacity: allowed ? 1 : GhDetailSizes.disabledAlpha,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: AppIconSize.sm),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    return Semantics(
      hint: allowed ? null : reason,
      child: filled
          ? FilledButton(onPressed: tap, child: child)
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
              ),
              onPressed: tap,
              child: child,
            ),
    );
  }
}

/// Read-only access, or saved data shown after a failed refresh.
class GhItemBanners extends StatelessWidget {
  const GhItemBanners({super.key, required this.controller});

  final GhItemController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.detail;
    final banners = <Widget>[
      if (d != null && c.error != null)
        GhBanner(
          title: GhDetailStrings.staleTitle,
          body: GhDetailStrings.staleBody(ghErrorText(c.error!)),
          actionLabel: ghNeedsReconnect(c.error)
              ? GhDetailStrings.reconnect
              : GhDetailStrings.retry,
          onAction: ghNeedsReconnect(c.error)
              ? () => ghReconnect(context)
              : c.load,
        ),
      if (d != null && (d.viewer.needsReconnect || !d.viewer.canWrite))
        GhBanner(
          icon: GhDetailIcons.lock,
          title: GhDetailStrings.readOnlyTitle,
          body: d.viewer.canWrite
              ? GhDetailStrings.readOnlyBody
              : GhDetailStrings.notConnectedBody,
          actionLabel: GhDetailStrings.reconnect,
          onAction: () => ghReconnect(context),
        ),
    ];
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in banners) ...[const SizedBox(height: AppSpacing.md), b],
      ],
    );
  }
}

/// The main actions under the header: Review and Merge on a pull request,
/// Close or Reopen on an issue (Ready for review on drafts).
class GhActionBar extends StatelessWidget {
  const GhActionBar({super.key, required this.controller});

  final GhItemController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.detail;
    if (d == null) return const SizedBox.shrink();
    final can = d.can;
    final reconnect = d.viewer.needsReconnect || !d.viewer.canWrite;
    GhGatedButton gate(
      String label,
      AppIconData icon,
      String key,
      bool allowed,
      VoidCallback run, {
      bool filled = false,
    }) => GhGatedButton(
      label: label,
      icon: icon,
      allowed: allowed,
      reason: can.why(key),
      reconnect: reconnect,
      filled: filled,
      busy: c.busy,
      onPressed: () {
        Haptics.tap();
        run();
      },
    );
    final buttons = <Widget>[];
    if (d.isPr) {
      if (d.state == 'merged') return const SizedBox.shrink();
      if (d.state == 'closed') {
        buttons.add(
          gate(
            GhDetailStrings.reopen,
            GhDetailIcons.reopen,
            'reopen',
            can.reopen,
            () => reopenItem(context, c),
          ),
        );
      } else {
        buttons.add(
          gate(
            GhDetailStrings.review,
            GhDetailIcons.review,
            'review',
            true,
            () => showReviewSheet(context, c),
          ),
        );
        buttons.add(
          d.state == 'draft'
              ? gate(
                  GhDetailStrings.markReady,
                  GhDetailIcons.ready,
                  'markReady',
                  can.markReady,
                  () => _markReady(context, c),
                  filled: true,
                )
              : gate(
                  GhDetailStrings.merge,
                  GhDetailIcons.merge,
                  'merge',
                  can.merge,
                  () => showMergeSheet(context, c),
                  filled: true,
                ),
        );
      }
    } else {
      buttons.add(
        d.isOpen
            ? gate(
                GhDetailStrings.close,
                GhDetailIcons.close,
                'close',
                can.close,
                () => showCloseSheet(context, c),
              )
            : gate(
                GhDetailStrings.reopen,
                GhDetailIcons.reopen,
                'reopen',
                can.reopen,
                () => reopenItem(context, c),
              ),
      );
      buttons.add(
        gate(
          GhDetailStrings.react,
          GhDetailIcons.react,
          'react',
          can.react,
          () => showReactSheet(context, c),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

Future<void> _markReady(BuildContext context, GhItemController c) async {
  final err = await c.markReady();
  if (!context.mounted) return;
  if (err != null) {
    showGhError(context, err);
  } else {
    ghToast(context, GhDetailStrings.markedReady);
  }
}

/// Description, timeline and the comment box.
class GhConversation extends StatelessWidget {
  const GhConversation({super.key, required this.controller});

  final GhItemController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.detail;
    if (d == null) return const GhSkeletonCells(count: 3);
    final t = c.timeline;
    final Widget timeline;
    if (t.data != null) {
      timeline = GhTimeline(
        repo: c.fullName,
        detail: d,
        items: t.data!,
        onReact: d.can.react ? () => showReactSheet(context, c) : null,
      );
    } else if (t.failed) {
      timeline = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GhTimeline(
            repo: c.fullName,
            detail: d,
            items: const [],
            onReact: null,
          ),
          M3Empty(
            icon: GhDetailIcons.comment,
            title: GhDetailStrings.loadFailed,
            hint: ghErrorText(t.error!),
            action: FilledButton.tonal(
              onPressed: c.loadTimeline,
              child: const Text(GhDetailStrings.retry),
            ),
          ),
        ],
      );
    } else {
      timeline = const GhSkeletonCells(count: 2);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        timeline,
        const SizedBox(height: AppSpacing.lg),
        GhComposer(controller: c),
      ],
    );
  }
}

/// The overflow: edit, state, reactions, the Sparky review, and the
/// secondary GitHub hand-offs (copy link, open on GitHub).
class GhOverflowMenu extends StatelessWidget {
  const GhOverflowMenu({super.key, required this.controller});

  final GhItemController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.detail;
    final url = d?.url ?? '';
    return PopupMenuButton<String>(
      tooltip: GhDetailStrings.more,
      icon: const AppIcon(GhDetailIcons.more, size: AppIconSize.lg),
      onSelected: (v) async {
        Haptics.tap();
        if (d == null && v != 'refresh') return;
        final reconnect =
            d != null && (d.viewer.needsReconnect || !d.viewer.canWrite);
        void gated(String key, bool ok, VoidCallback run) => ok
            ? run()
            : explainDisabled(context, d!.can.why(key), reconnect: reconnect);
        switch (v) {
          case 'edit':
            gated('edit', d!.can.edit, () => showEditSheet(context, c));
          case 'labels':
            gated('label', d!.can.label, () => showLabelsSheet(context, c));
          case 'assignees':
            gated(
              'assign',
              d!.can.assign,
              () => showAssigneesSheet(context, c),
            );
          case 'close':
            gated('close', d!.can.close, () => showCloseSheet(context, c));
          case 'reopen':
            gated('reopen', d!.can.reopen, () => reopenItem(context, c));
          case 'react':
            gated('react', d!.can.react, () => showReactSheet(context, c));
          case 'sparky':
            openSparkyReview(context, c.owner, c.repo, c.number, d!.title);
          case 'copy':
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) ghToast(context, GhDetailStrings.copied);
          case 'open':
            ghVisit(context, url);
          case 'refresh':
            c.load();
        }
      },
      itemBuilder: (_) => [
        if (d != null) ...[
          _item('edit', GhDetailIcons.edit, GhDetailStrings.edit, d.can.edit),
          _item(
            'labels',
            GhDetailIcons.label,
            GhDetailStrings.editLabels,
            d.can.label,
          ),
          _item(
            'assignees',
            GhDetailIcons.assignee,
            GhDetailStrings.editAssignees,
            d.can.assign,
          ),
          if (d.isOpen)
            _item(
              'close',
              GhDetailIcons.close,
              d.isPr ? GhDetailStrings.closePr : GhDetailStrings.closeIssue,
              d.can.close,
            )
          else if (d.state != 'merged')
            _item(
              'reopen',
              GhDetailIcons.reopen,
              GhDetailStrings.reopen,
              d.can.reopen,
            ),
          if (d.isPr)
            _item(
              'react',
              GhDetailIcons.react,
              GhDetailStrings.react,
              d.can.react,
            ),
          if (d.isPr)
            _item(
              'sparky',
              GhDetailIcons.sparky,
              GhDetailStrings.sparkyReview,
              true,
            ),
          const PopupMenuDivider(),
          _item('copy', GhDetailIcons.copy, GhDetailStrings.copyLink, true),
          _item('open', GhDetailIcons.open, GhDetailStrings.openOnGithub, true),
        ],
        _item('refresh', GhDetailIcons.refresh, GhDetailStrings.refresh, true),
      ],
    );
  }

  static PopupMenuItem<String> _item(
    String value,
    AppIconData icon,
    String label,
    bool allowed,
  ) => PopupMenuItem(
    value: value,
    child: Opacity(
      opacity: allowed ? 1 : GhDetailSizes.disabledAlpha,
      child: Row(
        children: [
          AppIcon(icon, size: AppIconSize.md),
          const SizedBox(width: AppSpacing.md),
          Text(label),
        ],
      ),
    ),
  );
}

/// The whole-screen failure (nothing saved to show).
class GhItemFailed extends StatelessWidget {
  const GhItemFailed({super.key, required this.controller});

  final GhItemController controller;

  @override
  Widget build(BuildContext context) {
    final e = controller.error!;
    final reconnect = ghNeedsReconnect(e);
    return M3Empty(
      icon: GhDetailIcons.warning,
      title: GhDetailStrings.loadFailed,
      hint: ghErrorText(e),
      action: FilledButton.tonal(
        onPressed: reconnect ? () => ghReconnect(context) : controller.load,
        child: Text(
          reconnect ? GhDetailStrings.reconnect : GhDetailStrings.retry,
        ),
      ),
    );
  }
}
