import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';

/// Long-press menu for a user message: FORK FROM HERE (when [onForkHere]
/// is set) and COPY.
Future<void> showUserMessageActions(
  BuildContext context, {
  required String text,
  VoidCallback? onForkHere,
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
  if (action == LineageStrings.forkFromHere) onForkHere?.call();
  if (action == AppStrings.copy) {
    await Clipboard.setData(ClipboardData(text: text));
    Haptics.received();
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.icon, required this.onTap});

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              AppIcon(
                icon,
                size: AppIconSize.md,
                color: context.palette.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: context.text.label),
            ],
          ),
        ),
      ),
    );
  }
}
