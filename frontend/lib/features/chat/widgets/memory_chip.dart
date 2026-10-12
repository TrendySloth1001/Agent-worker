import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/memory.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/icon_label.dart';
import '../../memory/memory_screen.dart';

/// Subtle "memory updated" chip under a reply that saved or forgot something;
/// tap to open the Memory screen.
class MemoryChip extends StatelessWidget {
  const MemoryChip({super.key, required this.ops});

  /// ADD, UPDATE or DELETE per change.
  final List<String> ops;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final onlyForgot = ops.every((o) => o == 'DELETE');
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => MemoryScreen.open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: p.border, width: AppBorder.thin),
          ),
          child: IconLabel(
            icon: MemoryIcons.chip,
            text: onlyForgot
                ? MemoryStrings.forgotChip
                : MemoryStrings.updatedChip,
            style: context.text.caption,
            color: p.textTertiary,
          ),
        ),
      ),
    );
  }
}
