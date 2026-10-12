import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_structure.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

class TreeNode {
  TreeNode(this.text, this.depth);
  final String text;
  final int depth;
  final List<TreeNode> children = [];
}

class TreeData {
  const TreeData(this.title, this.roots, this.count);
  final String title;
  final List<TreeNode> roots;
  final int count;
}

/// Parses a ```tree block: indented lines (2+ spaces or a tab per level, an
/// optional `- ` bullet is ignored). Depth is normalised so odd indents
/// still nest sensibly. Null when there are no nodes.
TreeData? parseTree(String src) {
  var title = '';
  final roots = <TreeNode>[];
  final stack = <(int, TreeNode)>[]; // (raw indent, node)
  var count = 0;
  for (final raw in src.replaceAll('\r\n', '\n').split('\n')) {
    if (raw.trim().isEmpty) continue;
    final expanded = raw.replaceAll('\t', '  ');
    final kv = playfulKeyValue(expanded.trim());
    if (kv != null && kv.$1 == 'title' && title.isEmpty && stack.isEmpty) {
      title = kv.$2;
      continue;
    }
    if (count >= StructLimits.treeNodes) break;
    final indent = expanded.length - expanded.trimLeft().length;
    var text = expanded.trim();
    text = text.replaceFirst(RegExp(r'^[-*+•]\s+'), '').trim();
    if (text.isEmpty) continue;
    while (stack.isNotEmpty && stack.last.$1 >= indent) {
      stack.removeLast();
    }
    final depth = stack.length;
    if (depth >= StructLimits.treeDepth) continue;
    final node = TreeNode(text, depth);
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.$2.children.add(node);
    }
    stack.add((indent, node));
    count++;
  }
  if (roots.isEmpty) return null;
  return TreeData(title, roots, count);
}

/// ```tree block: collapsible outline with painted connector lines.
class TreeCard extends StatefulWidget {
  const TreeCard({super.key, required this.source});

  final String source;

  @override
  State<TreeCard> createState() => _TreeCardState();
}

class _TreeCardState extends State<TreeCard> {
  late TreeData? _data = parseTree(widget.source);
  final Set<TreeNode> _closed = {};

  @override
  void didUpdateWidget(TreeCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _data = parseTree(widget.source);
      _closed.clear();
    }
  }

  /// Flattened visible rows with, per row, whether each ancestor level still
  /// has later siblings (to keep the vertical guide going).
  void _walk(
    List<TreeNode> nodes,
    List<bool> guides,
    List<(TreeNode, List<bool>, bool)> out,
  ) {
    for (var i = 0; i < nodes.length; i++) {
      final last = i == nodes.length - 1;
      final n = nodes[i];
      out.add((n, guides, last));
      if (n.children.isNotEmpty && !_closed.contains(n)) {
        _walk(n.children, [...guides, !last], out);
      }
    }
  }

  void _toggleAll(TreeData d) {
    Haptics.tap();
    setState(() {
      if (_closed.isEmpty) {
        void add(List<TreeNode> ns) {
          for (final n in ns) {
            if (n.children.isNotEmpty) _closed.add(n);
            add(n.children);
          }
        }

        add(d.roots);
        // Keep the roots open so something is always visible.
        for (final r in d.roots) {
          _closed.remove(r);
        }
      } else {
        _closed.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(title: StructStrings.tree, source: widget.source);
    }
    final rows = <(TreeNode, List<bool>, bool)>[];
    _walk(d.roots, const [], rows);
    final p = context.palette;
    final t = context.text;
    return RichCard(
      title: d.title.isEmpty
          ? StructStrings.tree
          : '${StructStrings.tree} / ${d.title.toUpperCase()}',
      trailing: d.count > 6
          ? GestureDetector(
              onTap: () => _toggleAll(d),
              behavior: HitTestBehavior.opaque,
              child: Text(
                _closed.isEmpty
                    ? StructStrings.collapseAll
                    : StructStrings.expandAll,
                style: t.caption.copyWith(color: p.accent),
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: StructSizes.pad,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (node, guides, last) in rows)
              _TreeRow(
                node: node,
                guides: guides,
                last: last,
                closed: _closed.contains(node),
                onTap: node.children.isEmpty
                    ? null
                    : () {
                        Haptics.tap();
                        setState(() {
                          if (!_closed.remove(node)) _closed.add(node);
                        });
                      },
              ),
          ],
        ),
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.guides,
    required this.last,
    required this.closed,
    this.onTap,
  });

  final TreeNode node;
  final List<bool> guides;
  final bool last, closed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final isRoot = node.depth == 0;
    final branch = node.children.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: StructSizes.treeRowHeight),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (node.depth > 0)
                SizedBox(
                  width: StructSizes.treeIndent * node.depth,
                  child: CustomPaint(
                    painter: TreeGuidePainter(
                      guides: guides,
                      last: last,
                      indent: StructSizes.treeIndent,
                      color: p.borderStrong,
                      stroke: StructSizes.treeStroke,
                    ),
                  ),
                ),
              Center(
                child: Container(
                  width: StructSizes.treeDot * 2,
                  height: StructSizes.treeDot * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: branch && !closed ? p.accent : null,
                    border: Border.all(
                      color: branch ? p.accent : p.textTertiary,
                      width: AppBorder.thin,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      node.text,
                      style: isRoot
                          ? t.bodySmall.copyWith(fontWeight: FontWeight.w700)
                          : t.bodySmall.copyWith(
                              color: branch ? p.textPrimary : p.textSecondary,
                            ),
                    ),
                  ),
                ),
              ),
              if (branch && closed)
                Center(
                  child: Text(
                    '+${_descendants(node)}',
                    style: t.caption.copyWith(color: p.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static int _descendants(TreeNode n) {
    var c = 0;
    for (final k in n.children) {
      c += 1 + _descendants(k);
    }
    return c;
  }
}

/// Elbow connectors: vertical guides for ancestors that continue, plus an
/// elbow into this row's dot.
class TreeGuidePainter extends CustomPainter {
  TreeGuidePainter({
    required this.guides,
    required this.last,
    required this.indent,
    required this.color,
    required this.stroke,
  });

  /// One flag per ancestor level (index 0 = root level): true when that
  /// ancestor has later siblings. Index `depth - 1` is the parent level.
  final List<bool> guides;
  final bool last;
  final double indent, stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;
    final mid = size.height / 2;
    // Cell k (k-th indent slot) belongs to the ancestor at depth k + 1.
    for (var i = 1; i < guides.length; i++) {
      if (!guides[i]) continue;
      final gx = indent * (i - 1) + indent / 2;
      canvas.drawLine(Offset(gx, 0), Offset(gx, size.height), paint);
    }
    final px = indent * (guides.length - 1) + indent / 2;
    canvas.drawLine(Offset(px, 0), Offset(px, last ? mid : size.height), paint);
    canvas.drawLine(Offset(px, mid), Offset(size.width, mid), paint);
  }

  @override
  bool shouldRepaint(TreeGuidePainter old) =>
      old.last != last || old.color != color || old.guides != guides;
}
