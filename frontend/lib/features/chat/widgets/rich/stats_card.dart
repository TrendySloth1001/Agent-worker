import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/constants/widget_playful.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

enum StatDir { up, down, none }

class StatTile {
  const StatTile(this.label, this.value, this.delta, this.dir, this.spark);
  final String label, value, delta;
  final StatDir dir;
  final List<double> spark;
}

class StatsData {
  const StatsData(this.title, this.tiles);
  final String title;
  final List<StatTile> tiles;
}

List<double> _parseSpark(String s) => [
  for (final v in s.split(RegExp(r'[,\s]+')))
    if (double.tryParse(v) != null) double.parse(v),
].take(PlayfulLimits.sparkPoints).toList();

/// Parses a ```stats block; null when there are no stats.
StatsData? parseStats(String src) {
  var title = '';
  final raw = <(String, String, String, String)>[];
  final sparks = <String, List<double>>{};
  for (final line in playfulLines(src)) {
    final kv = playfulKeyValue(line);
    if (kv == null) continue;
    final (key, value) = kv;
    final parts = value.split('|').map((e) => e.trim()).toList();
    if (key == 'title') {
      title = value;
    } else if (key == 'stat' &&
        raw.length < PlayfulLimits.tiles &&
        parts.length >= 2 &&
        parts[0].isNotEmpty) {
      raw.add((
        parts[0],
        parts[1],
        parts.length > 2 ? parts[2] : '',
        parts.length > 3 ? parts[3].toLowerCase() : '',
      ));
    } else if (key == 'spark' && parts.length >= 2) {
      final pts = _parseSpark(parts[1]);
      if (pts.length >= 2) sparks[parts[0].toLowerCase()] = pts;
    }
  }
  if (raw.isEmpty) return null;
  return StatsData(title, [
    for (final r in raw)
      StatTile(
        r.$1,
        r.$2,
        r.$3,
        r.$4 == 'up'
            ? StatDir.up
            : r.$4 == 'down'
            ? StatDir.down
            : StatDir.none,
        sparks[r.$1.toLowerCase()] ?? const [],
      ),
  ]);
}

/// ```stats block: KPI tiles with optional sparklines.
class StatsCard extends StatefulWidget {
  const StatsCard({super.key, required this.source});

  final String source;

  @override
  State<StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<StatsCard> {
  late StatsData? _data = parseStats(widget.source);
  int? _selected;

  @override
  void didUpdateWidget(StatsCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _data = parseStats(widget.source);
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(
        title: WidgetKitStrings.stats,
        source: widget.source,
      );
    }
    final sel = _selected == null ? null : d.tiles[_selected!];
    return RichCard(
      title: d.title.isEmpty
          ? WidgetKitStrings.stats
          : '${WidgetKitStrings.stats} / ${d.title.toUpperCase()}',
      child: Padding(
        padding: const EdgeInsets.all(PlayfulSizes.pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - PlayfulSizes.statGap) / 2;
                return Wrap(
                  spacing: PlayfulSizes.statGap,
                  runSpacing: PlayfulSizes.statGap,
                  children: [
                    for (var i = 0; i < d.tiles.length; i++)
                      SizedBox(
                        width: w,
                        child: _Tile(
                          tile: d.tiles[i],
                          selected: _selected == i,
                          onTap: d.tiles[i].spark.isEmpty
                              ? null
                              : () {
                                  Haptics.tap();
                                  setState(
                                    () => _selected = _selected == i ? null : i,
                                  );
                                },
                        ),
                      ),
                  ],
                );
              },
            ),
            AnimatedSize(
              duration: PlayfulDurations.expand,
              alignment: Alignment.topCenter,
              child: sel == null
                  ? const SizedBox(width: double.infinity)
                  : _Detail(tile: sel),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.selected, this.onTap});

  final StatTile tile;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final dirIcon = tile.dir == StatDir.up
        ? PlayfulIcons.up
        : tile.dir == StatDir.down
        ? PlayfulIcons.down
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: PlayfulDurations.expand,
        constraints: const BoxConstraints(
          minHeight: PlayfulSizes.statTileMinHeight,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? p.accent : p.border,
            width: AppBorder.thin,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tile.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            DotNumber(tile.value),
            if (tile.delta.isNotEmpty || tile.spark.isNotEmpty)
              const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (tile.delta.isNotEmpty) ...[
                  if (dirIcon != null)
                    AppIcon(dirIcon, size: AppIconSize.sm, color: p.accent),
                  if (dirIcon != null) const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: Text(
                      tile.delta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
                const Spacer(),
                if (tile.spark.isNotEmpty)
                  SizedBox(
                    width: PlayfulSizes.sparkWidth,
                    height: PlayfulSizes.sparkHeight,
                    child: CustomPaint(
                      painter: _SparkPainter(
                        tile.spark,
                        line: p.textSecondary,
                        dot: p.accent,
                        dotRadius: PlayfulSizes.sparkDot,
                        stroke: PlayfulSizes.sparkStroke,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.tile});

  final StatTile tile;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final s = tile.spark;
    String f(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    Widget cell(String k, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: t.caption),
          Text(v, style: t.label),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: PlayfulSizes.statGap),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tile.label.toUpperCase(), style: t.caption),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: PlayfulSizes.sparkBigHeight,
            child: CustomPaint(
              painter: _SparkPainter(
                s,
                line: p.textPrimary,
                dot: p.accent,
                dotRadius: PlayfulSizes.sparkDot + 1,
                stroke: PlayfulSizes.sparkStroke,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              cell(PlayfulStrings.sparkFirst, f(s.first)),
              cell(PlayfulStrings.sparkMin, f(s.reduce(min))),
              cell(PlayfulStrings.sparkMax, f(s.reduce(max))),
              cell(PlayfulStrings.sparkLast, f(s.last)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(
    this.v, {
    required this.line,
    required this.dot,
    required this.dotRadius,
    required this.stroke,
  });

  final List<double> v;
  final Color line, dot;
  final double dotRadius, stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final lo = v.reduce(min), hi = v.reduce(max);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    final inset = dotRadius;
    Offset pt(int i) => Offset(
      inset + (size.width - 2 * inset) * i / (v.length - 1),
      inset + (size.height - 2 * inset) * (1 - (v[i] - lo) / span),
    );
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pt(v.length - 1), dotRadius, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.v != v || old.line != line || old.dot != dot;
}
