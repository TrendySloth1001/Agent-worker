import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/circle_search.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import 'circle_geometry.dart';

/// The frozen screen of "Circle to search": the screenshot fills the
/// overlay, dimmed under a dot grid; the user circles, scribbles or taps
/// what to search, drawn as a glowing red stroke. The selected box stays
/// lit while the answer shows; drawing again selects anew.
class CircleView extends StatefulWidget {
  const CircleView({
    super.key,
    required this.image,
    required this.onSelect,
    required this.onCancel,
    this.selection,
    this.selecting = true,
    this.busy = false,
    this.onEmpty,
    this.onDrawStart,
    this.mergeWindow = CircleConfig.strokeMerge,
  });

  /// The screenshot (a [FileImage] on the phone).
  final ImageProvider image;

  /// The last selection (overlay coordinates), lit while answering.
  final Rect? selection;

  /// Choosing (hint and back button on top) rather than answering.
  final bool selecting;

  /// The selection is being cut out.
  final bool busy;

  final void Function(Rect selection, Size view) onSelect;
  final VoidCallback onCancel;

  /// A stroke that selected nothing.
  final VoidCallback? onEmpty;

  /// A new selection started (not a stroke merged into the current one):
  /// any cut-out or answer of the previous one is cancelled.
  final VoidCallback? onDrawStart;

  /// Strokes within this pause merge into one selection.
  final Duration mergeWindow;

  /// The view for a screenshot file.
  static ImageProvider fileImage(String path) => FileImage(File(path));

  @override
  State<CircleView> createState() => _CircleViewState();
}

class _CircleViewState extends State<CircleView> {
  /// The strokes of the selection being drawn (the finger may lift between
  /// them); they become one selection once the user pauses.
  final _strokes = <List<Offset>>[];
  bool _drawing = false;

  /// Bumped on every change to [_strokes], so the painter repaints.
  int _version = 0;

  /// Runs out [CircleView.mergeWindow] after the last stroke: then the
  /// strokes are selected. Active while another stroke would still merge.
  Timer? _pause;

  bool get _pending => _pause?.isActive ?? false;

  @override
  void dispose() {
    _pause?.cancel();
    super.dispose();
  }

  void _start(Offset p) {
    Haptics.tick();
    final merge = _pending;
    _pause?.cancel();
    // A new selection: whatever is being cut out or answered is dropped.
    if (!merge) widget.onDrawStart?.call();
    setState(() {
      _drawing = true;
      if (!merge) _strokes.clear();
      _strokes.add([p]);
      _version++;
    });
  }

  void _move(Offset p) {
    if (!_drawing || _strokes.isEmpty) return;
    final stroke = _strokes.last;
    if ((p - stroke.last).distance < CircleSizes.minPointGap) return;
    setState(() {
      stroke.add(p);
      _version++;
    });
  }

  void _end(Size view) {
    if (!_drawing) return;
    _pause?.cancel();
    _pause = Timer(widget.mergeWindow, () => _commit(view));
    setState(() => _drawing = false);
  }

  /// The user paused: the strokes so far are the selection.
  void _commit(Size view) {
    if (!mounted) return;
    final box = selectionOfStrokes(_strokes, view: view);
    // Repaint without the "still drawing" state.
    setState(() => _version++);
    if (box == null) {
      widget.onEmpty?.call();
      return;
    }
    Haptics.send();
    widget.onSelect(box, view);
  }

