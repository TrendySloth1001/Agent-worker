import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/docs.dart';
import '../../../core/constants/share_export.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';

/// Long-press menu for a user message: EDIT (greyed out while [onEdit] is
/// null, i.e. a reply is streaming), FORK FROM HERE (when [onForkHere] is
/// set) and COPY.
Future<void> showUserMessageActions(
  BuildContext context, {
  required String text,
  VoidCallback? onForkHere,
  VoidCallback? onEdit,
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
          _Row(
            label: EditStrings.edit,
            icon: AppIcons.edit,
            subtitle: onEdit == null
                ? EditStrings.busyHint
                : EditStrings.editHint,
            onTap: onEdit == null
                ? null
                : () => Navigator.pop(sheet, EditStrings.edit),
          ),
          if (onForkHere != null)
            _Row(
              label: LineageStrings.forkFromHere,
              icon: AppIcons.fork,
              onTap: () => Navigator.pop(sheet, LineageStrings.forkFromHere),
            ),
          _Row(
            label: AppStrings.copy,
            icon: AppIcons.copy,
            onTap: () => Navigator.pop(sheet, AppStrings.copy),
          ),
        ],
      ),
    ),
  );
  if (action == EditStrings.edit) onEdit?.call();
  if (action == LineageStrings.forkFromHere) onForkHere?.call();
  if (action == AppStrings.copy) {
    await Clipboard.setData(ClipboardData(text: text));
    Haptics.received();
  }
}

/// Long-press menu for a reply: TURN INTO DOC (long replies, when
/// [onTurnIntoDoc] is set) and COPY.
Future<void> showReplyActions(
  BuildContext context, {
  required String text,
  VoidCallback? onTurnIntoDoc,
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
          if (onTurnIntoDoc != null)
            _Row(
              label: DocStrings.turnIntoDoc,
              icon: AppIcons.doc,
              subtitle: DocStrings.turnIntoDocHint,
              onTap: () => Navigator.pop(sheet, DocStrings.turnIntoDoc),
            ),
          _Row(
            label: AppStrings.copy,
            icon: AppIcons.copy,
            onTap: () => Navigator.pop(sheet, AppStrings.copy),
          ),
        ],
      ),
    ),
  );
  if (action == DocStrings.turnIntoDoc) onTurnIntoDoc?.call();
  if (action == AppStrings.copy) {
    await Clipboard.setData(ClipboardData(text: text));
    Haptics.received();
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final AppIconData icon;

  /// Null shows the row greyed out.
  final VoidCallback? onTap;

  /// Small caption under the label.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    return InkWell(
      onTap: enabled
          ? () {
              Haptics.tap();
              onTap!();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: SizedBox(
          height: AppSizes.rowHeight,
          child: Row(
            children: [
              AppIcon(
                icon,
                size: AppIconSize.md,
                color: enabled ? p.textSecondary : p.textTertiary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: context.text.label.copyWith(
                        color: enabled ? null : p.textTertiary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: context.text.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
