import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'springs.dart';

/// Springs [child] in when it first builds (or when [trigger] changes):
/// it rises from [offset] (a fraction of its size), grows from [scale] and
/// fades in, overshooting slightly with [spring] before it settles. With
/// reduced motion it simply appears.
///
/// Meant for entrances such as the assistant pill and sheet:
/// `SpringIn(child: pill)`.
class SpringIn extends StatefulWidget {
  const SpringIn({
    super.key,
    required this.child,
    this.trigger,
    this.spring,
    this.offset = AppSprings.entranceOffset,
    this.scale = AppSprings.entranceScale,
    this.alignment = Alignment.bottomCenter,
  });

  final Widget child;

  /// Change it to play the entrance again.
  final Object? trigger;

  /// Defaults to [AppSprings.pop].
  final SpringDescription? spring;

  /// Where it starts, as a fraction of its own size.
  final Offset offset;

  /// The scale it starts at.
  final double scale;

  /// The scale's anchor.
  final Alignment alignment;

  @override
  State<SpringIn> createState() => _SpringInState();
}

class _SpringInState extends State<SpringIn>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController.unbounded(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value == 0 && !_c.isAnimating) _play();
  }

  @override
  void didUpdateWidget(SpringIn old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _c.value = 0;
      _play();
    }
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
      return;
    }
    _c.animateWith(
      SpringSimulation(widget.spring ?? AppSprings.pop, _c.value, 1, 0),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final rest = 1 - t;
        return FractionalTranslation(
          translation: widget.offset * rest,
          child: Transform.scale(
            scale: 1 - (1 - widget.scale) * rest,
            alignment: widget.alignment,
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
        );
      },
    );
  }
}
