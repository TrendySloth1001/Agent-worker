import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_structure.dart';
import '../../../../core/theme/app_palette.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

class ProgressRow {
  const ProgressRow(this.label, this.value, this.max, this.note, this.rating);
  final String label, note;
  final double value, max;

  /// True for `rating:` rows, drawn as dots instead of a segmented bar.
  final bool rating;

  double get fraction => max <= 0 ? 0 : (value / max).clamp(0.0, 1.0);
}

class ProgressData {
  const ProgressData(this.title, this.rows);
  final String title;
  final List<ProgressRow> rows;
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Parses a ```progress block: `bar: label | value | max | note` (max
/// defaults to 100) and `rating: label | value | max | note` (max
/// defaults to 5). Null when no row is valid.
ProgressData? parseProgress(String src) {
  var title = '';
  final rows = <ProgressRow>[];
  for (final line in playfulLines(src)) {
    final kv = playfulKeyValue(line);
    if (kv == null) continue;
    final (key, value) = kv;
    if (key == 'title') {
      title = value;
      continue;
    }
    if ((key != 'bar' && key != 'rating') || rows.length >= StructLimits.bars) {
      continue;
    }
    final parts = value.split('|').map((e) => e.trim()).toList();
    if (parts.length < 2 || parts[0].isEmpty) continue;
    final v = double.tryParse(parts[1].replaceAll(RegExp(r'[%,]'), ''));
    if (v == null || !v.isFinite || v < 0) continue;
    final rating = key == 'rating';
    var max = parts.length > 2 ? double.tryParse(parts[2]) : null;
    max = (max == null || max <= 0) ? (rating ? 5 : 100) : max;
    if (rating) max = max.clamp(1, StructLimits.ratingMax).toDouble();
    rows.add(
      ProgressRow(
        parts[0],
        v,
        max,
        parts.length > 3 ? parts.skip(3).join(' | ') : '',
        rating,
      ),
    );
  }
  if (rows.isEmpty) return null;
  return ProgressData(title, rows);
}

/// ```progress block: dot-matrix progress bars and rating dots.
class ProgressCard extends StatefulWidget {
  const ProgressCard({super.key, required this.source});

  final String source;

  @override
  State<ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<ProgressCard> {
  late ProgressData? _data = parseProgress(widget.source);

  @override
  void didUpdateWidget(ProgressCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _data = parseProgress(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(
        title: StructStrings.progress,
        source: widget.source,
      );
    }
    return RichCard(
      title: d.title.isEmpty
          ? StructStrings.progress
          : '${StructStrings.progress} / ${d.title.toUpperCase()}',
      child: Padding(
        padding: const EdgeInsets.all(StructSizes.pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < d.rows.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              _Row(row: d.rows[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});

  final ProgressRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final value = row.rating
        ? '${_num(row.value)}/${_num(row.max)}'
        : row.max == 100
        ? '${_num(row.value)}%'
        : '${_num(row.value)}/${_num(row.max)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall,
              ),
            ),
            Text(value, style: t.caption.copyWith(color: p.textSecondary)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        row.rating
            ? _Dots(row: row)
            : SizedBox(
                height: StructSizes.barHeight,
                child: CustomPaint(
                  painter: SegmentBarPainter(
                    fraction: row.fraction,
                    on: p.accent,
                    off: p.border,
                  ),
                ),
              ),
        if (row.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              row.note,
              style: t.caption.copyWith(color: p.textTertiary),
            ),
          ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.row});

  final ProgressRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = row.max.round();
    final filled = row.value.clamp(0, row.max);
    return Row(
      children: [
        for (var i = 0; i < n; i++)
          Padding(
            padding: const EdgeInsets.only(right: StructSizes.ratingGap),
            child: Container(
              width: StructSizes.ratingDot,
              height: StructSizes.ratingDot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i + 1 <= filled
                    ? p.accent
                    : i < filled
                    ? p.accent.withValues(alpha: 0.5)
                    : p.border,
              ),
            ),
          ),
      ],
    );
  }
}

/// Dot-matrix style bar: a row of small squares, the first
/// `fraction * segments` lit.
class SegmentBarPainter extends CustomPainter {
  SegmentBarPainter({
    required this.fraction,
    required this.on,
    required this.off,
  });

  final double fraction;
  final Color on, off;

  @override
  void paint(Canvas canvas, Size size) {
    const n = StructSizes.barSegments;
    final w = (size.width - StructSizes.barGap * (n - 1)) / n;
    final lit = fraction * n;
    for (var i = 0; i < n; i++) {
      final x = i * (w + StructSizes.barGap);
      final color = i + 1 <= lit + 1e-6
          ? on
          : i < lit
          ? on.withValues(alpha: 0.5)
          : off;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, w, size.height),
          const Radius.circular(1),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(SegmentBarPainter old) =>
      old.fraction != fraction || old.on != on || old.off != off;
}
