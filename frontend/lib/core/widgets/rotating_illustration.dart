import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/illustrations.dart';
import 'illustration.dart';

/// Cycles through a few [Illustration]s in one fixed slot: each scene stays
/// up for [interval], then the next one cross-fades in with a small scale
/// and rise, while the art drifts gently up and down.
///
/// With reduced motion it shows one still scene. Rotation pauses while the
/// app is in the background or the slot is offstage (TickerMode off).
class RotatingIllustration extends StatefulWidget {
  const RotatingIllustration({
    super.key,
    required this.kinds,
    required this.height,
    this.paper,
    this.interval = IllustrationDurations.rotateEvery,
    this.initialIndex,
  });

  /// Scenes in order; must not be empty.
  final List<IllustrationKind> kinds;

  /// Slot height; the slot is [IllustrationSizes.rotatingAspect] times as
  /// wide, and every scene is contained in it so nothing around it moves.
  final double height;

  /// See [Illustration.paper].
  final Color? paper;

  final Duration interval;

  /// Scene to start on. When null it starts on a random scene the first
  /// time, then each new slot for the same set carries on from where the
  /// last one stopped.
  final int? initialIndex;

  /// Makes the next slot for [kinds] start on [index] (tests, screenshots).
  @visibleForTesting
  static void debugStartAt(List<IllustrationKind> kinds, int index) =>
      _RotatingIllustrationState._next[Object.hashAll(kinds)] = index;

  @override
  State<RotatingIllustration> createState() => _RotatingIllustrationState();
}

class _RotatingIllustrationState extends State<RotatingIllustration>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Next scene per set, kept for the session.
  static final _next = <int, int>{};
  static final _random = math.Random();

  late int _index;
  bool _first = true;
  Timer? _timer;
  bool _still = false;
  bool _visible = true;
  bool _foreground = true;

  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: IllustrationDurations.floatCycle,
  );
  late final Animation<double> _drift = CurvedAnimation(
    parent: _float,
    curve: Curves.easeInOutSine,
  );

  int get _setKey => Object.hashAll(widget.kinds);

  @override
  void initState() {
    super.initState();
    final n = widget.kinds.length;
    _index = (widget.initialIndex ?? _next[_setKey] ?? _random.nextInt(n)) % n;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.of(context);
    _sync();
  }

  @override
  void didUpdateWidget(RotatingIllustration old) {
    super.didUpdateWidget(old);
    if (old.kinds.length != widget.kinds.length) {
      _index %= widget.kinds.length;
    }
    if (old.interval != widget.interval) {
      _timer?.cancel();
      _timer = null;
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  /// Runs the timer and the float only while they can be seen.
  void _sync() {
    final run = !_still && _visible && _foreground;
    if (run && widget.kinds.length > 1) {
      _timer ??= Timer.periodic(widget.interval, (_) => _advance());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    if (run && !_float.isAnimating) {
      _float.repeat(reverse: true);
    } else if (!run && _float.isAnimating) {
      _float.stop();
    }
  }

  void _advance() {
    if (!mounted) return;
    setState(() {
      _first = false;
      _index = (_index + 1) % widget.kinds.length;
    });
  }

  @override
  void dispose() {
    _next[_setKey] = (_index + 1) % widget.kinds.length;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final w = h * IllustrationSizes.rotatingAspect;
    final kind = widget.kinds[_index];
    Widget scene(IllustrationKind k, {bool entrance = false}) => Illustration(
      key: ValueKey(k),
      kind: k,
      height: h,
      width: w,
      paper: widget.paper,
      entrance: entrance,
    );

    if (_still) {
      return SizedBox(width: w, height: h, child: scene(kind));
    }
    return SizedBox(
      width: w,
      height: h,
      child: AnimatedBuilder(
        animation: _drift,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (0.5 - _drift.value) * 2 * IllustrationSizes.float),
          child: child,
        ),
        child: AnimatedSwitcher(
          duration: IllustrationDurations.swap,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, t) => FadeTransition(
            opacity: t,
            child: ScaleTransition(
              scale: Tween(
                begin: IllustrationSizes.swapScale,
                end: 1.0,
              ).animate(t),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, IllustrationSizes.swapRise),
                  end: Offset.zero,
                ).animate(t),
                child: child,
              ),
            ),
          ),
          child: scene(kind, entrance: _first),
        ),
      ),
    );
  }
}
