import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_colors.dart';
import '../constants/dot_matrix.dart';
import '../motion/spring_field.dart';
import '../motion/springs.dart';
import '../theme/app_palette.dart';

/// What the backdrop's red energy layer is doing.
enum DotMatrixMode {
  /// A slow breathing glow along the bottom edge.
  idle,

  /// The glow follows the microphone level, with turbulence along the edge.
  listening,

  /// Travelling waves interfere along the bottom rows, a bright packet
  /// sweeping through them.
  thinking,

  /// A calmer version of the thinking waves while the answer streams in.
  streaming,
}

/// A Nothing-style dot matrix over a see-through veil: ink dots at low
/// opacity (black on light, white on dark) and a red energy layer in the
/// palette's accent that heats up to orange and (on dark) a white-hot core.
///
/// The energy is a field of coupled springs (one per dot): the opening wave
/// is an impulse front that rises, overshoots and settles; touching or
/// dragging over the backdrop sends ripples out from the finger (pointer
/// events are only observed, so taps still reach whatever is behind); the
/// microphone feeds turbulence along the bottom; thinking runs two
/// travelling waves through it that interfere. A new opening ([wave]
/// changes) replays the front.
///
/// One ticker drives everything and only repaints (no rebuilds, no widget
/// per dot), capped at 60 fps and dropping to 30 once idle and calm. Dots
/// are drawn in batched point calls, halos in one atlas call. With reduced
/// motion it paints one still, settled frame.
class DotMatrixBackdrop extends StatefulWidget {
  const DotMatrixBackdrop({
    super.key,
    this.mode = DotMatrixMode.idle,
    this.wave = 0,
    this.level,
    this.interactive = true,
  });

  final DotMatrixMode mode;

  /// Change it to replay the rising wave (e.g. on every new opening).
  final int wave;

  /// The microphone level (0..1), read every frame while listening.
  final ValueGetter<double>? level;

  /// Whether touches on the backdrop make ripples.
  final bool interactive;

  @override
  State<DotMatrixBackdrop> createState() => _DotMatrixBackdropState();
}

class _DotMatrixBackdropState extends State<DotMatrixBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _frame = DotMatrixFrame();
  final _cache = DotMatrixCache();
  bool _still = false;
  bool _restartWave = false;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _frame.setTargets(widget.mode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _still && (still || _ticker.isActive)) return;
    _still = still;
    if (still) {
      _ticker.stop();
      _frame.settle();
    } else if (!_ticker.isActive) {
      _restartWave = true;
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(DotMatrixBackdrop old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) {
      _frame.setTargets(widget.mode);
      if (_still) _frame.settle();
    }
    if (old.wave != widget.wave && !_still) _restartWave = true;
  }

  void _onTick(Duration elapsed) {
    final gap = elapsed - _last;
    final pace = _frame.calm
        ? DotMatrixDurations.calmFrame
        : DotMatrixDurations.frame;
    if (_last != Duration.zero &&
        !_restartWave &&
        gap < pace - DotMatrixDurations.frameSlack) {
      return; // 60 fps at most (30 when calm), whatever the display does.
    }
    _last = elapsed;
    final t = _seconds(elapsed);
    if (_restartWave) {
      _restartWave = false;
      _frame.startWave(t);
    }
    _frame.advance(t, _seconds(gap), widget.level?.call() ?? 0);
  }

  void _onDown(PointerDownEvent e) {
    if (!_still) _frame.touch(e.localPosition);
  }

  void _onMove(PointerMoveEvent e) {
    if (!_still) _frame.drag(e.localPosition, e.localDelta.distance);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: DotMatrixPainter(
          frame: _frame,
          palette: context.palette,
          cache: _cache,
        ),
      ),
    );
    if (!widget.interactive) return paint;
    // Only listens: the gesture arena (e.g. the overlay's tap to close)
    // still gets every pointer.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      child: paint,
    );
  }
}

/// A critically-ish damped spring on one value (mode cross-fades).
class _Blend {
  double x = 0, v = 0, target = 0;

  static final _k = AppSprings.stiffnessFor(DotMatrixPhysics.blendPeriod);
  static final _d = AppSprings.dampingFor(_k, DotMatrixPhysics.blendDamping);

  void step(double dt) {
    final a = _k * (target - x) - _d * v;
    v += a * dt;
    x += v * dt;
  }

  void snap() {
    x = target;
    v = 0;
  }
}

