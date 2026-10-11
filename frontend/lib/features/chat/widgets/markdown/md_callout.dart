import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'md_blocks.dart';

/// GitHub alert (`> [!NOTE]`): a card with a left bar, icon and label.
class MdCallout extends StatelessWidget {
  const MdCallout({super.key, required this.block, required this.renderBody});

  final MdCalloutBlock block;
  final Widget Function(String text) renderBody;

  (String, AppIconData, bool) get _spec => switch (block.kind) {
    CalloutKind.note => (AppStrings.calloutNote, AppIcons.about, false),
    CalloutKind.tip => (AppStrings.calloutTip, AppIcons.tip, false),
    CalloutKind.important => (
      AppStrings.calloutImportant,
      AppIcons.alert,
      false,
    ),
    CalloutKind.warning => (AppStrings.calloutWarning, AppIcons.alert, true),
    CalloutKind.caution => (AppStrings.calloutCaution, AppIcons.alert, true),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, icon, hot) = _spec;
    final tone = hot ? p.accent : p.textPrimary;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MdSizes.calloutBar,
            child: ColoredBox(color: tone),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + MdSizes.calloutBar,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AppIcon(icon, size: AppIconSize.sm, color: tone),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      label,
                      style: context.text.label.copyWith(color: tone),
                    ),
                  ],
                ),
                if (block.body.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  renderBody(block.body),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
