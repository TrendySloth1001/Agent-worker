import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'md_blocks.dart';
import 'inline_icon.dart';

/// Where one list level sits: its left edge and marker size, in the
/// coordinates of the whole list.
class _Geo {
  const _Geo(this.left, this.marker);
  final double left;
  final double marker;
  double get center => left + marker / 2;
  double get gutter => marker + MdSizes.tlGutterGap;
}

double _markerSize(int depth, bool ordered, {bool icons = false}) {
  if (icons) {
    return depth == 0 ? MdSizes.tlIconMarker : MdSizes.tlIconMarkerNested;
  }
  if (ordered) {
    return depth == 0 ? MdSizes.tlMarkerOrdered : MdSizes.tlMarkerOrderedNested;
  }
  return depth == 0 ? MdSizes.tlMarker : MdSizes.tlMarkerNested;
}

double _spineWidth(int depth) =>
    depth == 0 ? MdSizes.tlSpine : MdSizes.tlSpineNested;

/// A list drawn as a connected timeline: one spine through the markers, with
/// nested items branching off it.
class TimelineList extends StatelessWidget {
  const TimelineList({super.key, required this.list, required this.renderText});

  final MdList list;

  /// Renders one item's markdown.
  final Widget Function(String text) renderText;

  @override
  Widget build(BuildContext context) {
    final body = context.text.body;
    final firstLineCenter = (body.fontSize ?? 0) * (body.height ?? 1) / 2;
    final geo = _Geo(0, _markerSize(0, list.ordered, icons: list.hasIcons));
    return _Items(
      list: list,
      depth: 0,
      chain: [geo],
      through: const [],
      parentIsLast: true,
      firstLineCenter: firstLineCenter,
      renderText: renderText,
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({
    required this.list,
    required this.depth,
    required this.chain,
    required this.through,
    required this.parentIsLast,
    required this.firstLineCenter,
    required this.renderText,
  });

  final MdList list;
  final int depth;

  /// Geometry of every level down to this one (last = this level).
  final List<_Geo> chain;

  /// For each ancestor spine: does it run the full height of an item here?
  final List<bool> through;
  final bool parentIsLast;
  final double firstLineCenter;
  final Widget Function(String) renderText;

  @override
  Widget build(BuildContext context) {
    final n = list.items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++)
          _ItemTile(
            item: list.items[i],
            ordered: list.ordered,
            isFirst: i == 0,
            isLast: i == n - 1,
            depth: depth,
            chain: chain,
            through: depth == 0
                ? const []
                : [...through, !parentIsLast || i != n - 1],
            firstLineCenter: firstLineCenter,
            renderText: renderText,
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.ordered,
    required this.isFirst,
    required this.isLast,
    required this.depth,
    required this.chain,
    required this.through,
    required this.firstLineCenter,
    required this.renderText,
  });

  final MdItem item;
  final bool ordered;
  final bool isFirst;
  final bool isLast;
  final int depth;
  final List<_Geo> chain;

  /// One entry per ancestor spine (see [_Items.through]).
  final List<bool> through;
  final double firstLineCenter;
  final Widget Function(String) renderText;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final geo = chain.last;
    final kids = item.children;
    final hasKids = kids != null && kids.items.isNotEmpty;
    final markerBox = item.checked != null ? MdSizes.tlCheckbox : geo.marker;

    final head = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _HeadPainter(
              color: p.borderStrong,
              width: _spineWidth(depth),
              markerCenterX: geo.marker / 2,
              markerCenterY: firstLineCenter,
              markerRadius: markerBox / 2,
              lineAbove: !isFirst,
              lineBelow: !isLast || hasKids,
              branchFromDx: depth == 0
                  ? null
                  : chain[depth - 1].center - geo.left,
              branchWidth: depth == 0 ? 0 : _spineWidth(depth - 1),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: geo.gutter, bottom: MdSizes.tlItemGap),
          child: renderText(item.body),
        ),
        Positioned(
          left: geo.marker / 2 - markerBox / 2,
          top: firstLineCenter - markerBox / 2,
          child: _Marker(
            item: item,
            ordered: ordered,
            isFirst: isFirst,
            isLast: isLast,
            depth: depth,
            box: markerBox,
          ),
        ),
      ],
    );

    Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        head,
        if (hasKids)
          Padding(
            padding: EdgeInsets.only(left: geo.gutter),
            child: _Items(
              list: kids,
              depth: depth + 1,
              chain: [
                ...chain,
                _Geo(
                  geo.left + geo.gutter,
                  _markerSize(depth + 1, kids.ordered, icons: kids.hasIcons),
                ),
              ],
              through: through,
              parentIsLast: isLast,
              firstLineCenter: firstLineCenter,
              renderText: renderText,
            ),
          ),
      ],
    );

    if (depth > 0) {
      column = CustomPaint(
        painter: _AncestorPainter(
          color: p.borderStrong,
          dx: [for (var k = 0; k < depth; k++) chain[k].center - geo.left],
          widths: [for (var k = 0; k < depth; k++) _spineWidth(k)],
          through: through,
          curveStartY: firstLineCenter - MdSizes.tlCurveRadius,
        ),
        child: column,
      );
    }
    return column;
  }
}

