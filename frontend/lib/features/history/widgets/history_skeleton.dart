import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/history.dart';
import '../../../core/theme/app_palette.dart';

/// Placeholder rows drawn as dot-matrix bars with a light sweeping across
/// them. Static when the system asks for reduced motion.
class HistorySkeleton extends StatefulWidget {
  const HistorySkeleton({super.key});

  /// Bar lengths as a fraction of the width, repeated down the list.
  static const widths = [0.62, 0.8, 0.5, 0.7, 0.88, 0.45, 0.74, 0.58, 0.66];

  @override
  State<HistorySkeleton> createState() => _HistorySkeletonState();
}

class _HistorySkeletonState extends State<HistorySkeleton>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: HistoryDurations.shimmer,
  );
  bool? _reduce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reduce) return;
    _reduce = reduce;
    if (reduce) {
      _c.stop();
    } else {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: HistoryStrings.loading,
      liveRegion: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _SkeletonPainter(
              progress: _c,
              base: p.border,
              glow: p.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter({
    required this.progress,
    required this.base,
    required this.glow,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color base, glow;

  static const _bandWidth = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    const step = HistorySizes.dotSize + HistorySizes.dotGap;
    const rowsOfDots = 3;
    const pad = AppSpacing.screenPadding + HistorySizes.rowInset;
    final usable = size.width - pad * 2;
    if (usable <= 0) return;
    final sweep = progress.value * (1 + _bandWidth * 2) - _bandWidth;
    final basePoints = <Offset>[];
    final glowPoints = <Offset>[];
    for (var i = 0; i < HistorySizes.skeletonRows; i++) {
      final top =
          i * HistorySizes.rowHeight +
          (HistorySizes.rowHeight - step * (rowsOfDots - 1)) / 2;
      final length =
          usable * HistorySkeleton.widths[i % HistorySkeleton.widths.length];
      for (var x = 0.0; x <= length; x += step) {
        final at = (pad + x) / size.width;
        final lit = (at - sweep).abs() < _bandWidth / 2;
        for (var r = 0; r < rowsOfDots; r++) {
          (lit ? glowPoints : basePoints).add(Offset(pad + x, top + r * step));
        }
      }
    }
    Paint dots(Color c) => Paint()
      ..color = c
      ..strokeWidth = HistorySizes.dotSize
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(ui.PointMode.points, basePoints, dots(base));
    canvas.drawPoints(
      ui.PointMode.points,
      glowPoints,
      dots(glow.withValues(alpha: 0.55)),
    );
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      base != old.base || glow != old.glow;
}
