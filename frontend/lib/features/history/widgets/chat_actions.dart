import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/chat_cleanup.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/history.dart';
import '../../../core/constants/share_export.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../settings/widgets/settings_kit.dart';
import '../../../data/conversation.dart';
import '../history_controller.dart';
import 'merge_picker.dart';

/// Long-press menu for a conversation: rename (inline in the list), pin,
/// archive, fork, merge, export or delete. Calls [onDeleted] after the server
/// accepted the delete. [onFork] duplicates the chat and opens the copy. [onMerge] merges
/// it with another and opens the result; [onMerged] gets its outcome once the
/// progress dialog has closed. [onExport] (when set) offers EXPORT as
/// Markdown or PDF.
Future<void> showChatActions(
  BuildContext context, {
  required ConversationSummary chat,
  required HistoryController controller,
  required ValueChanged<String> onDeleted,
  required Future<bool> Function(ConversationSummary chat) onFork,
  required Future<bool> Function(String id, String otherId) onMerge,
  required ValueChanged<bool> onMerged,
  Future<void> Function(ConversationSummary chat)? onExport,
}) async {
  Haptics.tap();
  final p = context.palette;
  final action = await showM3Sheet<String>(
    context,
    builder: (sheet) => M3ActionSheet(
      title: chat.title ?? HistoryStrings.untitled,
      rows: [
        _SheetRow(
          label: AppStrings.rename,
          icon: AppIcons.edit,
          onTap: () => Navigator.pop(sheet, AppStrings.rename),
        ),
        _SheetRow(
          label: chat.pinned ? AppStrings.unpinChat : AppStrings.pinChat,
          icon: chat.pinned ? AppIcons.unpin : AppIcons.pin,
          onTap: () => Navigator.pop(sheet, AppStrings.pinChat),
        ),
        _SheetRow(
          label: chat.archived
              ? AppStrings.unarchiveChat
              : AppStrings.archiveChat,
          icon: chat.archived ? AppIcons.unarchive : AppIcons.archive,
          onTap: () => Navigator.pop(sheet, AppStrings.archiveChat),
        ),
        _SheetRow(
          label: LineageStrings.fork,
          icon: AppIcons.fork,
          onTap: () => Navigator.pop(sheet, LineageStrings.fork),
        ),
        _SheetRow(
          label: LineageStrings.mergeWith,
          icon: AppIcons.merge,
          onTap: () => Navigator.pop(sheet, LineageStrings.mergeWith),
        ),
        if (onExport != null)
          _SheetRow(
            label: ShareStrings.export,
            icon: ShareIcons.export,
            onTap: () => Navigator.pop(sheet, ShareStrings.export),
          ),
        _SheetRow(
          label: AppStrings.deleteChat,
          icon: AppIcons.delete,
          color: p.accent,
          onTap: () => Navigator.pop(sheet, AppStrings.deleteChat),
        ),
      ],
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == AppStrings.pinChat) {
    final ok = await controller.setPinned(chat.id, !chat.pinned);
    ok ? Haptics.received() : Haptics.error();
    return;
  }
  if (action == AppStrings.archiveChat) {
    await archiveChat(context, chat, controller);
    return;
  }
  if (action == LineageStrings.fork) {
    await onFork(chat);
    return;
  }
  if (action == LineageStrings.mergeWith) {
    await _merge(context, chat, controller, onMerge, onMerged);
    return;
  }
  if (action == ShareStrings.export) {
    await onExport?.call(chat);
    return;
  }
  if (action == AppStrings.rename) {
    controller.beginRename(chat.id);
    return;
  }
  if (action == AppStrings.deleteChat) {
    await _delete(context, chat, controller, onDeleted);
  }
}

/// Archives or restores, with an UNDO on the notice.
Future<void> archiveChat(
  BuildContext context,
  ConversationSummary chat,
  HistoryController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final value = !chat.archived;
  if (!await controller.setArchived(chat.id, value)) {
    Haptics.error();
    return;
  }
  Haptics.received();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          value ? AppStrings.chatArchived : AppStrings.chatUnarchived,
        ),
        action: SnackBarAction(
          label: AppStrings.undo,
          onPressed: () {
            Haptics.tap();
            controller.setArchived(chat.id, !value);
          },
        ),
      ),
    );
}