/// The animated state the painter reads: the spring field (one spring per
/// dot), the open front, the mode weights and the microphone level.
class DotMatrixFrame extends ChangeNotifier {
  DotMatrixFrame()
    : field = SpringField(
        spring: AppSprings.spring(
          period: DotMatrixPhysics.period,
          damping: DotMatrixPhysics.damping,
        ),
        coupling: DotMatrixPhysics.waveSpeed * DotMatrixPhysics.waveSpeed,
        timestep: DotMatrixPhysics.timestep,
        maxSubsteps: DotMatrixPhysics.maxSubsteps,
        limit: DotMatrixPhysics.limit,
      ),
      ripples = SpringField(
        spring: AppSprings.spring(
          period: DotMatrixPhysics.ripplePeriod,
          damping: DotMatrixPhysics.rippleDamping,
        ),
        coupling: DotMatrixPhysics.rippleSpeed * DotMatrixPhysics.rippleSpeed,
        timestep: DotMatrixPhysics.timestep,
        maxSubsteps: DotMatrixPhysics.maxSubsteps,
        limit: DotMatrixPhysics.limit,
      );

  /// The glow: stiff springs that chase their targets (the breathing, the
  /// thinking waves) and ring when the open front kicks them.
  final SpringField field;

  /// The membrane: loose springs, strongly coupled, so kicks (touches, the
  /// microphone) travel as rings. A dot's energy is `field.h + |ripples.h|`.
  final SpringField ripples;

  /// The energy of dot [i].
  double energy(int i) =>
      field.h[i] + ripples.h[i].abs() * DotMatrixPhysics.rippleGain;

  /// Seconds since the ticker started.
  double t = 0;

  /// When the latest open wave started (seconds); null = no wave.
  double? waveStart = 0;

  /// When the backdrop last opened (the idle glow calms down from it).
  double openedAt = 0;

  final _listen = _Blend(), _think = _Blend(), _stream = _Blend();

  /// Mode weights (about 0..1, springy).
  double get listen => _listen.x;
  double get think => _think.x;
  double get stream => _stream.x;

  /// The smoothed microphone level.
  double level = 0;

  /// True when the backdrop is idle and the field has settled: the widget
  /// then paces frames at the calm rate.
  bool calm = false;

  // ---- geometry (set by [layout]) ----
  Size? _size;
  int cols = 0, rows = 0;
  double originX = 0, originY = 0;

  /// Per cell: distance (dp) from the open front's centre (elliptical).
  Float32List _openDist = Float32List(0);

  /// Per column / per row scratch, reused every frame.
  Float32List _colX = Float32List(0);
  Float32List _colGlow = Float32List(0);
  Float32List _colHeight = Float32List(0);
  Float32List _colSweep = Float32List(0);
  Float32List _colSin1 = Float32List(0), _colCos1 = Float32List(0);
  Float32List _colSin2 = Float32List(0), _colCos2 = Float32List(0);
  Float32List _rowD = Float32List(0);
  Float32List _rowSin1 = Float32List(0), _rowCos1 = Float32List(0);
  Float32List _rowSin2 = Float32List(0), _rowCos2 = Float32List(0);
  Float32List _rowThink = Float32List(0);

  /// The open front's radius (dp) now and its reach.
  double _frontR = 0, _frontReach = 0;
  double _frontT0 = 0;

  /// Touches since the last frame: x, y, strength, sigma.
  final _touches = Float32List(DotMatrixSizes.touchQueue * 4);
  int _touchCount = 0;

  bool _pendingSettle = false;
  int _seed = 0x2545F491;

  bool get _waving => waveStart != null;

  void setTargets(DotMatrixMode mode) {
    _listen.target = mode == DotMatrixMode.listening ? 1.0 : 0.0;
    _think.target = mode == DotMatrixMode.thinking ? 1.0 : 0.0;
    _stream.target = mode == DotMatrixMode.streaming ? 1.0 : 0.0;
  }

  /// Replays the open front from time [now].
  void startWave(double now) {
    waveStart = now;
    openedAt = now;
    _frontR = 0;
    field.clear();
    ripples.clear();
  }

  /// Jumps to a settled still frame: no wave, every dot at rest on its
  /// target (the glow at a lively moment of its breathing).
  void settle() {
    _listen.snap();
    _think.snap();
    _stream.snap();
    waveStart = null;
    level = 0;
    t = DotMatrixSizes.stillTime;
    openedAt = t;
    _touchCount = 0;
    if (_size == null) {
      _pendingSettle = true;
    } else {
      _computeTargets();
      field.settle();
      ripples.clear();
    }
    notifyListeners();
  }

