import 'dart:math' as math;
import 'dart:ui';

import '../../core/constants/circle_search.dart';
import '../screen_text.dart';

/// The pure math of "Circle to search": from a finger stroke to a box on the
/// view, from the view to the screenshot's pixels and the screen's pixels,
/// and which text nodes the selection covers. The screenshot fills the view
/// (BoxFit.fill), so each mapping is a plain per-axis scale.

/// The selected box (view coordinates) of a stroke: its bounding box, or for
/// a tap (a stroke smaller than [tapSlop]) a [tapSize] square around it.
/// Clamped to [view]. Null for an empty stroke.
Rect? selectionOf(
  List<Offset> points, {
  required Size view,
  double tapSize = CircleSizes.tapSize,
  double tapSlop = CircleSizes.tapSlop,
}) {
  if (points.isEmpty) return null;
  var l = points.first.dx, t = points.first.dy;
  var r = l, b = t;
  for (final p in points) {
    l = math.min(l, p.dx);
    t = math.min(t, p.dy);
    r = math.max(r, p.dx);
    b = math.max(b, p.dy);
  }
  var box = Rect.fromLTRB(l, t, r, b);
  if (box.width < tapSlop && box.height < tapSlop) {
    box = Rect.fromCenter(center: box.center, width: tapSize, height: tapSize);
  }
  final bounds = Offset.zero & view;
  final clamped = box.intersect(bounds);
  return clamped.isEmpty ? null : clamped;
}

/// Scales [rect] from a [from]-sized space to a [to]-sized one.
Rect mapRect(Rect rect, Size from, Size to) {
  final sx = to.width / from.width;
  final sy = to.height / from.height;
  return Rect.fromLTRB(
    rect.left * sx,
    rect.top * sy,
    rect.right * sx,
    rect.bottom * sy,
  );
}

/// The pixels of the screenshot to cut out for [selection] (view
/// coordinates): the box grown by [padding] view px, mapped onto [image],
/// rounded outwards to whole pixels and kept inside the image. Null when it
/// is smaller than [minSide] pixels.
Rect? cropRectFor(
  Rect selection, {
  required Size view,
  required Size image,
  double padding = CircleSizes.padding,
  int minSide = CircleSizes.minCropSide,
}) {
  if (view.isEmpty || image.isEmpty) return null;
  final mapped = mapRect(selection.inflate(padding), view, image);
  final px = Rect.fromLTRB(
    mapped.left.floorToDouble(),
    mapped.top.floorToDouble(),
    mapped.right.ceilToDouble(),
    mapped.bottom.ceilToDouble(),
  ).intersect(Offset.zero & image);
  if (px.width < minSide || px.height < minSide) return null;
  return px;
}

/// The text nodes the selection [screenRect] (screen pixels) covers, in
/// their reading order: a node counts when the selection holds a good part
/// of it, or when it holds a good part of the selection.
List<ScreenNode> nodesIn(Rect screenRect, List<ScreenNode> nodes) {
  final area = screenRect.width * screenRect.height;
  if (area <= 0) return const [];
  return [
    for (final n in nodes)
      if (n.bounds case final b?)
        if (_covers(screenRect, area, b)) n,
  ];
}

bool _covers(Rect sel, double selArea, Rect node) {
  if (!sel.overlaps(node)) return false;
  final o = sel.intersect(node);
  final overlap = o.width * o.height;
  final nodeArea = node.width * node.height;
  return (nodeArea > 0 && overlap / nodeArea >= CircleSizes.nodeShare) ||
      overlap / selArea >= CircleSizes.selectionShare;
}

/// The text of the selection: the covered nodes as one block, trimmed and
/// deduped like the whole screen's text.
String selectionText(
  Rect selection, {
  required Size view,
  required ScreenContext screen,
  int maxChars = CircleSizes.maxSelectionChars,
}) {
  final size = screen.screenSize;
  if (size == null || screen.nodes.isEmpty) return '';
  final rect = mapRect(selection, view, size);
  return buildScreenText(nodesIn(rect, screen.nodes), maxChars: maxChars);
}

/// A smooth path through [points] (quadratic curves through the midpoints),
/// so a quick scribble draws as a soft line rather than a polyline.
Path smoothPath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length < 3) {
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }
  for (var i = 1; i < points.length - 1; i++) {
    final p = points[i];
    final next = points[i + 1];
    final mid = Offset((p.dx + next.dx) / 2, (p.dy + next.dy) / 2);
    path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}