  void _tap(Offset p, Size view) {
    _start(p);
    _end(view);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: widget.image,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, _, _) => ColoredBox(color: p.background),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: reduce ? Duration.zero : AppDurations.normal,
              builder: (context, t, _) => CustomPaint(
                painter: CirclePainter(
                  // The strokes while drawing and cutting out; then the lit box.
                  strokes: _drawing || _pending || widget.busy
                      ? _strokes
                      : const [],
                  version: _version,
                  selection: _drawing || _pending ? null : widget.selection,
                  accent: p.accent,
                  dim: Colors.black.withValues(
                    alpha:
                        t *
                        (p.isDark ? CircleSizes.dimDark : CircleSizes.dimLight),
                  ),
                  dot: Colors.white.withValues(alpha: t * CircleSizes.dotAlpha),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Strokes start where the finger touched, not past the slop.
              dragStartBehavior: DragStartBehavior.down,
              // Always drawable: a stroke while cutting out starts anew.
              onPanStart: (d) => _start(d.localPosition),
              onPanUpdate: (d) => _move(d.localPosition),
              onPanEnd: (_) => _end(view),
              onTapUp: (d) => _tap(d.localPosition, view),
            ),
            if (widget.selecting)
              Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: _Hint(busy: widget.busy, onCancel: widget.onCancel),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Circle or tap anything to search" with a back button, on top.
class _Hint extends StatelessWidget {
  const _Hint({required this.busy, required this.onCancel});

  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = p.isDark ? p.surfaceRaised : p.surface;
    return Row(
      children: [
        Semantics(
          button: true,
          label: CircleStrings.cancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: Container(
              width: CircleSizes.hintHeight,
              height: CircleSizes.hintHeight,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: card,
                border: Border.all(color: p.border, width: AppBorder.thin),
              ),
              child: AppIcon(
                AppIcons.back,
                size: AppIconSize.md,
                color: p.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Container(
            height: CircleSizes.hintHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: p.border, width: AppBorder.thin),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox.square(
                    dimension: AppIconSize.sm,
                    child: CircularProgressIndicator(
                      strokeWidth: AppBorder.thick,
                      color: p.accent,
                    ),
                  )
                else
                  AppIcon(
                    CircleIcons.circle,
                    size: AppIconSize.sm,
                    color: p.accent,
                  ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    busy ? CircleStrings.reading : CircleStrings.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Dim and dots over the screenshot (with the selection cut out and lit),
/// and the stroke as a red line with a soft glow.
class CirclePainter extends CustomPainter {
  CirclePainter({
    required this.strokes,
    this.version = 0,
    required this.selection,
    required this.accent,
    required this.dim,
    required this.dot,
  });

  final List<List<Offset>> strokes;

  /// Changes whenever [strokes] do (they are mutated in place).
  final int version;
  final Rect? selection;
  final Color accent, dim, dot;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    final sel = selection;
    final hole = sel == null
        ? null
        : RRect.fromRectAndRadius(
            sel.inflate(CircleSizes.padding),
            const Radius.circular(CircleSizes.selectionRadius),
          );
    final shade = hole == null
        ? (Path()..addRect(all))
        : Path.combine(
            PathOperation.difference,
            Path()..addRect(all),
            Path()..addRRect(hole),
          );
    canvas.drawPath(shade, Paint()..color = dim);
    // The dot grid, only over the dimmed part.
    canvas.save();
    canvas.clipPath(shade);
    final dots = Paint()..color = dot;
    for (
      var y = CircleSizes.dotSpacing / 2;
      y < size.height;
      y += CircleSizes.dotSpacing
    ) {
      for (
        var x = CircleSizes.dotSpacing / 2;
        x < size.width;
        x += CircleSizes.dotSpacing
      ) {
        canvas.drawCircle(Offset(x, y), CircleSizes.dotRadius, dots);
      }
    }
    canvas.restore();
    if (hole != null) {
      canvas.drawRRect(
        hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = CircleSizes.stroke
          ..color = accent.withValues(alpha: CircleSizes.glowAlpha)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            CircleSizes.glowBlur,
          ),
      );
      canvas.drawRRect(
        hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppBorder.thick
          ..color = accent,
      );
    }
    for (final points in strokes) {
      _stroke(canvas, points);
    }
  }

  void _stroke(Canvas canvas, List<Offset> points) {
    if (points.isEmpty) return;
    final path = smoothPath(points);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = CircleSizes.glow
        ..color = accent.withValues(alpha: CircleSizes.glowAlpha)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          CircleSizes.glowBlur,
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = CircleSizes.stroke
        ..color = accent,
    );
    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        CircleSizes.stroke,
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(CirclePainter old) =>
      old.version != version ||
      old.strokes.length != strokes.length ||
      old.selection != selection ||
      old.accent != accent ||
      old.dim != dim ||
      old.dot != dot;
}
