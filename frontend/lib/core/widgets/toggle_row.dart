import 'package:flutter/material.dart';

import '../constants/app_icons.dart';
import '../constants/app_sizes.dart';
import '../haptics.dart';
import '../theme/app_palette.dart';
import 'app_icon.dart';

/// Label on the left, flat switch on the right.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });

  final String label;

  /// Optional one-line helper under the label.
  final String? subtitle;
  final AppIconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onChanged(!value);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.rowHeight),
        child: Row(
          children: [
            if (icon != null) ...[
              AppIcon(icon!, size: AppIconSize.sm, color: p.textSecondary),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.label),
                    if (subtitle != null)
                      Text(subtitle!, style: context.text.caption),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AnimatedContainer(
              duration: AppDurations.fast,
              width: AppSizes.toggleWidth,
              height: AppSizes.toggleHeight,
              padding: const EdgeInsets.all(AppSpacing.xs),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                color: value ? p.accent : Colors.transparent,
                border: Border.all(
                  color: value ? p.accent : p.borderStrong,
                  width: AppBorder.thin,
                ),
              ),
              child: Container(
                width: AppSizes.toggleKnob,
                height: AppSizes.toggleKnob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? p.textInverse : p.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