  /// A press at [p] (local dp): a round impulse under the finger.
  void touch(Offset p) =>
      _queue(p, DotMatrixSizes.touchKick, DotMatrixSizes.touchSigma);

  /// A drag through [p] that moved [distance] dp since the last event.
  void drag(Offset p, double distance) => _queue(
    p,
    DotMatrixSizes.dragKick * math.min(1.0, distance / DotMatrixSizes.dragFull),
    DotMatrixSizes.dragSigma,
  );

  void _queue(Offset p, double strength, double sigma) {
    if (_touchCount >= DotMatrixSizes.touchQueue || strength <= 0) return;
    final i = _touchCount++ * 4;
    _touches[i] = p.dx;
    _touches[i + 1] = p.dy;
    _touches[i + 2] = strength;
    _touches[i + 3] = sigma;
    calm = false;
  }

  /// Sizes the grid to [size] (only reallocates when it changes).
  void layout(Size size) {
    if (size == _size) return;
    _size = size;
    const step = DotMatrixSizes.spacing;
    cols = (size.width / step).floor();
    rows = (size.height / step).floor();
    originX = (size.width - (cols - 1) * step) / 2;
    // Anchor the grid to the bottom edge, where the energy lives.
    originY = size.height - step / 2 - (rows - 1) * step;
    field.resize(cols, rows);
    ripples.resize(cols, rows);

    _colX = Float32List(cols);
    for (var c = 0; c < cols; c++) {
      _colX[c] = originX + c * step;
    }
    _colGlow = Float32List(cols);
    _colHeight = Float32List(cols);
    _colSweep = Float32List(cols);
    _colSin1 = Float32List(cols);
    _colCos1 = Float32List(cols);
    _colSin2 = Float32List(cols);
    _colCos2 = Float32List(cols);
    _rowD = Float32List(rows);
    for (var r = 0; r < rows; r++) {
      _rowD[r] = size.height - (originY + r * step);
    }
    _rowSin1 = Float32List(rows);
    _rowCos1 = Float32List(rows);
    _rowSin2 = Float32List(rows);
    _rowCos2 = Float32List(rows);
    _rowThink = Float32List(rows);

    // The front is an ellipse centred on the bottom edge.
    _openDist = Float32List(cols * rows);
    final cx = size.width / 2;
    for (var r = 0; r < rows; r++) {
      final d = _rowD[r];
      for (var c = 0; c < cols; c++) {
        final dx = (_colX[c] - cx) * DotMatrixSizes.openAspect;
        _openDist[r * cols + c] = math.sqrt(dx * dx + d * d);
      }
    }
    _frontReach = size.height * DotMatrixSizes.openReach;

    if (_pendingSettle) {
      _pendingSettle = false;
      _computeTargets();
      field.settle();
    }
  }

  /// One tick: time moves on, the mode springs and the level follow their
  /// targets, forces hit the field and it steps.
  void advance(double now, double dt, double micLevel) {
    t = now;
    final step = dt.clamp(0.0, DotMatrixSizes.maxFrameStep);
    _listen.step(step);
    _think.step(step);
    _stream.step(step);
    final follow = 1 - math.exp(-step / _seconds(DotMatrixDurations.level));
    level += (micLevel.clamp(0.0, 1.0) - level) * follow;
    if (_size == null) {
      notifyListeners();
      return;
    }

    final start = waveStart;
    if (start != null && now - start > _seconds(DotMatrixDurations.open)) {
      waveStart = null;
    }
    if (dt > DotMatrixSizes.resumeGap) {
      // Back from a pause (hidden, or a long stall): whatever was moving
      // would have settled by now, so land there instead of replaying a
      // slowed-down tail.
      _listen.snap();
      _think.snap();
      _stream.snap();
      waveStart = null;
      _touchCount = 0;
      _computeTargets();
      field.settle();
      ripples.clear();
      notifyListeners();
      return;
    }
    _computeTargets();
    _applyTouches();
    _turbulence(step);
    _frontT0 = now - step;
    field.advance(step, _waving ? _frontStep : null);
    ripples.advance(step);

    final busy = listen + think + stream;
    calm =
        !_waving &&
        busy < DotMatrixSizes.energyFloor &&
        now - openedAt > 2 * _seconds(DotMatrixDurations.idleSettle) &&
        field.kinetic + ripples.kinetic < DotMatrixPhysics.calmKinetic;
    notifyListeners();
  }

