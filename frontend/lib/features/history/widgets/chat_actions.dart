import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/conversation.dart';
import '../history_controller.dart';
import 'merge_picker.dart';

/// Long-press menu for a conversation: pin, archive, fork, merge, rename or
/// delete. Calls [onRenamed] / [onDeleted] after the server accepted the
/// change. [onFork] duplicates the chat and opens the copy. [onMerge] merges
/// it with another and opens the result; [onMerged] gets its outcome once the
/// progress dialog has closed.
Future<void> showChatActions(
  BuildContext context, {
  required ConversationSummary chat,
  required HistoryController controller,
  required void Function(String id, String title) onRenamed,
  required ValueChanged<String> onDeleted,
  required Future<bool> Function(ConversationSummary chat) onFork,
  required Future<bool> Function(String id, String otherId) onMerge,
  required ValueChanged<bool> onMerged,
}) async {
  Haptics.tap();
  final p = context.palette;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          _SheetRow(
            label: AppStrings.rename,
            icon: AppIcons.edit,
            onTap: () => Navigator.pop(sheet, AppStrings.rename),
          ),
          Divider(color: p.border),
          _SheetRow(
            label: AppStrings.deleteChat,
            icon: AppIcons.delete,
            color: p.accent,
            onTap: () => Navigator.pop(sheet, AppStrings.deleteChat),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == AppStrings.pinChat) {
    final ok = await controller.setPinned(chat.id, !chat.pinned);
    ok ? Haptics.received() : Haptics.error();
    return;
  }
  if (action == AppStrings.archiveChat) {
    await _archive(context, chat, controller);
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
  if (action == AppStrings.rename) {
    await _rename(context, chat, controller, onRenamed);
  }
  if (!context.mounted) return;
  if (action == AppStrings.deleteChat) {
    await _delete(context, chat, controller, onDeleted);
  }
}

/// Archives or restores, with an UNDO on the notice.
Future<void> _archive(
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
    builder: (dialog) => _Dialog(
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

Future<void> _rename(
  BuildContext context,
  ConversationSummary chat,
  HistoryController controller,
  void Function(String id, String title) onRenamed,
) async {
  final field = TextEditingController(text: chat.title ?? '');
  final title = await showDialog<String>(
    context: context,
    builder: (dialog) => _Dialog(
      title: AppStrings.rename,
      confirm: AppStrings.save,
      onConfirm: () => Navigator.pop(dialog, field.text.trim()),
      child: TextField(
        controller: field,
        autofocus: true,
        maxLength: 120,
        style: dialog.text.body,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: AppStrings.renameHint,
          counterText: '',
        ),
        onSubmitted: (v) => Navigator.pop(dialog, v.trim()),
      ),
    ),
  );
  field.dispose();
  if (title == null || title.isEmpty || title == chat.title) return;
  final updated = await controller.rename(chat.id, title);
  if (updated != null) {
    Haptics.received();
    onRenamed(chat.id, updated.title ?? title);
  } else {
    Haptics.error();
  }
}

Future<void> _delete(
  BuildContext context,
  ConversationSummary chat,
  HistoryController controller,
  ValueChanged<String> onDeleted,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => _Dialog(
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
  Widget build(BuildContext context) {
    final c = color ?? context.palette.textSecondary;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: SizedBox(
          height: AppSizes.rowHeight,
          child: Row(
            children: [
              AppIcon(icon, size: AppIconSize.md, color: c),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: context.text.label.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// MERGING with a thin spinner, shown while the briefing is written.
class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      backgroundColor: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: p.border),
      ),
      content: Row(
        children: [
          SizedBox.square(
            dimension: LineageSizes.progress,
            child: CircularProgressIndicator(
              strokeWidth: AppBorder.thin,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(LineageStrings.merging, style: context.text.caption),
        ],
      ),
    );
  }
}

class _Dialog extends StatelessWidget {
  const _Dialog({
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
    final p = context.palette;
    return AlertDialog(
      backgroundColor: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: p.border),
      ),
      title: Text(title, style: context.text.label),
      content: child,
      actions: [
        TextButton(
          onPressed: () {
            Haptics.tap();
            Navigator.pop(context);
          },
          child: Text(AppStrings.cancel, style: context.text.caption),
        ),
        TextButton(
          onPressed: () {
            Haptics.tap();
            onConfirm();
          },
          child: Text(
            confirm,
            style: context.text.caption.copyWith(
              color: destructive ? p.accent : p.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
