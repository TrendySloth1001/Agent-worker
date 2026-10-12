import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/docs.dart';
import '../../../core/constants/share_export.dart';
import '../../../core/haptics.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../settings/widgets/settings_kit.dart';

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
  final action = await showM3Sheet<String>(
    context,
    builder: (sheet) => M3ActionSheet(
      rows: [
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
  final action = await showM3Sheet<String>(
    context,
    builder: (sheet) => M3ActionSheet(
      rows: [
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
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SettingsTile(
        icon: icon,
        title: sentenceCase(label),
        summary: subtitle == null ? null : sentenceCase(subtitle!),
        onTap: onTap,
      ),
    );
  }
}
