import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../constants/dot_matrix.dart';
import '../theme/app_palette.dart';

/// What the backdrop's red energy layer is doing.
enum DotMatrixMode {
  /// A slow breathing glow along the bottom edge.
  idle,

  /// The glow follows the microphone level (or pulses gently).
  listening,

  /// A bright shimmer runs left to right along the bottom rows.
  thinking,

  /// A calmer shimmer while the answer streams in.
  streaming,
}

/// A Nothing-style dot matrix over a see-through veil: ink dots at low
/// opacity (black on light, white on dark) and a red energy layer in the
/// palette's accent. A red wave rises through the grid when [wave] changes
/// (and on first show).
///
/// One ticker drives everything and only repaints (no rebuilds, no widget per
/// dot). Dots are drawn in a few batched point calls with cached paints. With
/// reduced motion it paints one still frame: the grid and a soft red glow.
class DotMatrixBackdrop extends StatefulWidget {
  const DotMatrixBackdrop({
    super.key,
    this.mode = DotMatrixMode.idle,
    this.wave = 0,
    this.level,
  });

  final DotMatrixMode mode;

  /// Change it to replay the rising wave (e.g. on every new opening).
  final int wave;

  /// The microphone level (0..1), read every frame while listening.
  final ValueGetter<double>? level;

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
    final dt = _seconds(elapsed - _last);
    _last = elapsed;
    final t = _seconds(elapsed);
    if (_restartWave) {
      _restartWave = false;
      _frame.waveStart = t;
    }
    _frame.advance(t, dt, widget.level?.call() ?? 0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: DotMatrixPainter(
          frame: _frame,
          palette: context.palette,
          cache: _cache,
        ),
      ),
    );
  }
}

/// The animated state the painter reads: time, the open wave and how much
/// of each mode is showing (cross-faded, so state changes never pop).
class DotMatrixFrame extends ChangeNotifier {
  /// Seconds since the ticker started.
  double t = 0;

  /// When the latest open wave started (seconds); null = no wave.
  double? waveStart = 0;

  /// Mode weights (0..1), eased towards [_targets].
  double listen = 0, think = 0, stream = 0;

  /// The smoothed microphone level.
  double level = 0;

  var _targets = (listen: 0.0, think: 0.0, stream: 0.0);

  void setTargets(DotMatrixMode mode) {
    _targets = (
      listen: mode == DotMatrixMode.listening ? 1.0 : 0.0,
      think: mode == DotMatrixMode.thinking ? 1.0 : 0.0,
      stream: mode == DotMatrixMode.streaming ? 1.0 : 0.0,
    );
  }

  /// Jumps to the targets with no wave (one still frame).
  void settle() {
    listen = _targets.listen;
    think = _targets.think;
    stream = _targets.stream;
    waveStart = null;
    level = 0;
    notifyListeners();
  }

  /// One tick: time moves on, weights and level ease towards their targets.
  void advance(double now, double dt, double micLevel) {
    t = now;
    final step = dt.clamp(0.0, DotMatrixSizes.maxFrameStep);
    final blend = 1 - math.exp(-step / _seconds(DotMatrixDurations.blend));
    listen += (_targets.listen - listen) * blend;
    think += (_targets.think - think) * blend;
    stream += (_targets.stream - stream) * blend;
    final follow = 1 - math.exp(-step / _seconds(DotMatrixDurations.level));
    level += (micLevel.clamp(0.0, 1.0) - level) * follow;
    notifyListeners();
  }
}

double _seconds(Duration d) =>
    d.inMicroseconds / Duration.microsecondsPerSecond;

/// Grid positions and paints, rebuilt only when the size or colours change.
class DotMatrixCache {
  Size? size;
  Color? ink, accent;
  bool? dark;

  int cols = 0, rows = 0;
  double originX = 0, originY = 0;

  /// Ink dots grouped by opacity step (one draw call each).
  final inkPoints = <Float32List>[];
  final inkPaints = <Paint>[];

