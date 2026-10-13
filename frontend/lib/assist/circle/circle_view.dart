import 'dart:io';

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

  /// The view for a screenshot file.
  static ImageProvider fileImage(String path) => FileImage(File(path));

  @override
  State<CircleView> createState() => _CircleViewState();
}

class _CircleViewState extends State<CircleView> {
  final _points = <Offset>[];
  bool _drawing = false;

  void _start(Offset p) {
    Haptics.tick();
    setState(() {
      _drawing = true;
      _points
        ..clear()
        ..add(p);
    });
  }

  void _move(Offset p) {
    if (!_drawing) return;
    if ((p - _points.last).distance < CircleSizes.minPointGap) return;
    setState(() => _points.add(p));
  }

  void _end(Size view) {
    if (!_drawing) return;
    setState(() => _drawing = false);
    final box = selectionOf(_points, view: view);
    if (box == null) {
      widget.onEmpty?.call();
      return;
    }
    Haptics.send();
    widget.onSelect(box, view);
  }

  void _tap(Offset p, Size view) {
    if (widget.busy) return;
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
                  // The stroke while drawing and cutting out; then the lit box.
                  points: _drawing || widget.busy ? List.of(_points) : const [],
                  selection: _drawing ? null : widget.selection,
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
              onPanStart: widget.busy ? null : (d) => _start(d.localPosition),
              onPanUpdate: widget.busy ? null : (d) => _move(d.localPosition),
              onPanEnd: widget.busy ? null : (_) => _end(view),
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
    required this.points,
    required this.selection,
    required this.accent,
    required this.dim,
    required this.dot,
  });

  final List<Offset> points;
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
      old.points.length != points.length ||
      old.selection != selection ||
      old.accent != accent ||
      old.dim != dim ||
      old.dot != dot;
}
