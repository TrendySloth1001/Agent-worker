import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';

/// Small bottom sheet: a caption and one row per option. Returns the
/// picked value, or null when dismissed. Callers give the opening haptic.
Future<T?> showShareSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, AppIconData, String)> options,
}) {
  final p = context.palette;
  return showModalBottomSheet<T>(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.lg,
              AppSpacing.screenPadding,
              AppSpacing.sm,
            ),
            child: Text(title, style: sheet.text.caption),
          ),
          for (final (value, icon, label) in options)
            InkWell(
              onTap: () {
                Haptics.tap();
                Navigator.pop(sheet, value);
              },
              child: Container(
                height: AppSizes.sheetOptionHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.border)),
                ),
                child: Row(
                  children: [
                    AppIcon(icon, size: AppIconSize.md, color: p.textSecondary),
                    const SizedBox(width: AppSpacing.md),
                    Text(label, style: sheet.text.label),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
