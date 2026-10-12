import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/telemetry.dart';
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

/// Hairline horizontal gridlines only.
FlGridData _grid(AppPalette p, double step) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: step,
  getDrawingHorizontalLine: (_) => FlLine(
    color: p.border.withValues(alpha: TelemetrySizes.gridAlpha),
    strokeWidth: AppBorder.thin,
  ),
);

TextStyle _axis(BuildContext context) => AppTextStyles.bodySmall.copyWith(
  fontSize: AppFontSize.caption,
  color: Theme.of(context).colorScheme.onSurfaceVariant,
  fontFeatures: const [FontFeature.tabularFigures()],
);

FlTitlesData _titles(
  BuildContext context,
  List<SeriesPoint> points,
  String bucket,
  double step,
  String Function(double) yLabel,
) {
  final style = _axis(context);
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

/// One bar per bucket; the failed share of it is drawn in red.
class ActivityBars extends StatelessWidget {
  const ActivityBars({
    super.key,
    required this.series,
    required this.value,
    required this.format,
    required this.label,
    this.failed,
  });

  final TelemetrySeries series;

  /// Bar height of a bucket.
  final num Function(SeriesPoint) value;

  /// Failed part of [value] (requests only).
  final num Function(SeriesPoint)? failed;
  final String Function(num) format;

  /// Tooltip noun: "requests", "tokens".
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pts = series.points;
    final top = pts.fold<double>(0, (m, x) => math.max(m, value(x).toDouble()));
    final step = _step(top);
    final maxY = math.max(step, (top / step).ceil() * step);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: SizedBox(
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
                  (v) => format(v),
                ),
                barGroups: [
                  for (var i = 0; i < pts.length; i++) _group(i, pts[i], w, p),
                ],
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    tooltipBorderRadius: BorderRadius.circular(AppRadius.md),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, gi, rod, ri) {
                      final x = pts[group.x];
                      final f = failed?.call(x) ?? 0;
                      return BarTooltipItem(
                        '${clock(x.t)}\n${format(value(x))} $label'
                        '${f > 0 ? '\n${format(f)} ${TelemetryStrings.legendFailed.toLowerCase()}' : ''}',
                        _tip(context),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  BarChartGroupData _group(int i, SeriesPoint x, double w, AppPalette p) {
    final v = value(x).toDouble();
    final f = (failed?.call(x) ?? 0).toDouble().clamp(0, v);
    return BarChartGroupData(
      x: i,
      barRods: [
        BarChartRodData(
          toY: v,
          width: w,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(TelemetrySizes.chartBarRadius),
          ),
          color: p.textSecondary,
          rodStackItems: f > 0
              ? [
                  BarChartRodStackItem(0, v - f, p.textSecondary),
                  BarChartRodStackItem(v - f, v, p.accent),
                ]
              : const [],
        ),
      ],
    );
  }
}

/// Median latency (solid) and time to first token (dashed) per bucket.
class LatencyLines extends StatelessWidget {
  const LatencyLines({super.key, required this.series});

  final TelemetrySeries series;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pts = series.points;
    double top = 0;
    for (final x in pts) {
      top = math.max(top, (x.latencyP50 ?? 0).toDouble());
      top = math.max(top, (x.ttftP50 ?? 0).toDouble());
    }
    final step = _step(top);
    final maxY = math.max(step, (top / step).ceil() * step);
    LineChartBarData line(
      int? Function(SeriesPoint) f,
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
        padding: const EdgeInsets.only(right: AppSpacing.md),
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
              (v) => ms(v.round()),
            ),
            lineBarsData: [
              line((x) => x.latencyP50, p.textPrimary, false),
              line((x) => x.ttftP50, p.textTertiary, true),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) =>
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                tooltipBorderRadius: BorderRadius.circular(AppRadius.md),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${s.barIndex == 0 ? '${clock(pts[s.spotIndex].t)}\n' : ''}'
                      '${s.barIndex == 0 ? TelemetryStrings.legendLatency : TelemetryStrings.legendTtft} '
                      '${ms(s.y.round())}',
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

/// A tiny line of values, no axes (one provider's traffic over the range).
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: TelemetrySizes.sparkWidth,
      height: TelemetrySizes.sparkHeight,
      child: CustomPaint(
        painter: _SparkPainter(values, p.textSecondary, p.border),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.line, this.base);

  final List<double> values;
  final Color line, base;

  @override
  void paint(Canvas canvas, Size size) {
    final top = values.fold<double>(0, math.max);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TelemetrySizes.sparkStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = top == 0 ? base : line;
    if (values.length < 2) {
      canvas.drawLine(
        Offset(0, size.height),
        Offset(size.width, size.height),
        stroke,
      );
      return;
    }
    final inset = TelemetrySizes.sparkStroke;
    final h = size.height - inset * 2;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = top == 0
          ? size.height - inset
          : inset + h * (1 - values[i] / top);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.line != line || old.base != base;
}
