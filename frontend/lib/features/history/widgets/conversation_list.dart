import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/history.dart';
import '../../../core/constants/illustrations.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/m3_kit_extras.dart' show sentenceCase;
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/illustration.dart';
import '../../../data/conversation.dart';
import '../history_controller.dart';
import '../history_grouping.dart';
import 'chat_row.dart';
import 'history_skeleton.dart';

/// Pull-to-refresh list of conversations: sticky date groups, endless
/// paging, and skeleton, empty, no-match and error states.
class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.controller,
    required this.currentId,
    required this.onOpen,
    required this.onActions,
    required this.onPin,
    required this.onArchive,
    required this.onRename,
    this.runningIds = const {},
  });

  final HistoryController controller;
  final String? currentId;

  /// Chats with a reply, round table or document being written.
  final Set<String> runningIds;
  final ValueChanged<ConversationSummary> onOpen;
  final ValueChanged<ConversationSummary> onActions;
  final ValueChanged<ConversationSummary> onPin;
  final ValueChanged<ConversationSummary> onArchive;
  final void Function(ConversationSummary chat, String title) onRename;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RefreshIndicator(
        color: p.accent,
        backgroundColor: p.surface,
        onRefresh: controller.load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < HistorySizes.loadMoreExtent) {
              controller.loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: _slivers(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _slivers(BuildContext context) {
    final p = context.palette;
    final items = controller.visible;
    if (controller.loading) {
      return [
        const SliverToBoxAdapter(
          child: SizedBox(
            height: HistorySizes.rowHeight * HistorySizes.skeletonRows,
            child: HistorySkeleton(),
          ),
        ),
      ];
    }
    if (items.isEmpty) {
      if (controller.searchPending) {
        return [
          const SliverToBoxAdapter(
            child: SizedBox(
              height: HistorySizes.rowHeight * 3,
              child: HistorySkeleton(),
            ),
          ),
        ];
      }
      return [
        SliverFillRemaining(hasScrollBody: false, child: _empty(context)),
      ];
    }

    final now = DateTime.now();
    final query = controller.query.trim();
    ChatRow row(ConversationSummary c, {String? time}) => ChatRow(
      key: ValueKey(c.id),
      chat: c,
      isCurrent: c.id == currentId,
      running: runningIds.contains(c.id),
      query: query,
      time: time,
      archivedList: controller.archived,
      renaming: controller.renamingId == c.id,
      onTap: () => onOpen(c),
      onLongPress: () => onActions(c),
      onPin: () => onPin(c),
      onArchive: () => onArchive(c),
      onRename: (title) => onRename(c, title),
      onCancelRename: controller.cancelRename,
    );

    final slivers = <Widget>[];
    if (query.isNotEmpty) {
      slivers.add(
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (_, i) =>
              row(items[i], time: historyTime(items[i].updatedAt, now)),
        ),
      );
    } else {
      final scaler = MediaQuery.textScalerOf(context);
      final extent = scaler.scale(AppFontSize.body * 1.3) + AppSpacing.xl;
      final height = extent < HistorySizes.groupHeight
          ? HistorySizes.groupHeight
          : extent;
      for (final g in groupConversations(items, now)) {
        slivers.add(
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _GroupHeader(
                  label: sentenceCase(g.label),
                  height: height,
                  background: p.background,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge!.copyWith(color: p.textSecondary),
                ),
              ),
              SliverList.builder(
                itemCount: g.items.length,
                itemBuilder: (_, i) => row(
                  g.items[i],
                  // Pinned chats have no date group, so they carry a time.
                  time: g.isPinned
                      ? historyTime(g.items[i].updatedAt, now)
                      : null,
                ),
              ),
            ],
          ),
        );
      }
    }
    slivers.add(
      SliverToBoxAdapter(
        child: SizedBox(
          height: HistorySizes.rowHeight,
          child: controller.loadingMore
              ? Center(
                  child: SizedBox.square(
                    dimension: AppIconSize.sm,
                    child: CircularProgressIndicator(
                      strokeWidth: AppBorder.thin,
                      color: p.textTertiary,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
    return slivers;
  }

  Widget _empty(BuildContext context) {
    final p = context.palette;
    final searching = controller.searching;
    final failed = controller.error != null;
    final String text;
    if (failed) {
      text = AppStrings.historyLoadFailed;
    } else if (searching) {
      text = '${HistoryStrings.noMatchesFor} "${controller.query.trim()}".';
    } else if (controller.archived) {
      text = AppStrings.archivedEmpty;
    } else {
      text = AppStrings.historyEmpty;
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xl),
          if (!failed && !searching && !controller.archived)
            Illustration(
              kind: IllustrationKind.emptyHistory,
              height: IllustrationSizes.emptyHistory,
              paper: p.surface,
            )
          else
            AppIcon(
              failed
                  ? AppIcons.alert
                  : searching
                  ? AppIcons.search
                  : AppIcons.archive,
              size: AppIconSize.empty,
              color: failed ? p.accent : p.textTertiary,
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
          if (failed) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () {
                Haptics.tap();
                controller.load();
              },
              child: Text(
                AppStrings.retry,
                style: context.text.caption.copyWith(color: p.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sentence-case M3 label that sticks to the top until its group has passed.
class _GroupHeader extends SliverPersistentHeaderDelegate {
  _GroupHeader({
    required this.label,
    required this.height,
    required this.background,
    required this.style,
  });

  final String label;
  final double height;
  final Color background;
  final TextStyle style;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Semantics(
      header: true,
      child: Container(
        color: background,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(
          DrawerMotion.itemInset + AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.sm,
        ),
        child: Text(label, style: style, maxLines: 1),
      ),
    );
  }

  @override
  bool shouldRebuild(_GroupHeader old) =>
      label != old.label ||
      height != old.height ||
      background != old.background ||
      style != old.style;
}
