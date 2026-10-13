import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// The app's motion language: damped springs instead of fixed curves.
///
/// A spring is described by its natural period (how long one swing takes)
/// and its damping ratio (1 = no overshoot, lower = more bounce). The same
/// numbers drive the dot-matrix backdrop's field and any widget entrance, so
/// everything moves with one physical feel.
abstract final class AppSprings {
  /// Quick, barely-bouncing: chips, toggles, small reveals.
  static final snappy = spring(period: 0.32, damping: 0.86);

  /// The signature entrance: a visible overshoot that settles fast (the
  /// assistant pill and sheet).
  static final pop = spring(period: 0.42, damping: 0.68);

  /// Slow and soft: large surfaces and backdrops.
  static final gentle = spring(period: 0.6, damping: 0.92);

  /// Where an entrance starts (a fraction of the widget's own size) and the
  /// scale it grows from (see `SpringIn`).
  static const entranceOffset = Offset(0, 0.12);
  static const entranceScale = 0.96;

  /// A unit-mass spring with this natural [period] (seconds) and [damping]
  /// ratio.
  static SpringDescription spring({
    required double period,
    required double damping,
  }) {
    final k = stiffnessFor(period);
    return SpringDescription(
      mass: 1,
      stiffness: k,
      damping: dampingFor(k, damping),
    );
  }

  /// Stiffness of a unit-mass spring that swings once every [period] seconds.
  static double stiffnessFor(double period) {
    final w = 2 * math.pi / period;
    return w * w;
  }

  /// Damping coefficient of a unit-mass spring with stiffness [k] and the
  /// given damping [ratio].
  static double dampingFor(double k, double ratio) => 2 * ratio * math.sqrt(k);

  /// How long [spring] takes to settle within [tolerance] of its target
  /// (from rest at 0 to 1): use it as the duration of a [SpringCurve].
  static Duration settleTime(
    SpringDescription spring, {
    double tolerance = 0.002,
  }) {
    final zeta = spring.damping / (2 * math.sqrt(spring.stiffness));
    final w = math.sqrt(spring.stiffness / spring.mass);
    // The envelope e^(-zeta w t) reaches the tolerance.
    final t = -math.log(tolerance) / (math.min(zeta, 1) * w);
    return Duration(microseconds: (t * Duration.microsecondsPerSecond).ceil());
  }
}

/// A [Curve] that follows a spring from 0 to 1, overshoot included, so any
/// implicit animation (`AnimatedScale`, `AnimatedSlide`, `TweenAnimationBuilder`)
/// can move like a spring. Pair it with [AppSprings.settleTime] as the
/// duration.
class SpringCurve extends Curve {
  SpringCurve(this.spring)
    : _duration =
          AppSprings.settleTime(spring).inMicroseconds /
          Duration.microsecondsPerSecond;

  final SpringDescription spring;
  final double _duration;

  late final _sim = SpringSimulation(spring, 0, 1, 0);

  @override
  double transformInternal(double t) => _sim.x(t * _duration);
}