  /// Energy dots, refilled every frame: one buffer and paint per step.
  final energyPoints = <Float32List>[];
  final energyCounts = <int>[];
  final energyPaints = <Paint>[];

  /// Per-column scratch values, reused every frame.
  Float64List colGlow = Float64List(0);
  Float64List colHeight = Float64List(0);
  Float64List colShimmer = Float64List(0);
  Float64List colFront = Float64List(0);

  Paint veil = Paint();
  Paint haze = Paint();

  static const _inkSteps = DotMatrixSizes.inkLevels;

  void ensure(Size s, AppPalette p) {
    final ink = p.textPrimary;
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
    const step = DotMatrixSizes.spacing;
    cols = (s.width / step).floor();
    rows = (s.height / step).floor();
    originX = (s.width - (cols - 1) * step) / 2;
    // Anchor the grid to the bottom edge, where the energy lives.
    originY = s.height - step / 2 - (rows - 1) * step;

    _buildInk(s, ink, p.isDark);
    _buildEnergy(p.accent);
    colGlow = Float64List(cols);
    colHeight = Float64List(cols);
    colShimmer = Float64List(cols);
    colFront = Float64List(cols);

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

  void _buildInk(Size s, Color ink, bool isDark) {
    final top = isDark
        ? DotMatrixSizes.inkTopAlphaDark
        : DotMatrixSizes.inkTopAlphaLight;
    final bottom = isDark
        ? DotMatrixSizes.inkBottomAlphaDark
        : DotMatrixSizes.inkBottomAlphaLight;
    final buckets = List.generate(_inkSteps, (_) => <double>[]);
    for (var r = 0; r < rows; r++) {
      final y = originY + r * DotMatrixSizes.spacing;
      final f =
          ((y / s.height - DotMatrixSizes.inkFadeStart) /
                  (1 - DotMatrixSizes.inkFadeStart))
              .clamp(0.0, 1.0);
      final alpha = top + (bottom - top) * f * f;
      final b = (alpha / bottom * (_inkSteps - 1)).round();
      if (b <= 0) continue;
      for (var c = 0; c < cols; c++) {
        buckets[b].add(originX + c * DotMatrixSizes.spacing);
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

  void _buildEnergy(Color accent) {
    const n = DotMatrixSizes.energyLevels;
    energyPoints
      ..clear()
      ..addAll(List.generate(n, (_) => Float32List(cols * rows * 2)));
    energyCounts
      ..clear()
      ..addAll(List.filled(n, 0));
    energyPaints
      ..clear()
      ..addAll(
        List.generate(n, (i) {
          final f = (i + 1) / n;
          return _dotPaint(
            accent.withValues(
              alpha: ui.lerpDouble(
                DotMatrixSizes.energyMinAlpha,
                DotMatrixSizes.energyMaxAlpha,
                f,
              ),
            ),
            ui.lerpDouble(
              DotMatrixSizes.energyMinRadius,
              DotMatrixSizes.energyMaxRadius,
              f * f,
            )!,
          );
        }),
      );
  }

  static Paint _dotPaint(Color color, double radius) => Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..strokeWidth = radius * 2
    ..isAntiAlias = true;
}

/// Paints the veil, the ink grid and the red energy dots of [frame].
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
    final c = _cache..ensure(size, palette);
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
    final t = f.t;
    const step = DotMatrixSizes.spacing;
    final w = size.width;

    // The open wave: progress 0..1, eased; null once it has passed.
    final start = f.waveStart;
    final raw = start == null
        ? 1.0
        : ((t - start) / _seconds(DotMatrixDurations.open)).clamp(0.0, 1.0);
    final waving = raw < 1;
    final eased = Curves.easeOutCubic.transform(raw);
    final waveFade = math.pow(1 - raw, DotMatrixSizes.waveFadePower).toDouble();
    final waveReach =
        size.height * (1 - DotMatrixSizes.waveTop) + DotMatrixSizes.waveCurve;

    // The glow fills in behind the wave.
    final busy = math.max(f.think, f.stream);
    final pulse =
        DotMatrixSizes.listenPulseDepth *
        (1 + math.sin(t * DotMatrixSizes.listenPulseSpeed)) /
        2;
    final mic = math.max(f.level, pulse);
    final strength =
        eased *
        (DotMatrixSizes.idleStrength +
            (DotMatrixSizes.listenStrength - DotMatrixSizes.idleStrength) *
                f.listen) *
        (1 - DotMatrixSizes.busyDim * busy);
    final lift = DotMatrixSizes.listenLift * mic * f.listen;

    // The shimmer packet's centre (dp), wrapping off both edges.
    const sw = DotMatrixSizes.shimmerWidth;
    final pass = f.think >= f.stream
        ? DotMatrixDurations.thinkingPass
        : DotMatrixDurations.streamingPass;
    final phase = (t / _seconds(pass)) % 1.0;
    const off = DotMatrixSizes.shimmerOffscreen * sw;
    final sx = -off + phase * (w + 2 * off);
    final shimmerStrength =
        f.think * DotMatrixSizes.thinkingStrength +
        f.stream * DotMatrixSizes.streamingStrength;

    var maxHeight = 0.0;
    for (var col = 0; col < c.cols; col++) {
      final x = c.originX + col * step;
      final g = _breath(x, t);
      c.colGlow[col] =
          strength *
          (DotMatrixSizes.breathFloor + (1 - DotMatrixSizes.breathFloor) * g);
      final h =
          DotMatrixSizes.glowHeight *
              (1 + DotMatrixSizes.glowSwell * (2 * g - 1)) +
          lift *
              (DotMatrixSizes.listenLiftMin +
                  DotMatrixSizes.listenLiftSpread * g);
      c.colHeight[col] = h;
      if (h > maxHeight) maxHeight = h;
      final dx = (x - sx) / sw;
      c.colShimmer[col] = shimmerStrength * math.exp(-dx * dx);
      final xn = x / w - 0.5;
      c.colFront[col] =
          eased * waveReach - DotMatrixSizes.waveCurve * 4 * xn * xn;
    }

    // Rows above this have no energy (outside the wave): skip them.
    var reach =
        DotMatrixSizes.falloffReach *
        math.max(maxHeight, DotMatrixSizes.shimmerHeight);
    if (waving) reach = size.height;

    const levels = DotMatrixSizes.energyLevels;
    final counts = c.energyCounts..fillRange(0, levels, 0);
    for (var row = c.rows - 1; row >= 0; row--) {
      final y = c.originY + row * step;
      final d = size.height - y;
      if (d > reach) break;
      final shimmerFall = math.exp(
        -d / (DotMatrixSizes.shimmerHeight * DotMatrixSizes.shimmerFalloff),
      );
      for (var col = 0; col < c.cols; col++) {
        final q = d / c.colHeight[col];
        var e = c.colGlow[col] * math.exp(-q * q);
        final s = c.colShimmer[col] * shimmerFall;
        e = 1 - (1 - e) * (1 - s);
        if (waving) {
          final k = (d - c.colFront[col]) / DotMatrixSizes.waveWidth;
          final band =
              DotMatrixSizes.waveStrength * waveFade * math.exp(-k * k);
          e = 1 - (1 - e) * (1 - band);
        }
        if (e < DotMatrixSizes.energyFloor) continue;
        final b = math.min(levels - 1, (e * levels).floor());
        final i = counts[b] * 2;
        final buf = c.energyPoints[b];
        buf[i] = c.originX + col * step;
        buf[i + 1] = y;
        counts[b]++;
      }
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

  @override
  bool shouldRepaint(DotMatrixPainter old) =>
      old.frame != frame || old.palette != palette;
}
