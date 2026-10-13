import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/physics.dart';

/// A grid of damped springs coupled to their neighbours: a tiny membrane.
///
/// Every cell has a displacement [h] and a velocity [v] and is pulled towards
/// its own [target] by a spring. Neighbours pull on each other (a discrete
/// wave equation), so a kick anywhere spreads as a ring that overshoots,
/// interferes with other rings and settles. Integration is semi-implicit
/// Euler at a fixed timestep (stable and frame-rate independent); the state
/// lives in [Float32List]s that are only reallocated when the grid resizes,
/// so a frame allocates nothing.
class SpringField {
  SpringField({
    required SpringDescription spring,
    required this.coupling,
    required this.timestep,
    required this.maxSubsteps,
    required this.limit,
  }) : stiffness = spring.stiffness / spring.mass,
       damping = spring.damping / spring.mass;

  /// Pull towards the target (per unit mass), 1/s².
  final double stiffness;

  /// Velocity damping (per unit mass), 1/s.
  final double damping;

  /// Neighbour coupling: wave speed squared, in cells² per s².
  final double coupling;

  /// The fixed integration step (s) and the most steps one frame may take
  /// (a longer gap is dropped rather than simulated).
  final double timestep;
  final int maxSubsteps;

  /// Displacements are clamped to ±[limit] so no input can blow it up.
  final double limit;

  int cols = 0, rows = 0;
  Float32List h = Float32List(0);
  Float32List v = Float32List(0);
  Float32List target = Float32List(0);
  Float32List _accel = Float32List(0);
  double _carry = 0;

  int get length => cols * rows;

  /// Resizes the grid (state resets) when the cell count changes.
  void resize(int cols, int rows) {
    if (cols == this.cols && rows == this.rows) return;
    this.cols = cols;
    this.rows = rows;
    final n = cols * rows;
    h = Float32List(n);
    v = Float32List(n);
    target = Float32List(n);
    _accel = Float32List(n);
    _carry = 0;
  }

  /// Every cell at rest on its target.
  void settle() {
    h.setAll(0, target);
    v.fillRange(0, v.length, 0);
    _carry = 0;
  }

  /// Every cell at rest at zero.
  void clear() {
    h.fillRange(0, h.length, 0);
    v.fillRange(0, v.length, 0);
    _carry = 0;
  }

  /// Adds [dv] to the velocity of cell ([col], [row]).
  void kick(int col, int row, double dv) {
    if (col < 0 || row < 0 || col >= cols || row >= rows) return;
    v[row * cols + col] += dv;
  }

  /// A round impulse centred at ([col], [row]) (cell units, fractional):
  /// velocity [strength] at the centre with a Gaussian of [sigma] cells.
  void kickRadial(double col, double row, double strength, double sigma) {
    final reach = (sigma * 3).ceil();
    final c0 = math.max(0, col.round() - reach);
    final c1 = math.min(cols - 1, col.round() + reach);
    final r0 = math.max(0, row.round() - reach);
    final r1 = math.min(rows - 1, row.round() + reach);
    final inv = 1 / (sigma * sigma);
    for (var r = r0; r <= r1; r++) {
      final dr = r - row;
      for (var c = c0; c <= c1; c++) {
        final dc = c - col;
        v[r * cols + c] += strength * math.exp(-(dc * dc + dr * dr) * inv);
      }
    }
  }

  /// Moves the simulation on by [dt] seconds in fixed steps. [beforeStep]
  /// runs before each step with that step's offset into [dt] (s), for
  /// forces that move during the frame. Returns the number of steps taken.
  int advance(double dt, [void Function(double offset)? beforeStep]) {
    _carry += dt;
    var steps = (_carry / timestep).floor();
    if (steps > maxSubsteps) {
      steps = maxSubsteps;
      _carry = 0;
    } else {
      _carry -= steps * timestep;
    }
    for (var s = 0; s < steps; s++) {
      beforeStep?.call(s * timestep);
      _step(timestep);
    }
    return steps;
  }

  /// Sum of squared velocities: how much the field is still moving.
  double get kinetic {
    var sum = 0.0;
    for (var i = 0; i < v.length; i++) {
      sum += v[i] * v[i];
    }
    return sum;
  }

  void _step(double dt) {
    final w = cols, n = length;
    if (n == 0) return;
    final h = this.h, v = this.v, tgt = target, a = _accel;
    final k = stiffness, d = damping, c2 = coupling;
    // Accelerations first (all from the same h), then velocities and
    // positions: semi-implicit Euler. Edges mirror (no energy leaks out of
    // the sides; the top and bottom reflect softly).
    for (var r = 0; r < rows; r++) {
      final row = r * w;
      final up = r == 0 ? row : row - w;
      final down = r == rows - 1 ? row : row + w;
      for (var c = 0; c < w; c++) {
        final i = row + c;
        final hi = h[i];
        final left = c == 0 ? hi : h[i - 1];
        final right = c == w - 1 ? hi : h[i + 1];
        final lap = left + right + h[up + c] + h[down + c] - 4 * hi;
        a[i] = c2 * lap + k * (tgt[i] - hi) - d * v[i];
      }
    }
    final lim = limit;
    for (var i = 0; i < n; i++) {
      final vi = v[i] + a[i] * dt;
      v[i] = vi;
      final hi = h[i] + vi * dt;
      h[i] = hi > lim ? lim : (hi < -lim ? -lim : hi);
    }
  }
}
