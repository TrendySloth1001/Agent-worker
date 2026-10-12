import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../constants/mascot.dart';
import '../theme/app_palette.dart';

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

  /// The Lottie file that plays for this state.
  String get asset => switch (this) {
    idle => MascotAssets.idle,
    thinking => MascotAssets.thinking,
    writing => MascotAssets.writing,
    searching => MascotAssets.searching,
    celebrating => MascotAssets.celebrating,
    sleeping => MascotAssets.sleeping,
    error => MascotAssets.error,
    offline => MascotAssets.offline,
    github => MascotAssets.code,
  };

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

/// Sparky: a Noto Animated Emoji (Lottie) per state on a tonal disc with a
/// dot-ring halo. Compositions are cached by the lottie package, so a state
/// loads once. Changing state cross-fades. With animations disabled it shows
/// the first frame only, and it stops whenever its route is hidden (the
/// Lottie controller is muted by [TickerMode]).
class Mascot extends StatelessWidget {
  const Mascot({
    super.key,
    required this.state,
    this.size = MascotSizes.medium,
    this.semanticLabel,
  });

  final MascotState state;

  /// Width and height in logical pixels.
  final double size;

  /// Spoken label; defaults to the state's description.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: semanticLabel ?? state.label,
      image: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _HaloPainter(
                disc: p.surfaceRaised.withValues(
                  alpha: p.surfaceRaised.a * MascotLayout.discAlpha,
                ),
                dots: p.border.withValues(
                  alpha: p.border.a * MascotLayout.haloAlpha,
                ),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: still ? Duration.zero : MascotLayout.crossFade,
                  child: SizedBox.square(
                    key: ValueKey(state),
                    dimension: size * MascotLayout.emojiShare,
                    child: Lottie.asset(
                      state.asset,
                      animate: !still,
                      repeat: true,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  const _HaloPainter({required this.disc, required this.dots});

  final Color disc, dots;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      size.width * MascotLayout.discShare / 2,
      Paint()..color = disc,
    );
    final ring = size.width * MascotLayout.haloRingShare;
    final r = size.width * MascotLayout.haloDotRadius;
    final paint = Paint()..color = dots;
    for (var i = 0; i < MascotLayout.haloDots; i++) {
      final a = 2 * math.pi * i / MascotLayout.haloDots;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * ring, r, paint);
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.disc != disc || old.dots != dots;
}