  /// Kicks the dots the front crossed during this sub-step.
  void _frontStep(double offset) {
    final start = waveStart;
    if (start == null) return;
    final tau = _seconds(DotMatrixDurations.openTau);
    final age = _frontT0 + offset - start;
    final r = _frontReach * (1 - math.exp(-math.max(0.0, age) / tau));
    final r0 = _frontR;
    if (r <= r0) return;
    _frontR = r;
    final dist = _openDist, v = field.v, reach = _frontReach;
    const top = DotMatrixSizes.openKickTop;
    for (var i = 0; i < dist.length; i++) {
      final d = dist[i];
      if (d <= r0 || d > r) continue;
      final f = 1 - d / reach;
      v[i] += DotMatrixSizes.openKick * (top + (1 - top) * f * f);
    }
  }

  void _applyTouches() {
    if (_touchCount == 0) return;
    const step = DotMatrixSizes.spacing;
    for (var k = 0; k < _touchCount; k++) {
      final i = k * 4;
      ripples.kickRadial(
        (_touches[i] - originX) / step,
        (_touches[i + 1] - originY) / step,
        _touches[i + 2],
        _touches[i + 3],
      );
    }
    _touchCount = 0;
  }

  /// Random kicks along the bottom rows, as loud as the microphone.
  void _turbulence(double dt) {
    final w = listen * level;
    if (w <= 0.01 || cols == 0) return;
    final scale = dt / DotMatrixDurations.frame.inMicroseconds * 1e6;
    final n = (DotMatrixSizes.turbulenceKicks * scale).round();
    for (var k = 0; k < n; k++) {
      final c = _rand() * cols;
      final r = rows - 1 - (_rand() * DotMatrixSizes.turbulenceRows);
      ripples.kick(
        c.floor(),
        r.ceil(),
        DotMatrixSizes.turbulenceKick * w * (0.4 + _rand()),
      );
    }
  }

  /// A tiny deterministic xorshift (goldens stay stable), 0..1.
  double _rand() {
    var x = _seed;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _seed = x;
    return (x & 0xFFFFFF) / 0x1000000;
  }

