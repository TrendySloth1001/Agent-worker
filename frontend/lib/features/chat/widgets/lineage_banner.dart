import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/icon_label.dart';

/// Top of a forked chat: FORKED FROM and the parent title; tap opens it.
class LineageBanner extends StatelessWidget {
  const LineageBanner({
    super.key,
    required this.parentId,
    required this.parentTitle,
    required this.onOpen,
  });

  /// Null when the parent was deleted.
  final String? parentId;
  final String? parentTitle;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final id = parentId;
    final text = id == null
        ? LineageStrings.forkedFromDeleted
        : '${LineageStrings.forkedFrom} '
              '${(parentTitle ?? AppStrings.untitled).toUpperCase()}';
    return Center(
      child: Semantics(
        button: id != null,
        label: text,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: id == null
              ? null
              : () {
                  Haptics.tap();
                  onOpen(id);
                },
          child: Container(
            height: AppSizes.chipHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.chipHorizontalPadding,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: id == null ? p.border : p.borderStrong,
                width: AppBorder.thin,
              ),
            ),
            child: IconLabel(
              icon: AppIcons.fork,
              text: text,
              style: context.text.caption,
              color: id == null ? p.textTertiary : p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
