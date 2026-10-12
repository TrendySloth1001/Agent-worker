import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/icon_label.dart';

/// The composer's toggles (WEB / KB / TABLE / DOC), also in the assistant
/// overlay.
/// Small toggle pill: filled when on, outlined when off.
class SmartChip extends StatelessWidget {
  const SmartChip({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.hint,
    this.dim = false,
    this.height = AppSizes.chipHeight,
  });

  final String label;
  final AppIconData icon;
  final bool active;
  final VoidCallback onTap;

  /// Small state word after the label (WEB: AUTO / OFF).
  final String? hint;

  /// Shown muted: the tool is off.
  final bool dim;

  /// Smaller in the assistant overlay.
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: height,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.chipHorizontalPadding,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: active ? p.textPrimary : Colors.transparent,
          border: Border.all(
            color: active ? p.textPrimary : p.borderStrong,
            width: AppBorder.thin,
          ),
        ),
        child: IconLabel(
          icon: icon,
          text: hint == null ? label : '$label $hint',
          style: context.text.caption,
          color: active
              ? p.textInverse
              : dim
              ? p.textTertiary
              : p.textSecondary,
        ),
      ),
    );
  }
}