  /// Where each dot's spring wants to rest this frame: the breathing glow
  /// (lifted by the microphone) plus the thinking waves.
  void _computeTargets() {
    final tgt = field.target;
    final now = t;
    final busy = math.max(think, stream).clamp(0.0, 1.0);

    // The idle glow calms down after opening.
    final age = math.max(0.0, now - openedAt);
    final fresh = math.exp(-age / _seconds(DotMatrixDurations.idleSettle));
    final idle =
        DotMatrixSizes.idleRest +
        (DotMatrixSizes.idleStrength - DotMatrixSizes.idleRest) * fresh;
    final l = listen.clamp(0.0, 1.0);
    final strength =
        (idle + (DotMatrixSizes.listenStrength - idle) * l) *
        (1 - DotMatrixSizes.busyDim * busy);
    final pulse =
        DotMatrixSizes.listenPulseDepth *
        (1 + math.sin(now * DotMatrixSizes.listenPulseSpeed)) /
        2;
    final lift = DotMatrixSizes.listenLift * math.max(level, pulse) * l;

    // Thinking waves: two travelling sines (separable, so no trig per dot).
    final waves =
        think * DotMatrixSizes.thinkingStrength +
        stream * DotMatrixSizes.streamingStrength;
    final w = _size!.width;
    final pass = think >= stream
        ? DotMatrixDurations.thinkingPass
        : DotMatrixDurations.streamingPass;
    final phase = (now / _seconds(pass)) % 1.0;
    const sw = DotMatrixSizes.sweepWidth;
    const off = DotMatrixSizes.sweepOffscreen * sw;
    final sx = -off + phase * (w + 2 * off);

    var maxHeight = 0.0;
    for (var c = 0; c < cols; c++) {
      final x = _colX[c];
      final g = _breath(x, now);
      _colGlow[c] =
          strength *
          (DotMatrixSizes.breathFloor + (1 - DotMatrixSizes.breathFloor) * g);
      final h =
          DotMatrixSizes.glowHeight *
              (1 + DotMatrixSizes.glowSwell * (2 * g - 1)) +
          lift *
              (DotMatrixSizes.listenLiftMin +
                  DotMatrixSizes.listenLiftSpread * g);
      _colHeight[c] = 1 / (h * h);
      if (h > maxHeight) maxHeight = h;
      if (waves > 0) {
        final a1 = DotMatrixSizes.thinkK1 * x - DotMatrixSizes.thinkW1 * now;
        final a2 = -DotMatrixSizes.thinkK2 * x - DotMatrixSizes.thinkW2 * now;
        _colSin1[c] = math.sin(a1);
        _colCos1[c] = math.cos(a1);
        _colSin2[c] = math.sin(a2);
        _colCos2[c] = math.cos(a2);
        final dx = (x - sx) / sw;
        _colSweep[c] =
            DotMatrixSizes.sweepFloor +
            (1 - DotMatrixSizes.sweepFloor) * math.exp(-dx * dx);
      }
    }
    final reachD =
        DotMatrixSizes.falloffReach *
        math.max(maxHeight, waves > 0 ? DotMatrixSizes.thinkHeight : 0);
    for (var r = 0; r < rows; r++) {
      final d = _rowD[r];
      if (waves > 0) {
        final b1 = DotMatrixSizes.thinkD1 * d;
        final b2 = DotMatrixSizes.thinkD2 * d;
        _rowSin1[r] = math.sin(b1);
        _rowCos1[r] = math.cos(b1);
        _rowSin2[r] = math.sin(b2);
        _rowCos2[r] = math.cos(b2);
        final q = d / DotMatrixSizes.thinkHeight;
        _rowThink[r] = waves * _gauss(q * q);
      }
    }

    final gating = _waving;
    final front = _frontR;
    final gateInv = 1 / DotMatrixSizes.openGate;
    for (var r = 0; r < rows; r++) {
      final row = r * cols;
      final d = _rowD[r];
      if (d > reachD) {
        tgt.fillRange(row, row + cols, 0);
        continue;
      }
      final dd = d * d;
      final rowWave = waves > 0 ? _rowThink[r] : 0.0;
      final s1 = _rowSin1[r], c1 = _rowCos1[r];
      final s2 = _rowSin2[r], c2 = _rowCos2[r];
      for (var c = 0; c < cols; c++) {
        var e = _colGlow[c] * _gauss(dd * _colHeight[c]);
        if (rowWave > 0) {
          // sin(a + b) from the column and row parts; the two waves add,
          // and squaring the sum makes bright crests where they meet.
          final w1 = _colSin1[c] * c1 + _colCos1[c] * s1;
          final w2 = _colSin2[c] * c2 + _colCos2[c] * s2;
          final s = (w1 + w2 + 2) / 4;
          e += rowWave * _colSweep[c] * s * s;
        }
        if (gating) {
          final gate = ((front - _openDist[row + c]) * gateInv).clamp(0.0, 1.0);
          e *= gate;
        }
        tgt[row + c] = e;
      }
    }
  }

  /// e^-x for x >= 0, as a cheap rational approximation (no exp per dot).
  static double _gauss(double x) {
    final x2 = x * x;
    return 1 / (1 + x + x2 / 2 + x2 * x / 6 + x2 * x2 / 24);
  }

  /// The idle breathing at column [x]: a sum of three slow sines, 0..1.
  static double _breath(double x, double t) =>
      0.5 +
      DotMatrixSizes.breathA1 *
          math.sin(DotMatrixSizes.breathK1 * x + DotMatrixSizes.breathW1 * t) +
      DotMatrixSizes.breathA2 *
          math.sin(
            DotMatrixSizes.breathK2 * x -
                DotMatrixSizes.breathW2 * t +
                DotMatrixSizes.breathPhase,
          ) +
      DotMatrixSizes.breathA3 *
          math.sin(DotMatrixSizes.breathK3 * x + DotMatrixSizes.breathW3 * t);
}

double _seconds(Duration d) =>
    d.inMicroseconds / Duration.microsecondsPerSecond;

/// Paints, buffers and the halo sprite, rebuilt only when the size or the
/// colours change.
class DotMatrixCache {
  Size? size;
  Color? ink, accent;
  bool? dark;

  /// Ink dots grouped by opacity step (one draw call each).
  final inkPoints = <Float32List>[];
  final inkPaints = <Paint>[];

