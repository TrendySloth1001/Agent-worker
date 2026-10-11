/// Lane layout for the git graph widget (pure Dart, no Flutter).
///
/// Standard git-graph assignment: commits are walked in display order
/// (newest first, children above parents) while keeping a list of active
/// lanes, each waiting for one specific commit. A commit takes the lane that
/// waits for it (the default-branch lane, else the leftmost, when several do;
/// the others close into it), or a new lane on the right. Its first parent
/// continues its lane; further parents join a lane already waiting for them
/// or open new lanes (branch-off curves). Lanes are compacted between rows,
/// which draws as diagonal shifts.
library;

/// One commit as the layout sees it.
class GraphNode {
  const GraphNode(this.sha, this.parents);
  final String sha;
  final List<String> parents;
}

enum GraphLineKind {
  /// Same column on both rows.
  straight,

  /// A lane moving left after lanes to its left closed.
  shift,

  /// A lane closing into the commit below (merge-in / branch point).
  merge,

  /// From a commit to a new lane for one of its extra parents.
  fork,

  /// From a commit into a lane that already waits for that parent.
  join,
}

/// A line between this row's [from] column and the next row's [to] column.
class GraphLine {
  const GraphLine(this.from, this.to, this.color, this.kind);
  final int from, to, color;
  final GraphLineKind kind;

  @override
  String toString() => '$from>$to:${kind.name}';
}

/// Layout of one row.
class GraphRow {
  GraphRow({
    required this.lane,
    required this.color,
    required this.merge,
    required this.up,
    required this.danglingFirst,
    required this.danglingExtra,
  });

  /// Column of the commit dot.
  final int lane;

  /// Color index of the commit's lane (0 = the default branch).
  final int color;

  /// More than one parent (drawn as a hollow dot, dimmer text).
  final bool merge;

  /// Lines from the previous row into this one.
  final List<GraphLine> up;

  /// Lines from this row into the next one.
  List<GraphLine> down = const [];

  /// The first parent is not in the loaded history (line runs off).
  final bool danglingFirst;

  /// Extra parents not in the loaded history (short stubs).
  final int danglingExtra;

  /// Columns this row touches (commit and lines above and below).
  int get width {
    var w = lane + 1;
    for (final l in [...up, ...down]) {
      if (l.from + 1 > w) w = l.from + 1;
      if (l.to + 1 > w) w = l.to + 1;
    }
    return w;
  }
}

class GraphLayout {
  const GraphLayout(this.rows, this.width);
  final List<GraphRow> rows;

  /// Widest row.
  final int width;

  /// Color index of the row whose commit is [index], for ref pills.
  int colorOf(int index) => rows[index].color;
}

class _Lane {
  _Lane(this.expect, this.color);
  final String expect;
  int color;
}

/// A line waiting in the gap below a row for its destination column.
class _Pending {
  _Pending(this.from, this.lane, this.kind);
  final int from;
  final _Lane lane;
  final GraphLineKind kind;
}

/// Lays out [nodes] (display order). [defaultHead] is the default branch's
/// head: its first-parent chain keeps color 0. [colorCount] colors are
/// cycled for the other lanes (0 is never reused).
GraphLayout layoutGraph(
  List<GraphNode> nodes, {
  String? defaultHead,
  int colorCount = 8,
}) {
  final known = {for (final n in nodes) n.sha};
  final bySha = {for (final n in nodes) n.sha: n};
  final mainChain = <String>{};
  var s = defaultHead;
  while (s != null && bySha.containsKey(s) && mainChain.add(s)) {
    final ps = bySha[s]!.parents;
    s = ps.isEmpty ? null : ps.first;
  }

  var nextColor = 0;
  int newColor() {
    final usable = colorCount - 1;
    if (usable <= 0) return 0;
    return 1 + (nextColor++ % usable);
  }

  var lanes = <_Lane>[];
  var pending = <_Pending>[];
  final rows = <GraphRow>[];
  var maxWidth = 0;

  for (final node in nodes) {
    final sha = node.sha;
    final parents = <String>[];
    for (final p in node.parents) {
      if (!parents.contains(p)) parents.add(p);
    }
    final onMain = mainChain.contains(sha);

    // The lane this commit takes.
    final matches = [
      for (var j = 0; j < lanes.length; j++)
        if (lanes[j].expect == sha) j,
    ];
    int lane;
    int color;
    if (matches.isEmpty) {
      lane = lanes.length;
      color = onMain ? 0 : newColor();
    } else {
      lane = onMain
          ? matches.firstWhere((j) => lanes[j].color == 0, orElse: () => -1)
          : -1;
      if (lane < 0) lane = matches.first;
      color = onMain ? 0 : lanes[lane].color;
    }

    // Lines from the previous row land here.
    int columnOf(_Lane l) => l.expect == sha ? lane : lanes.indexOf(l);
    final up = [
      for (final p in pending)
        GraphLine(
          p.from,
          columnOf(p.lane),
          p.lane.color,
          p.lane.expect == sha && columnOf(p.lane) != p.from
              ? (p.kind == GraphLineKind.straight ||
                        p.kind == GraphLineKind.shift
                    ? GraphLineKind.merge
                    : p.kind)
              : p.kind == GraphLineKind.straight && columnOf(p.lane) != p.from
              ? GraphLineKind.shift
              : p.kind,
        ),
    ];
    if (rows.isNotEmpty) rows.last.down = up;

    // Lanes after this row: matched lanes close, the first parent continues.
    final next = <_Lane>[];
    final out = <_Pending>[];
    _Lane? own;
    final firstKnown = parents.isNotEmpty && known.contains(parents.first);
    for (var j = 0; j < lanes.length; j++) {
      final l = lanes[j];
      if (l.expect == sha) {
        if (j == lane && firstKnown) {
          own = _Lane(parents.first, color);
          next.add(own);
          out.add(_Pending(lane, own, GraphLineKind.straight));
        }
        continue;
      }
      next.add(l);
      out.add(_Pending(j, l, GraphLineKind.straight));
    }
    if (matches.isEmpty && firstKnown) {
      own = _Lane(parents.first, color);
      next.add(own);
      out.add(_Pending(lane, own, GraphLineKind.straight));
    }

    // Extra parents: join a waiting lane or branch off into a new one.
    var danglingExtra = 0;
    for (final p in parents.skip(1)) {
      if (!known.contains(p)) {
        danglingExtra++;
        continue;
      }
      final waiting = next.where((l) => l.expect == p).firstOrNull;
      if (waiting != null) {
        out.add(_Pending(lane, waiting, GraphLineKind.join));
      } else {
        final l = _Lane(p, newColor());
        next.add(l);
        out.add(_Pending(lane, l, GraphLineKind.fork));
      }
    }

    final row = GraphRow(
      lane: lane,
      color: color,
      merge: parents.length > 1,
      up: up,
      danglingFirst: parents.isNotEmpty && !firstKnown,
      danglingExtra: danglingExtra,
    );
    rows.add(row);
    lanes = next;
    pending = out;
  }

  // Lines still open below the last row run straight off the bottom.
  if (rows.isNotEmpty && pending.isNotEmpty) {
    rows.last.down = [
      for (final p in pending)
        GraphLine(p.from, p.from, p.lane.color, GraphLineKind.straight),
    ];
  }
  for (final r in rows) {
    if (r.width > maxWidth) maxWidth = r.width;
  }
  return GraphLayout(rows, maxWidth);
}
