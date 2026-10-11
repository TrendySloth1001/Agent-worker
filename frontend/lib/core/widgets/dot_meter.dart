import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../theme/app_palette.dart';

/// Row of dots; [fraction] of them are lit. Dot-matrix quota bar.
class DotMeter extends StatelessWidget {
  const DotMeter({super.key, required this.fraction, this.litColor});

  final double fraction;

  /// Color of lit dots. Defaults to the accent.
  final Color? litColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lit = (fraction.clamp(0.0, 1.0) * AppSizes.quotaDotCount).round();
    return Row(
      children: [
        for (var i = 0; i < AppSizes.quotaDotCount; i++)
          Expanded(
            child: Center(
              child: Container(
                width: AppSizes.quotaDot,
                height: AppSizes.quotaDot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < lit ? (litColor ?? p.accent) : p.border,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
