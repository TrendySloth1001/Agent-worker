import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/history.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';

/// Sliding sidebar that pushes the chat aside, as Android 15/16 apps do.
///
/// One [AnimationController] drives both the panel and the content: the panel
/// slides in from the left while the chat is pushed right, shrinks a little,
/// gets rounded corners and is dimmed. The drag follows the finger 1:1; on
/// release the velocity decides, and the settle uses Material 3 emphasized
/// easing (a decelerating curve when flung). Opening starts from a thin left
/// edge strip so horizontal scrolling inside the chat is never taken over;
/// once open, a drag on the pushed chat, the header or the footer closes it
/// (use [DrawerDragRegion]). The list area is left to row swipes.
///
/// Back closes the panel, with predictive back progress where the platform
/// provides it. Reduced motion makes the settle instant.
class DrawerShell extends StatefulWidget {
  const DrawerShell({
    super.key,
    required this.drawer,
    required this.child,
    this.onOpening,
  });

  final Widget drawer;
  final Widget child;

  /// Called when the panel starts to appear (refresh its data).
  final VoidCallback? onOpening;

  static DrawerShellState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<DrawerShellState>();

  @override
  State<DrawerShell> createState() => DrawerShellState();
}

class DrawerShellState extends State<DrawerShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const contentKey = ValueKey('drawer-shell-content');
  static const panelKey = ValueKey('drawer-shell-panel');

  late final _c = AnimationController(vsync: this)..addListener(_onTick);
  double _width = 1;
  bool _shown = false;
  bool _opened = false;
  bool _dragging = false;
  bool _backActive = false;
  double _backFrom = 0;
  bool _reduce = false;

  /// 0 closed, 1 open.
  double get value => _c.value;

  bool get isOpen => _shown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  void _onTick() {
    final shown = _c.value > 0;
    if (shown != _shown) {
      _shown = shown;
      if (shown) {
        FocusManager.instance.primaryFocus?.unfocus();
        widget.onOpening?.call();
      }
      setState(() {});
    }
    final open = _c.value >= 1;
    if (open != _opened) {
      _opened = open;
      if (open && !_dragging && !_backActive) Haptics.tick();
    }
  }

  void open({double velocity = 0}) => _settle(true, velocity);

  void close({double velocity = 0}) => _settle(false, velocity);

  void toggle() => _shown ? close() : open();

  void _settle(bool open, double velocity) {
    final target = open ? 1.0 : 0.0;
    final distance = (target - _c.value).abs();
    if (distance < 0.001) {
      _c.value = target;
      return;
    }
    if (_reduce) {
      _c.value = target;
      return;
    }
    final base = open ? DrawerMotion.open : DrawerMotion.close;
    if (velocity > 0) {
      // Thrown by a finger: keep that speed and slow down at the end.
      final ms = (distance * _width / velocity * 1000).clamp(
        120.0,
        base.inMilliseconds.toDouble(),
      );
      _c.animateTo(
        target,
        duration: Duration(milliseconds: ms.round()),
        curve: Curves.easeOutCubic,
      );
    } else {
      _c.animateTo(
        target,
        duration: base * distance.clamp(0.4, 1.0),
        curve: open
            ? Curves.easeInOutCubicEmphasized
            : Curves.easeInOutCubicEmphasized.flipped,
      );
    }
  }

  // --- Drag, shared by the edge strip, the scrim and [DrawerDragRegion]. ---

  void dragStart(DragStartDetails d) {
    _c.stop();
    _dragging = true;
  }

  void dragUpdate(DragUpdateDetails d) {
    _c.value += (d.primaryDelta ?? 0) / _width;
  }

  void dragEnd(DragEndDetails d) {
    _dragging = false;
    final v = d.primaryVelocity ?? 0;
    if (v.abs() >= DrawerMotion.flingVelocity) {
      _settle(v > 0, v.abs());
    } else {
      _settle(_c.value > 0.5, 0);
    }
  }

  void dragCancel() {
    _dragging = false;
    _settle(_c.value > 0.5, 0);
  }

  // --- Predictive back. ---

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_shown) return false;
    _c.stop();
    _backActive = true;
    _backFrom = _c.value;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_backActive) _c.value = _backFrom * (1 - backEvent.progress);
  }

  @override
  void handleCommitBackGesture() {
    if (!_backActive) return;
    _backActive = false;
    close();
  }

  @override
  void handleCancelBackGesture() {
    if (!_backActive) return;
    _backActive = false;
    open();
  }

  @override
  Widget build(BuildContext context) {
    _reduce = MediaQuery.disableAnimationsOf(context);
    final p = context.palette;
    return PopScope(
      canPop: !_shown,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth * AppSizes.drawerWidthFactor).clamp(
            0.0,
            AppSizes.drawerMaxWidth,
          );
          _width = width <= 0 ? 1 : width;
          return ColoredBox(
            color: p.background,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _stack(context, width),
            ),
          );
        },
      ),
    );
  }

  Widget _stack(BuildContext context, double width) {
    final t = _c.value;
    final shown = t > 0;
    final scale = 1 - (1 - DrawerMotion.contentScale) * t;
    return Stack(
      children: [
        Positioned(
          left: -width * (1 - t),
          top: 0,
          bottom: 0,
          width: width,
          child: Visibility(
            visible: shown,
            maintainState: true,
            child: KeyedSubtree(key: panelKey, child: widget.drawer),
          ),
        ),
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(width * t, 0),
            child: Transform.scale(
              key: contentKey,
              scale: scale,
              alignment: Alignment.centerLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  DrawerMotion.contentRadius * t,
                ),
                clipBehavior: shown ? Clip.antiAlias : Clip.none,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      excluding: shown,
                      child: AbsorbPointer(
                        absorbing: shown,
                        child: widget.child,
                      ),
                    ),
                    if (shown)
                      IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: DrawerMotion.scrimOpacity * t,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Opening strip when closed; the pushed chat (tap or drag to close)
        // when open. One widget, so a drag that starts on the edge carries on.
        Positioned(
          top: 0,
          bottom: 0,
          left: shown ? width * t : 0,
          right: shown ? 0 : null,
          width: shown ? null : DrawerMotion.edgeWidth,
          child: Semantics(
            button: shown,
            label: shown ? HistoryStrings.closeMenu : null,
            onTap: shown ? close : null,
            child: GestureDetector(
              behavior: shown
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.translucent,
              dragStartBehavior: DragStartBehavior.down,
              onTap: shown
                  ? () {
                      Haptics.tap();
                      close();
                    }
                  : null,
              onHorizontalDragStart: dragStart,
              onHorizontalDragUpdate: dragUpdate,
              onHorizontalDragEnd: dragEnd,
              onHorizontalDragCancel: dragCancel,
            ),
          ),
        ),
      ],
    );
  }
}

/// Makes [child] (the sidebar's header or footer) drag the panel closed.
/// The conversation list is not wrapped, so row swipes keep working.
class DrawerDragRegion extends StatelessWidget {
  const DrawerDragRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shell = DrawerShell.maybeOf(context);
    if (shell == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: shell.dragStart,
      onHorizontalDragUpdate: shell.dragUpdate,
      onHorizontalDragEnd: shell.dragEnd,
      onHorizontalDragCancel: shell.dragCancel,
      child: child,
    );
  }
}
