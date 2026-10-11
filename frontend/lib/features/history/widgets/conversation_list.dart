import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/conversation.dart';
import '../history_controller.dart';
import 'chat_row.dart';

/// Pull-to-refresh list of conversations grouped by recency, with
/// loading, empty, no-match and error states.
class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.controller,
    required this.currentId,
    required this.onOpen,
    required this.onActions,
  });

  final HistoryController controller;
  final String? currentId;
  final ValueChanged<ConversationSummary> onOpen;
  final ValueChanged<ConversationSummary> onActions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RefreshIndicator(
        color: p.accent,
        backgroundColor: p.surface,
        onRefresh: controller.load,
        child: _list(context),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final p = context.palette;
    final padding = EdgeInsets.fromLTRB(
      AppSpacing.screenPadding,
      0,
      AppSpacing.screenPadding,
      AppSpacing.lg,
    );
    if (controller.loading) return ListView(padding: padding);
    if (controller.items.isEmpty) {
      final searching = controller.query.trim().isNotEmpty;
      final failed = controller.error != null;
      return ListView(
        padding: padding,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: AppIcon(
              failed
                  ? AppIcons.alert
                  : searching
                  ? AppIcons.search
                  : controller.archived
                  ? AppIcons.archive
                  : AppIcons.history,
              size: AppIconSize.empty,
              color: failed ? p.accent : p.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            failed
                ? AppStrings.historyLoadFailed
                : searching
                ? AppStrings.historyNoMatches
                : controller.archived
                ? AppStrings.archivedEmpty
                : AppStrings.historyEmpty,
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
          if (failed) ...[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton(
                onPressed: () {
                  Haptics.tap();
                  controller.load();
                },
                child: Text(
                  AppStrings.retry,
                  style: context.text.caption.copyWith(color: p.accent),
                ),
              ),
            ),
          ],
        ],
      );
    }

    final now = DateTime.now();
    final children = <Widget>[];
    String? group;
    for (final chat in controller.items) {
      // The server lists pinned chats first.
      final g = chat.pinned ? AppStrings.pinned : _group(chat.updatedAt, now);
      if (g != group) {
        group = g;
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.lg,
              bottom: AppSpacing.xs,
            ),
            child: Text(g, style: context.text.caption),
          ),
        );
      }
      children.add(
        ChatRow(
          chat: chat,
          time: _time(chat.updatedAt, now),
          isCurrent: chat.id == currentId,
          onTap: () => onOpen(chat),
          onLongPress: () => onActions(chat),
        ),
      );
    }
    return ListView(padding: padding, children: children);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _group(DateTime at, DateTime now) {
    final days = _day(now).difference(_day(at)).inDays;
    if (days <= 0) return AppStrings.today;
    if (days == 1) return AppStrings.yesterday;
    if (days < 7) return AppStrings.thisWeek;
    return AppStrings.earlier;
  }

  static String _time(DateTime at, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (_day(now) == _day(at)) return '${two(at.hour)}:${two(at.minute)}';
    final month = AppStrings.months[at.month - 1];
    return at.year == now.year
        ? '${at.day} $month'
        : '${at.day} $month ${at.year}';
  }
}
