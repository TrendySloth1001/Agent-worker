import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../theme/app_palette.dart';

/// Nothing-style dot matrix filling the background.
class DotGridBackground extends StatelessWidget {
  const DotGridBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DotGridPainter(context.palette.dotGrid),
        size: Size.infinite,
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const step = AppSizes.dotGridSpacing;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), AppSizes.dotGridRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => oldDelegate.color != color;
}
