import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';

/// Three dots that light up in turn, like a dot-matrix display.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key, this.label = AppStrings.thinking});

  final String label;

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppDurations.slow * 3,
  );

  @override
  void initState() {
    super.initState();
    // A soft tick each time the dots start a new cycle.
    _controller
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          Haptics.tick();
          _controller.forward(from: 0);
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final active = (_controller.value * 3).floor();
            return Row(
              children: List.generate(3, (i) {
                return Container(
                  width: AppSizes.thinkingDot,
                  height: AppSizes.thinkingDot,
                  margin: const EdgeInsets.only(right: AppSpacing.xs),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == active
                        ? context.palette.accent
                        : context.palette.borderStrong,
                  ),
                );
              }),
            );
          },
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          widget.label,
          style: context.text.caption.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
      ],
    );
  }
}