/// Spines of the ancestors, running down the side of a nested item.
class _AncestorPainter extends CustomPainter {
  _AncestorPainter({
    required this.color,
    required this.dx,
    required this.widths,
    required this.through,
    required this.curveStartY,
  });

  final Color color;
  final List<double> dx;
  final List<double> widths;
  final List<bool> through;
  final double curveStartY;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (var k = 0; k < dx.length; k++) {
      paint.strokeWidth = widths[k];
      if (through[k]) {
        canvas.drawLine(Offset(dx[k], 0), Offset(dx[k], size.height), paint);
      } else if (k == dx.length - 1) {
        canvas.drawLine(Offset(dx[k], 0), Offset(dx[k], curveStartY), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_AncestorPainter old) =>
      old.color != color ||
      old.curveStartY != curveStartY ||
      old.through.length != through.length ||
      !_same(old.through, through) ||
      !_same(old.dx, dx);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// This item's own spine segments and the curve from its parent's spine.
class _HeadPainter extends CustomPainter {
  _HeadPainter({
    required this.color,
    required this.width,
    required this.markerCenterX,
    required this.markerCenterY,
    required this.markerRadius,
    required this.lineAbove,
    required this.lineBelow,
    required this.branchFromDx,
    required this.branchWidth,
  });

  final Color color;
  final double width;
  final double markerCenterX;
  final double markerCenterY;
  final double markerRadius;
  final bool lineAbove;
  final bool lineBelow;
  final double? branchFromDx;
  final double branchWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    final x = markerCenterX;
    final y = markerCenterY;
    if (lineAbove) {
      canvas.drawLine(Offset(x, 0), Offset(x, y - markerRadius), paint);
    }
    if (lineBelow) {
      canvas.drawLine(
        Offset(x, y + markerRadius),
        Offset(x, size.height),
        paint,
      );
    }
    final from = branchFromDx;
    if (from != null) {
      const r = MdSizes.tlCurveRadius;
      paint.strokeWidth = branchWidth;
      final path = Path()
        ..moveTo(from, y - r)
        ..quadraticBezierTo(from, y, from + r, y)
        ..lineTo(x - markerRadius, y);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_HeadPainter old) =>
      old.color != color ||
      old.lineAbove != lineAbove ||
      old.lineBelow != lineBelow ||
      old.markerCenterY != markerCenterY ||
      old.markerCenterX != markerCenterX ||
      old.markerRadius != markerRadius ||
      old.branchFromDx != branchFromDx;
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.item,
    required this.ordered,
    required this.isFirst,
    required this.isLast,
    required this.depth,
    required this.box,
  });

  final MdItem item;
  final bool ordered;
  final bool isFirst;
  final bool isLast;
  final int depth;
  final double box;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stroke = BorderSide(
      color: p.textPrimary,
      width: MdSizes.tlMarkerStroke,
    );
    final icon = item.icon;
    if (icon != null) {
      final parts = icon.split(':');
      // The background hides the spine behind the icon's transparent parts.
      return Container(
        width: box,
        height: box,
        color: p.background,
        child: InlineIcon(
          set: parts.first,
          name: parts.last,
          size: box,
          color: p.textPrimary,
          // No matching icon: the usual hollow circle.
          fallback: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(stroke),
            ),
          ),
        ),
      );
    }

    final checked = item.checked;
    if (checked != null) {
      return Container(
        width: box,
        height: box,
        decoration: BoxDecoration(
          color: checked ? p.textPrimary : null,
          borderRadius: BorderRadius.circular(MdSizes.tlMarkerRadius),
          border: Border.fromBorderSide(stroke),
        ),
        child: checked
            ? AppIcon(AppIcons.check, size: box - 2, color: p.textInverse)
            : null,
      );
    }

    if (ordered) {
      return Container(
        width: box,
        height: box,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: depth == 0 ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: depth == 0
              ? BorderRadius.circular(MdSizes.tlMarkerRadius)
              : null,
          border: Border.fromBorderSide(stroke),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${item.number}',
            style: context.text.caption.copyWith(
              color: p.textPrimary,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ),
      );
    }

    if (depth > 0) {
      return Container(
        width: box,
        height: box,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.fromBorderSide(stroke),
        ),
      );
    }

    // One item: nothing to connect, so a plain bullet dot (a lone filled
    // square read as a stray "■" glyph).
    if (isFirst && isLast) {
      return SizedBox.square(
        dimension: box,
        child: Center(
          child: Container(
            width: box * MdSizes.tlSingleDotScale,
            height: box * MdSizes.tlSingleDotScale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.textPrimary,
            ),
          ),
        ),
      );
    }
    if (isFirst) {
      return Container(
        width: box,
        height: box,
        decoration: BoxDecoration(
          color: p.textPrimary,
          borderRadius: BorderRadius.circular(MdSizes.tlMarkerRadius),
        ),
      );
    }
    if (isLast) {
      return SizedBox.square(
        dimension: box,
        child: Center(
          child: RotationTransition(
            turns: const AlwaysStoppedAnimation(MdSizes.tlDiamondTurns),
            child: Container(
              width: box * MdSizes.tlDiamondScale,
              height: box * MdSizes.tlDiamondScale,
              color: p.textPrimary,
            ),
          ),
        ),
      );
    }
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(stroke),
      ),
    );
  }
}