/// Picks the other chat, confirms, then merges behind a progress dialog.
Future<void> _merge(
  BuildContext context,
  ConversationSummary chat,
  HistoryController controller,
  Future<bool> Function(String id, String otherId) onMerge,
  ValueChanged<bool> onMerged,
) async {
  final other = await showMergePicker(
    context,
    exclude: chat.id,
    search: controller.find,
  );
  if (other == null || !context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => ChatConfirmDialog(
      title: LineageStrings.mergeTitle,
      confirm: LineageStrings.merge,
      onConfirm: () => Navigator.pop(dialog, true),
      child: Text(LineageStrings.mergeBody, style: dialog.text.bodySmall),
    ),
  );
  if (ok != true || !context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(canPop: false, child: _Progress()),
    ),
  );
  final merged = await onMerge(chat.id, other.id);
  navigator.pop();
  onMerged(merged);
}

Future<void> _delete(
  BuildContext context,
  ConversationSummary chat,
  HistoryController controller,
  ValueChanged<String> onDeleted,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => ChatConfirmDialog(
      title: AppStrings.deleteChatTitle,
      confirm: AppStrings.deleteChat,
      destructive: true,
      onConfirm: () => Navigator.pop(dialog, true),
      child: Text(AppStrings.deleteChatBody, style: dialog.text.bodySmall),
    ),
  );
  if (ok != true) return;
  if (await controller.delete(chat.id)) {
    Haptics.received();
    onDeleted(chat.id);
  } else {
    Haptics.error();
  }
}

/// Asks before deleting [count] picked chats (and their files).
Future<bool> confirmDeleteChats(BuildContext context, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => ChatConfirmDialog(
      title: ChatCleanupStrings.deleteTitle(count),
      confirm: ChatCleanupStrings.delete,
      destructive: true,
      onConfirm: () => Navigator.pop(dialog, true),
      child: Text(ChatCleanupStrings.deleteBody, style: dialog.text.bodySmall),
    ),
  );
  return ok == true;
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => SettingsTile(
    icon: icon,
    title: sentenceCase(label),
    iconColor: color,
    titleColor: color,
    onTap: onTap,
  );
}

/// MERGING with a spinner, shown while the briefing is written.
class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) {
    return M3Themed(
      child: Builder(
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              SizedBox.square(
                dimension: LineageSizes.progress,
                child: CircularProgressIndicator(
                  strokeWidth: AppBorder.thick,
                  color: context.palette.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Text(
                sentenceCase(LineageStrings.merging),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Material 3 confirm dialog with CANCEL and a (red, when [destructive])
/// confirm button.
class ChatConfirmDialog extends StatelessWidget {
  const ChatConfirmDialog({
    super.key,
    required this.title,
    required this.confirm,
    required this.onConfirm,
    required this.child,
    this.destructive = false,
  });

  final String title;
  final String confirm;
  final VoidCallback onConfirm;
  final Widget child;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return M3Themed(
      child: Builder(
        builder: (context) {
          final p = context.palette;
          return AlertDialog(
            title: Text(sentenceCase(title)),
            content: child,
            actions: [
              TextButton(
                onPressed: () {
                  Haptics.tap();
                  Navigator.pop(context);
                },
                child: Text(sentenceCase(AppStrings.cancel)),
              ),
              FilledButton(
                // The theme's buttons are full-width; dialog actions hug.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, ChatCleanupSizes.dialogAction),
                  backgroundColor: destructive ? p.accent : null,
                  foregroundColor: destructive ? Colors.white : null,
                ),
                onPressed: () {
                  Haptics.tap();
                  onConfirm();
                },
                child: Text(sentenceCase(confirm)),
              ),
            ],
          );
        },
      ),
    );
  }
}