  /// Energy dots, refilled every frame: one buffer and paint per step.
  final energyPoints = <Float32List>[];
  final energyCounts = <int>[];
  final energyPaints = <Paint>[];

  /// Halos, refilled every frame: one atlas call.
  Float32List haloXforms = Float32List(0);
  Float32List haloRects = Float32List(0);
  Int32List haloColors = Int32List(0);
  Paint haloPaint = Paint();

  /// The colour ramp (ARGB, opaque) from the lowest to the hottest step.
  Int32List lut = Int32List(DotMatrixColors.lutSize);
  double bloomAlpha = 0, auroraAlpha = 0;

  ui.Image? sprite;

  Paint veil = Paint();
  Paint haze = Paint();

  static const _inkSteps = DotMatrixSizes.inkLevels;

  void ensure(DotMatrixFrame f, Size s, AppPalette p) {
    final ink = p.textPrimary;
    sprite ??= _sprite();
    if (s == size &&
        ink == this.ink &&
        p.accent == accent &&
        p.isDark == dark) {
      return;
    }
    size = s;
    this.ink = ink;
    accent = p.accent;
    dark = p.isDark;

    _buildInk(f, s, ink, p.isDark);
    _buildEnergy(f, p);
    final n = f.cols * f.rows + f.cols;
    haloXforms = Float32List(n * 4);
    haloRects = Float32List(n * 4);
    haloColors = Int32List(n);
    const sp = DotMatrixSizes.bloomSprite;
    for (var i = 0; i < n; i++) {
      haloRects[i * 4 + 2] = sp;
      haloRects[i * 4 + 3] = sp;
    }
    haloPaint = Paint()
      ..blendMode = p.isDark
          ? DotMatrixSizes.bloomBlendDark
          : DotMatrixSizes.bloomBlendLight
      ..filterQuality = FilterQuality.low;
    bloomAlpha = p.isDark
        ? DotMatrixSizes.bloomAlphaDark
        : DotMatrixSizes.bloomAlphaLight;
    auroraAlpha = p.isDark
        ? DotMatrixSizes.auroraAlphaDark
        : DotMatrixSizes.auroraAlphaLight;

    final veilColor = p.background;
    final rect = Offset.zero & s;
    veil = Paint()
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
        veilColor.withValues(alpha: 0),
        veilColor.withValues(
          alpha: p.isDark
              ? DotMatrixSizes.veilMidDark
              : DotMatrixSizes.veilMidLight,
        ),
        veilColor.withValues(
          alpha: p.isDark
              ? DotMatrixSizes.veilEndDark
              : DotMatrixSizes.veilEndLight,
        ),
      ], DotMatrixSizes.veilStops);
    final hazeTop = Offset(0, s.height - DotMatrixSizes.hazeHeight);
    haze = Paint()
      ..shader = ui.Gradient.linear(hazeTop, rect.bottomLeft, [
        p.accent.withValues(alpha: 0),
        p.accent.withValues(
          alpha: p.isDark
              ? DotMatrixSizes.hazeAlphaDark
              : DotMatrixSizes.hazeAlphaLight,
        ),
      ]);
  }

  void dispose() {
    sprite?.dispose();
    sprite = null;
  }

  /// A white radial glow, drawn once and tinted per halo.
  static ui.Image _sprite() {
    const s = DotMatrixSizes.bloomSprite;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final centre = const Offset(s / 2, s / 2);
    canvas.drawCircle(
      centre,
      s / 2,
      Paint()
        ..shader = ui.Gradient.radial(centre, s / 2, [
          for (final a in DotMatrixSizes.bloomProfile)
            AppColors.white.withValues(alpha: a),
        ], DotMatrixSizes.bloomStops),
    );
    final picture = rec.endRecording();
    final image = picture.toImageSync(s.toInt(), s.toInt());
    picture.dispose();
    return image;
  }

  /// The ramp colour at [f] (0..1 over the steps).
  static Color _ramp(double f, AppPalette p) {
    final base = HSLColor.fromColor(p.accent);
    final hot = base
        .withHue((base.hue + DotMatrixColors.hotHueShift) % 360)
        .withSaturation(1)
        .withLightness(
          p.isDark
              ? DotMatrixColors.hotLightnessDark
              : DotMatrixColors.hotLightnessLight,
        )
        .toColor();
    const w0 = DotMatrixColors.warmStart, w1 = DotMatrixColors.hotStart;
    if (f <= w0) return p.accent;
    if (f <= w1) return Color.lerp(p.accent, hot, (f - w0) / (w1 - w0))!;
    final mix = p.isDark
        ? DotMatrixColors.coreMixDark
        : DotMatrixColors.coreMixLight;
    return Color.lerp(hot, p.textPrimary, mix * (f - w1) / (1 - w1))!;
  }

  void _buildInk(DotMatrixFrame f, Size s, Color ink, bool isDark) {
    final top = isDark
        ? DotMatrixSizes.inkTopAlphaDark
        : DotMatrixSizes.inkTopAlphaLight;
    final bottom = isDark
        ? DotMatrixSizes.inkBottomAlphaDark
        : DotMatrixSizes.inkBottomAlphaLight;
    final buckets = List.generate(_inkSteps, (_) => <double>[]);
    for (var r = 0; r < f.rows; r++) {
      final y = f.originY + r * DotMatrixSizes.spacing;
      final k =
          ((y / s.height - DotMatrixSizes.inkFadeStart) /
                  (1 - DotMatrixSizes.inkFadeStart))
              .clamp(0.0, 1.0);
      final alpha = top + (bottom - top) * k * k;
      final b = (alpha / bottom * (_inkSteps - 1)).round();
      if (b <= 0) continue;
      for (var c = 0; c < f.cols; c++) {
        buckets[b].add(f.originX + c * DotMatrixSizes.spacing);
        buckets[b].add(y);
      }
    }
    inkPoints.clear();
    inkPaints.clear();
    for (var b = 1; b < _inkSteps; b++) {
      if (buckets[b].isEmpty) continue;
      inkPoints.add(Float32List.fromList(buckets[b]));
      inkPaints.add(
        _dotPaint(
          ink.withValues(alpha: bottom * b / (_inkSteps - 1)),
          DotMatrixSizes.baseRadius,
        ),
      );
    }
  }

  void _buildEnergy(DotMatrixFrame f, AppPalette p) {
    const n = DotMatrixSizes.energyLevels;
    const lo = DotMatrixSizes.energyFloor, hi = DotMatrixSizes.energyMax;
    energyPoints
      ..clear()
      ..addAll(List.generate(n, (_) => Float32List(f.cols * f.rows * 2)));
    energyCounts
      ..clear()
      ..addAll(List.filled(n, 0));
    energyPaints
      ..clear()
      ..addAll(
        List.generate(n, (i) {
          final k = (i + 1) / n;
          final e = lo + (hi - lo) * k; // energy at this step
          final unit = ((e - lo) / (1 - lo)).clamp(0.0, 1.0);
          final over = ((e - 1) / (hi - 1)).clamp(0.0, 1.0);
          final radius = e <= 1
              ? ui.lerpDouble(
                  DotMatrixSizes.energyMinRadius,
                  DotMatrixSizes.energyFullRadius,
                  math.sqrt(unit),
                )!
              : ui.lerpDouble(
                  DotMatrixSizes.energyFullRadius,
                  DotMatrixSizes.energyMaxRadius,
                  over,
                )!;
          final alpha = ui.lerpDouble(
            p.isDark
                ? DotMatrixSizes.energyMinAlphaDark
                : DotMatrixSizes.energyMinAlphaLight,
            1,
            unit,
          )!;
          return _dotPaint(_ramp(k, p).withValues(alpha: alpha), radius);
        }),
      );
    for (var i = 0; i < lut.length; i++) {
      lut[i] = _ramp(i / (lut.length - 1), p).toARGB32();
    }
  }

  static Paint _dotPaint(Color color, double radius) => Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..strokeWidth = radius * 2
    ..isAntiAlias = true;
}

