import 'package:flutter/material.dart';

import '../constants/mascot.dart';
import '../theme/app_palette.dart';
import 'mascot_frame.dart';

/// What sparky is doing. Pick the one that matches the screen.
enum MascotState {
  idle(MascotStrings.idle),
  thinking(MascotStrings.thinking),
  writing(MascotStrings.writing),
  searching(MascotStrings.searching),
  celebrating(MascotStrings.celebrating),
  sleeping(MascotStrings.sleeping),
  error(MascotStrings.error),
  offline(MascotStrings.offline),

  /// Code and branches, for the GitHub screens.
  github(MascotStrings.github);

  const MascotState(this.label);

  final String label;

  /// The mascot for a live Round Table phase.
  static MascotState forTablePhase(String? phase) => switch (phase) {
    'researching' => searching,
    'drafting' || 'synthesizing' => writing,
    _ => thinking,
  };

  /// The mascot for a doc pipeline status or progress phase.
  static MascotState forDocPhase(String phase) => switch (phase) {
    'research' || 'researching' => searching,
    'sections' || 'writing' => writing,
    'finish' || 'finishing' => celebrating,
    _ => thinking,
  };
}

/// Sparky, a dot-matrix robot painted in code from the theme palette (ink
/// dots plus a red accent), so it follows light and dark with no assets.
///
/// Animates in a 4 second loop. With animations disabled it shows one still
/// frame, and it stops whenever its route is hidden (the ticker is muted by
/// [TickerMode]).
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    required this.state,
    this.size = MascotSizes.medium,
    this.semanticLabel,
  });

  final MascotState state;

  /// Width in logical pixels; the height follows the grid.
  final double size;

  /// Spoken label; defaults to the state's description.
  final String? semanticLabel;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1) * MascotGrid.loopSeconds.toInt(),
  );
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final height = widget.size * MascotGrid.rows / MascotGrid.cols;
    return Semantics(
      label: widget.semanticLabel ?? widget.state.label,
      image: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(widget.size, height),
            painter: _MascotPainter(
              state: widget.state,
              progress: _loop,
              still: _still,
              ink: p.textPrimary,
              accent: p.accent,
              faint: p.border,
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.state,
    required this.progress,
    required this.still,
    required this.ink,
    required this.accent,
    required this.faint,
  }) : super(repaint: progress);

  final MascotState state;
  final Animation<double> progress;
  final bool still;
  final Color ink, accent, faint;

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = still
        ? MascotGrid.stillAt
        : progress.value * MascotGrid.loopSeconds;
    final frame = buildMascotFrame(state, seconds);
    final cell = size.width / MascotGrid.cols;
    final radius = cell * MascotGrid.dotRadius;
    final paint = Paint();
    for (var r = 0; r < MascotGrid.rows; r++) {
      for (var c = 0; c < MascotGrid.cols; c++) {
        final dot = frame.at(c, r);
        final center = Offset((c + 0.5) * cell, (r + 0.5) * cell);
        if (dot == null) {
          final a = MascotFrame.inHead(c, r)
              ? MascotGrid.faintInside
              : MascotGrid.faintOutside;
          paint.color = faint.withValues(alpha: faint.a * a);
        } else {
          final base = dot.accent ? accent : ink;
          paint.color = base.withValues(alpha: base.a * dot.a);
        }
        canvas.drawCircle(center, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.state != state ||
      old.still != still ||
      old.ink != ink ||
      old.accent != accent ||
      old.faint != faint;
}
