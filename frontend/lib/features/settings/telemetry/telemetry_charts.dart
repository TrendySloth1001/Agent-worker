import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/telemetry.dart';
import '../format.dart';
import 'telemetry_format.dart';

/// A rounded step so the y axis shows about [TelemetrySizes.chartYTicks] lines.
double _step(double max) {
  if (max <= 0) return 1;
  final raw = max / TelemetrySizes.chartYTicks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in const [1, 2, 5, 10]) {
    if (raw <= m * mag) return m * mag;
  }
  return 10 * mag;
}

FlGridData _grid(AppPalette p, double step) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: step,
  getDrawingHorizontalLine: (_) => FlLine(
    color: p.border.withValues(alpha: TelemetrySizes.chartGridAlpha),
    strokeWidth: AppBorder.thin,
    dashArray: TelemetrySizes.gridDash,
  ),
);

FlTitlesData _titles(
  BuildContext context,
  List<SeriesPoint> points,
  String bucket,
  double step,
  String Function(double) yLabel,
) {
  final style = AppTextStyles.caption.copyWith(
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
  final n = points.length;
  final every = math.max(1, (n / TelemetrySizes.chartXLabels).ceil());
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: TelemetrySizes.chartLeftAxis,
        interval: step,
        getTitlesWidget: (v, meta) => v == meta.max && v != 0
            ? const SizedBox.shrink()
            : Text(yLabel(v), style: style, maxLines: 1),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: TelemetrySizes.chartBottomAxis,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (i < 0 || i >= n || (n - 1 - i) % every != 0) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Text(axisTime(points[i].t, bucket), style: style),
          );
        },
      ),
    ),
  );
}

TextStyle _tip(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.onSurface);

/// Requests per bucket, stacked: OK part neutral, failed part red.
class RequestBars extends StatelessWidget {
  const RequestBars({super.key, required this.series});

  final TelemetrySeries series;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pts = series.points;
    final top = pts.fold<int>(0, (m, x) => math.max(m, x.requests));
    final step = _step(top.toDouble());
    final maxY = math.max(step, (top / step).ceil() * step);
    return SizedBox(
      height: TelemetrySizes.chartHeight,
      child: LayoutBuilder(
        builder: (context, c) {
          final slot =
              (c.maxWidth - TelemetrySizes.chartLeftAxis) /
              math.max(1, pts.length);
          final w = (slot * TelemetrySizes.chartBarFill).clamp(
            TelemetrySizes.chartBarMin,
            TelemetrySizes.chartBarMax,
          );
          return BarChart(
            duration: Duration.zero,
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment: BarChartAlignment.spaceBetween,
              gridData: _grid(p, step),
              borderData: FlBorderData(show: false),
              titlesData: _titles(
                context,
                pts,
                series.bucket,
                step,
                (v) => compact(v.round()),
              ),
              barGroups: [
                for (var i = 0; i < pts.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: pts[i].requests.toDouble(),
                        width: w,
                        borderRadius: BorderRadius.circular(
                          TelemetrySizes.chartBarRadius,
                        ),
                        color: p.textPrimary,
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            (pts[i].requests - pts[i].failed).toDouble(),
                            p.textSecondary,
                          ),
                          BarChartRodStackItem(
                            (pts[i].requests - pts[i].failed).toDouble(),
                            pts[i].requests.toDouble(),
                            p.accent,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) =>
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  tooltipBorder: BorderSide(color: p.border),
                  tooltipBorderRadius: BorderRadius.circular(AppRadius.md),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, gi, rod, ri) {
                    final x = pts[group.x];
                    return BarTooltipItem(
                      '${clock(x.t)}\n'
                      '${x.requests} ${TelemetryStrings.requests}\n'
                      '${x.failed} ${TelemetryStrings.failed}',
                      _tip(context),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Up to two line series over the same buckets (second one dashed red).
class SeriesLines extends StatelessWidget {
  const SeriesLines({
    super.key,
    required this.series,
    required this.first,
    required this.second,
    required this.firstLabel,
    required this.secondLabel,
    required this.format,
  });

  final TelemetrySeries series;
  final num? Function(SeriesPoint) first, second;
  final String firstLabel, secondLabel;
  final String Function(num) format;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pts = series.points;
    double top = 0;
    for (final x in pts) {
      top = math.max(top, (first(x) ?? 0).toDouble());
      top = math.max(top, (second(x) ?? 0).toDouble());
    }
    final step = _step(top);
    final maxY = math.max(step, (top / step).ceil() * step);
    LineChartBarData line(
      num? Function(SeriesPoint) f,
      Color color,
      bool dash,
    ) => LineChartBarData(
      spots: [
        for (var i = 0; i < pts.length; i++)
          f(pts[i]) == null
              ? FlSpot.nullSpot
              : FlSpot(i.toDouble(), f(pts[i])!.toDouble()),
      ],
      color: color,
      barWidth: TelemetrySizes.chartLineWidth,
      dashArray: dash ? TelemetrySizes.lineDash : null,
      dotData: FlDotData(show: pts.length <= TelemetrySizes.dotsMaxPoints),
      isStrokeCapRound: true,
    );
    return SizedBox(
      height: TelemetrySizes.chartHeight,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: LineChart(
          duration: Duration.zero,
          LineChartData(
            minY: 0,
            maxY: maxY,
            minX: 0,
            maxX: math.max(1, pts.length - 1).toDouble(),
            gridData: _grid(p, step),
            borderData: FlBorderData(show: false),
            titlesData: _titles(
              context,
              pts,
              series.bucket,
              step,
              (v) => format(v),
            ),
            lineBarsData: [
              line(first, p.textPrimary, false),
              line(second, p.accent, true),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) =>
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                tooltipBorder: BorderSide(color: p.border),
                tooltipBorderRadius: BorderRadius.circular(AppRadius.md),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${s.barIndex == 0 ? '${clock(pts[s.spotIndex].t)}\n' : ''}'
                      '${s.barIndex == 0 ? firstLabel : secondLabel} '
                      '${format(s.y)}',
                      _tip(context),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small legend: a swatch and a mono caption per series.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      children: [
        for (final (color, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSizes.quotaDot,
                height: AppSizes.quotaDot,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
      ],
    );
  }
}
