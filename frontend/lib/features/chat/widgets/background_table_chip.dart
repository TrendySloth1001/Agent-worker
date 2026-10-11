import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';

/// "1 ROUND TABLE RUNNING": a table still working in a chat that is not on
/// screen. Tap to go back to it.
class BackgroundTableChip extends StatelessWidget {
  const BackgroundTableChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: BackgroundTableStrings.open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: Center(
          child: Container(
            height: BackgroundTableSizes.chipHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: BackgroundTableSizes.chipPadH,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: p.borderStrong, width: AppBorder.thin),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Pulse(),
                const SizedBox(width: AppSpacing.sm),
                AppIcon(
                  AppIcons.roundTable,
                  size: AppIconSize.sm,
                  color: p.textPrimary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    BackgroundTableStrings.running(1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption.copyWith(color: p.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent dot fading in and out while the table works.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: TableSizes.pulse)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: TableSizes.pulseMinOpacity, end: 1.0).animate(_c),
    child: Container(
      width: BackgroundTableSizes.dot,
      height: BackgroundTableSizes.dot,
      decoration: BoxDecoration(
        color: context.palette.accent,
        shape: BoxShape.circle,
      ),
    ),
  );
}
