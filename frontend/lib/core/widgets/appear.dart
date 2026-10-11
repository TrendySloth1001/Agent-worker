import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';

/// Fades and slides its child up once when first built.
class Appear extends StatelessWidget {
  const Appear({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.slow,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * AppSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}
