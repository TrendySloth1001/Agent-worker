import 'package:flutter/material.dart';

import '../../../../core/constants/widget_chart.dart';
import '../../../../core/theme/app_palette.dart';
import 'chart_model.dart';

/// The chart's data as a plain table (accessible fallback view).
class ChartTable extends StatelessWidget {
  const ChartTable({super.key, required this.spec});
  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final head = <String>[];
    final rows = <List<String>>[];
    final u = spec.unit;
    String cell(double? v) => v == null ? '–' : fmtWithUnit(v, u);
    if (spec.isPie) {
      final total = spec.slices.fold<double>(0, (a, b) => a + b.value);
      head.addAll([
        spec.xLabel.isEmpty ? ChartStrings.xHeader : spec.xLabel,
        spec.yLabel.isEmpty ? ChartStrings.yHeader : spec.yLabel,
        '%',
      ]);
      for (final s in spec.slices) {
        rows.add([
          s.label,
          cell(s.value),
          '${total > 0 ? (s.value / total * 100).toStringAsFixed(1) : 0}',
        ]);
      }
    } else if (spec.isScatter) {
      head.addAll(['', ChartStrings.xHeader, ChartStrings.yHeader]);
      for (final s in spec.series) {
        for (final p in s.points) {
          rows.add([s.name, fmtGrouped(p.x), cell(p.y)]);
        }
      }
    } else {
      head.addAll([spec.xLabel, for (final s in spec.series) s.name]);
      for (var i = 0; i < spec.categoryCount; i++) {
        rows.add([
          spec.categoryLabel(i),
          for (final s in spec.series)
            cell(i < s.values.length ? s.values[i] : null),
        ]);
      }
    }
    final p = context.palette;
    final t = context.text;
    Widget c(String s, {bool header = false, bool first = false}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ChartSizes.tableCellPadH,
        vertical: ChartSizes.tableCellPadV,
      ),
      child: Text(
        header ? s.toUpperCase() : s,
        style: header
            ? t.caption
            : t.label.copyWith(color: first ? p.textSecondary : p.textPrimary),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(horizontalInside: BorderSide(color: p.border)),
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.borderStrong)),
              ),
              children: [for (final h in head) c(h, header: true)],
            ),
            for (final r in rows)
              TableRow(
                children: [
                  for (var i = 0; i < r.length; i++) c(r[i], first: i == 0),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