/// Paints the veil, the ink grid, the halos and the red energy dots of
/// [frame].
class DotMatrixPainter extends CustomPainter {
  DotMatrixPainter({
    required this.frame,
    required this.palette,
    DotMatrixCache? cache,
  }) : _cache = cache ?? DotMatrixCache(),
       super(repaint: frame);

  final DotMatrixFrame frame;
  final AppPalette palette;
  final DotMatrixCache _cache;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    frame.layout(size);
    final c = _cache..ensure(frame, size, palette);
    final rect = Offset.zero & size;
    canvas.drawRect(rect, c.veil);
    canvas.drawRect(
      Rect.fromLTRB(
        0,
        size.height - DotMatrixSizes.hazeHeight,
        size.width,
        size.height,
      ),
      c.haze,
    );
    for (var i = 0; i < c.inkPoints.length; i++) {
      canvas.drawRawPoints(ui.PointMode.points, c.inkPoints[i], c.inkPaints[i]);
    }
    _paintEnergy(canvas, size, c);
  }

  void _paintEnergy(Canvas canvas, Size size, DotMatrixCache c) {
    final f = frame;
    final h = f.field.h;
    final cols = f.cols, rows = f.rows;
    if (h.length != cols * rows || cols == 0) return;
    const step = DotMatrixSizes.spacing;
    const levels = DotMatrixSizes.energyLevels;
    const lo = DotMatrixSizes.energyFloor, hi = DotMatrixSizes.energyMax;
    const levelScale = levels / (hi - lo);
    const sprite = DotMatrixSizes.bloomSprite;
    final lut = c.lut;
    final lutMax = lut.length - 1;
    final counts = c.energyCounts..fillRange(0, levels, 0);
    final xf = c.haloXforms, colors = c.haloColors;
    var halos = 0;

    // The aurora first: one big halo per column, behind everything.
    const ar = DotMatrixSizes.auroraRows;
    final auroraScale = DotMatrixSizes.auroraRadius * 2 / sprite;
    for (var col = 0; col < cols; col++) {
      var sum = 0.0;
      for (var r = rows - ar; r < rows; r++) {
        final e = f.energy(r * cols + col);
        if (e > 0) sum += e;
      }
      final e = math.min(sum / ar, hi);
      if (e < lo) continue;
      final k = (e - lo) / (hi - lo);
      _halo(
        xf,
        colors,
        halos++,
        f.originX + col * step,
        size.height - DotMatrixSizes.auroraRise,
        auroraScale,
        lut[(k * lutMax).round()],
        c.auroraAlpha * math.min(1.0, e),
      );
    }

    for (var row = rows - 1; row >= 0; row--) {
      final y = f.originY + row * step;
      final base = row * cols;
      for (var col = 0; col < cols; col++) {
        final e = f.energy(base + col);
        if (e < lo) continue;
        var b = ((e - lo) * levelScale).floor();
        if (b >= levels) b = levels - 1;
        final x = f.originX + col * step;
        final i = counts[b] * 2;
        final buf = c.energyPoints[b];
        buf[i] = x;
        buf[i + 1] = y;
        counts[b]++;
        if (e > DotMatrixSizes.bloomFloor) {
          final k = math.min(1.0, (e - lo) / (hi - lo));
          final glow = math.min(
            1.0,
            (e - DotMatrixSizes.bloomFloor) / (1 - DotMatrixSizes.bloomFloor),
          );
          final radius =
              DotMatrixSizes.bloomMinRadius +
              (DotMatrixSizes.bloomMaxRadius - DotMatrixSizes.bloomMinRadius) *
                  glow;
          _halo(
            xf,
            colors,
            halos++,
            x,
            y,
            radius * 2 / sprite,
            lut[(k * lutMax).round()],
            c.bloomAlpha * glow,
          );
        }
      }
    }

    final image = c.sprite;
    if (halos > 0 && image != null) {
      canvas.drawRawAtlas(
        image,
        Float32List.sublistView(xf, 0, halos * 4),
        Float32List.sublistView(c.haloRects, 0, halos * 4),
        Int32List.sublistView(colors, 0, halos),
        BlendMode.modulate,
        null,
        c.haloPaint,
      );
    }
    for (var b = 0; b < levels; b++) {
      final n = counts[b];
      if (n == 0) continue;
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(c.energyPoints[b], 0, n * 2),
        c.energyPaints[b],
      );
    }
  }

  /// Writes halo [i]: the sprite centred on ([x], [y]) at [scale], tinted
  /// [rgb] at [alpha].
  static void _halo(
    Float32List xf,
    Int32List colors,
    int i,
    double x,
    double y,
    double scale,
    int rgb,
    double alpha,
  ) {
    const half = DotMatrixSizes.bloomSprite / 2;
    final j = i * 4;
    xf[j] = scale;
    xf[j + 1] = 0;
    xf[j + 2] = x - half * scale;
    xf[j + 3] = y - half * scale;
    final a = (alpha.clamp(0.0, 1.0) * 255).round();
    colors[i] = (a << 24) | (rgb & 0x00FFFFFF);
  }

  @override
  bool shouldRepaint(DotMatrixPainter old) =>
      old.frame != frame || old.palette != palette;
}
