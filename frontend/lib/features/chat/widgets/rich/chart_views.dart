import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_chart.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import 'chart_model.dart';

/// Series color: accent first, then four monochrome steps. Later indexes reuse
/// the steps at lower opacity so no new hue is ever introduced.
Color chartColor(AppPalette p, int i) {
  final base = [
    p.accent,
    p.textPrimary,
    p.textSecondary,
    p.textTertiary,
    p.borderStrong,
  ][i % 5];
  final tier = i ~/ 5;
  return tier == 0 ? base : base.withValues(alpha: tier == 1 ? 0.55 : 0.3);
}

String _short(String s) => s.length <= ChartSizes.labelMaxChars
    ? s
    : '${s.substring(0, ChartSizes.labelMaxChars - 1)}…';

/// The interactive chart with legend, readout and axis captions.
class ChartPanel extends StatefulWidget {
  const ChartPanel({super.key, required this.spec, this.fill = false});

  final ChartSpec spec;

  /// Fill the parent's height (fullscreen) instead of a fixed chart height.
  final bool fill;

  @override
  State<ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<ChartPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: ChartDurations.intro,
  )..forward();
  late final Animation<double> _grow = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOutCubic,
  );
  final Set<int> _hidden = {};
  Object? _lastTouch;
  String? _readout;
  int? _touchedSlice;

  ChartSpec get spec => widget.spec;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _tick(Object? key) {
    if (key == _lastTouch) return;
    _lastTouch = key;
    if (key != null) Haptics.tick();
  }

  void _touchEnded(FlTouchEvent e) {
    if (!e.isInterestedForInteractions) _lastTouch = null;
  }

  void _toggle(int i) {
    Haptics.tap();
    setState(() {
      if (!_hidden.remove(i)) _hidden.add(i);
      _readout = null;
      _touchedSlice = null;
    });
  }

  List<int> get _visible {
    final n = spec.isPie ? spec.slices.length : spec.series.length;
    return [
      for (var i = 0; i < n; i++)
        if (!_hidden.contains(i)) i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final legendCount = spec.isPie ? spec.slices.length : spec.series.length;
    final showLegend = spec.isPie || spec.series.length > 1;
    final chart = _visible.isEmpty
        ? Center(child: Text(ChartStrings.hiddenAll, style: t.caption))
        : LayoutBuilder(
            builder: (context, c) => AnimatedBuilder(
              animation: _grow,
              builder: (context, _) => _chart(context, c.maxWidth, _grow.value),
            ),
          );
    final height = switch (spec.kind) {
      ChartKind.pie || ChartKind.donut => ChartSizes.pieHeight,
      ChartKind.radar => ChartSizes.radarHeight,
      _ => ChartSizes.height,
    };
    return Column(
      mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spec.yLabel.isNotEmpty && spec.isCartesian ||
            spec.isScatter && spec.yLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              _axisCaption(spec.yLabel),
              style: t.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.fill)
          Expanded(child: chart)
        else
          SizedBox(height: height, child: chart),
        if (spec.xLabel.isNotEmpty &&
            !spec.isPie &&
            spec.kind != ChartKind.radar)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              spec.xLabel,
              textAlign: TextAlign.center,
              style: t.caption,
            ),
          ),
        if (spec.isPie || spec.kind == ChartKind.radar)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: SizedBox(
              height: ChartSizes.readoutHeight,
              child: Center(
                child: Text(
                  _readout ??
                      (spec.isPie ? ChartStrings.hintPie : ChartStrings.hint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption.copyWith(
                    color: _readout == null ? p.textTertiary : p.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        if (showLegend)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: 0,
              children: [
                for (var i = 0; i < legendCount; i++) _legendItem(context, i),
              ],
            ),
          ),
      ],
    );
  }

  String _axisCaption(String label) =>
      spec.unit.isEmpty ? label : '$label (${spec.unit})';

  Widget _legendItem(BuildContext context, int i) {
    final p = context.palette;
    final off = _hidden.contains(i);
    final name = spec.isPie ? spec.slices[i].label : spec.series[i].name;
    final total = spec.isPie
        ? spec.slices.fold<double>(0, (a, b) => a + b.value)
        : 0.0;
    final pct = spec.isPie && total > 0
        ? ' ${(spec.slices[i].value / total * 100).round()}%'
        : '';
    final color = chartColor(p, i);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(i),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Opacity(
          opacity: off ? ChartSizes.legendHiddenAlpha : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: ChartSizes.legendDot,
                height: ChartSizes.legendDot,
                decoration: BoxDecoration(
                  color: off ? Colors.transparent : color,
                  border: Border.all(color: color, width: AppBorder.thin),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Flexible(
                child: Text(
                  '$name$pct',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption.copyWith(
                    color: context.palette.textSecondary,
                    decoration: off ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chart(BuildContext context, double w, double g) =>
      switch (spec.kind) {
        ChartKind.bar => _scrollable(context, w, _bar(context, g)),
        ChartKind.line ||
        ChartKind.area => _scrollable(context, w, _line(context, g)),
        ChartKind.scatter => _scatter(context, g),
        ChartKind.pie || ChartKind.donut => _pie(context, g),
        ChartKind.radar => _radar(context, g),
      };

  // ---- shared pieces ----

  FlGridData _grid(AppPalette p, double? hInterval, {bool vertical = false}) =>
      FlGridData(
        show: true,
        drawVerticalLine: vertical,
        horizontalInterval: hInterval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: p.border.withValues(alpha: ChartSizes.gridAlpha),
          strokeWidth: AppBorder.thin,
        ),
        getDrawingVerticalLine: (_) => FlLine(
          color: p.border.withValues(alpha: ChartSizes.gridAlpha),
          strokeWidth: AppBorder.thin,
        ),
      );

  FlBorderData _border(AppPalette p) => FlBorderData(
    show: true,
    border: Border(
      bottom: BorderSide(color: p.borderStrong),
      left: BorderSide(color: p.border),
    ),
  );

  Widget _axisText(BuildContext context, TitleMeta meta, String s) =>
      SideTitleWidget(
        meta: meta,
        space: 6,
        child: Text(
          s,
          maxLines: 1,
          style: context.text.caption.copyWith(
            fontSize: ChartSizes.captionFont,
          ),
        ),
      );

  AxisTitles _leftTitles(
    BuildContext context,
    double step, {
    String Function(double)? fmt,
  }) => AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: ChartSizes.leftAxis,
      interval: step,
      getTitlesWidget: (v, meta) =>
          _axisText(context, meta, (fmt ?? fmtCompact)(v)),
    ),
  );

  AxisTitles _bottomCategory(BuildContext context, double w, int n) {
    final fit = math.max(1, (w / 46).floor());
    final step = math.max(
      1,
      (n / math.min(fit, ChartSizes.maxXLabels + 6)).ceil(),
    );
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: ChartSizes.bottomAxis,
        interval: 1,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if ((v - i).abs() > 0.01 || i < 0 || i >= n || i % step != 0) {
            return const SizedBox.shrink();
          }
          return _axisText(context, meta, _short(spec.categoryLabel(i)));
        },
      ),
    );
  }

  static const _noTitles = AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  );

  FlTitlesData _titles({
    required AxisTitles left,
    required AxisTitles bottom,
  }) => FlTitlesData(
    show: true,
    leftTitles: left,
    bottomTitles: bottom,
    topTitles: _noTitles,
    rightTitles: _noTitles,
  );

  TextStyle _tipStyle(BuildContext context) => context.text.caption.copyWith(
    color: context.palette.textPrimary,
    height: 1.4,
  );

  Widget _scrollable(BuildContext context, double w, Widget chart) {
    final k = math.max(1, _visible.length);
    final slot = spec.kind == ChartKind.bar
        ? ChartSizes.minSlot + (k - 1) * 10
        : ChartSizes.minSlot - 6;
    final needed = ChartSizes.leftAxis + spec.categoryCount * slot;
    if (needed <= w) return chart;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: needed, child: chart),
    );
  }

  ({double min, double max, double step}) _yScale({required bool zeroBase}) {
    double? lo, hi;
    for (final i in _visible) {
      for (final v in spec.series[i].values) {
        if (v == null) continue;
        lo = lo == null ? v : math.min(lo, v);
        hi = hi == null ? v : math.max(hi, v);
      }
    }
    return niceScale(lo ?? 0, hi ?? 1, zeroBase: zeroBase);
  }

  // ---- bar ----

  Widget _bar(BuildContext context, double g) {
    final p = context.palette;
    final vis = _visible;
    final sc = _yScale(zeroBase: true);
    final n = spec.categoryCount;
    final k = vis.length;
    return LayoutBuilder(
      builder: (context, c) {
        final inner = math.max(1.0, c.maxWidth - ChartSizes.leftAxis);
        final slot = inner / math.max(1, n);
        final rodW = ((slot * 0.72 - ChartSizes.barGroupSpace * (k - 1)) / k)
            .clamp(3.0, ChartSizes.barMaxWidth);
        final groups = [
          for (var i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barsSpace: ChartSizes.barGroupSpace,
              barRods: [
                for (final si in vis)
                  BarChartRodData(
                    toY:
                        (i < spec.series[si].values.length
                            ? spec.series[si].values[i] ?? 0
                            : 0) *
                        g,
                    width: rodW,
                    color: chartColor(p, si),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(
                        (spec.series[si].values.length > i &&
                                (spec.series[si].values[i] ?? 0) >= 0)
                            ? ChartSizes.barRadius
                            : 0,
                      ),
                      bottom: Radius.circular(
                        (spec.series[si].values.length > i &&
                                (spec.series[si].values[i] ?? 0) < 0)
                            ? ChartSizes.barRadius
                            : 0,
                      ),
                    ),
                  ),
              ],
            ),
        ];
        return BarChart(
          duration: Duration.zero,
          BarChartData(
            minY: sc.min,
            maxY: sc.max,
            alignment: BarChartAlignment.spaceAround,
            groupsSpace: 4,
            barGroups: groups,
            gridData: _grid(p, sc.step),
            borderData: _border(p),
            titlesData: _titles(
              left: _leftTitles(context, sc.step),
              bottom: _bottomCategory(context, c.maxWidth, n),
            ),
            barTouchData: BarTouchData(
              touchCallback: (e, r) {
                final s = r?.spot;
                _tick(
                  s == null
                      ? null
                      : (s.touchedBarGroupIndex, s.touchedRodDataIndex),
                );
                _touchEnded(e);
              },
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => p.surfaceHigh,
                tooltipBorder: BorderSide(color: p.borderStrong),
                tooltipBorderRadius: BorderRadius.circular(AppRadius.sm),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: ChartSizes.tooltipPadH,
                  vertical: ChartSizes.tooltipPadV,
                ),
                maxContentWidth: 200,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, gi, rod, ri) {
                  final si = vis[ri];
                  final raw = spec.series[si].values;
                  final v = gi < raw.length ? raw[gi] : null;
                  if (v == null) return null;
                  final head = k > 1 ? '${spec.categoryLabel(gi)}\n' : '';
                  final name = k > 1
                      ? '${spec.series[si].name}: '
                      : '${spec.categoryLabel(gi)}: ';
                  return BarTooltipItem(
                    '$head$name${fmtWithUnit(v, spec.unit)}',
                    _tipStyle(context),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- line / area ----

  Widget _line(BuildContext context, double g) {
    final p = context.palette;
    final vis = _visible;
    final area = spec.kind == ChartKind.area;
    final sc = _yScale(zeroBase: area);
    final n = spec.categoryCount;
    final base = math.max(sc.min, math.min(0.0, sc.max));
    final showDots = n <= 24;
    final bars = [
      for (final si in vis)
        LineChartBarData(
          spots: [
            for (var i = 0; i < n; i++)
              if (i < spec.series[si].values.length &&
                  spec.series[si].values[i] != null)
                FlSpot(
                  i.toDouble(),
                  base + (spec.series[si].values[i]! - base) * g,
                )
              else
                FlSpot.nullSpot,
          ],
          isCurved: false,
          color: chartColor(p, si),
          barWidth: ChartSizes.lineWidth,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: showDots,
            getDotPainter: (s, pct, bar, idx) => FlDotCirclePainter(
              radius: ChartSizes.dotRadius,
              color: p.codeBackground,
              strokeColor: bar.color ?? p.accent,
              strokeWidth: AppBorder.thick,
            ),
          ),
          belowBarData: BarAreaData(
            show: area,
            color: chartColor(p, si).withValues(alpha: ChartSizes.areaAlpha),
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, c) => LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: n > 1 ? 0 : -0.5,
            maxX: n > 1 ? (n - 1).toDouble() : 0.5,
            minY: sc.min,
            maxY: sc.max,
            lineBarsData: bars,
            gridData: _grid(p, sc.step),
            borderData: _border(p),
            titlesData: _titles(
              left: _leftTitles(context, sc.step),
              bottom: _bottomCategory(context, c.maxWidth, n),
            ),
            lineTouchData: LineTouchData(
              touchCallback: (e, r) {
                final s = r?.lineBarSpots;
                _tick(s == null || s.isEmpty ? null : s.first.spotIndex);
                _touchEnded(e);
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => p.surfaceHigh,
                tooltipBorder: BorderSide(color: p.borderStrong),
                tooltipBorderRadius: BorderRadius.circular(AppRadius.sm),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: ChartSizes.tooltipPadH,
                  vertical: ChartSizes.tooltipPadV,
                ),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) {
                  final multi = vis.length > 1;
                  return [
                    for (var j = 0; j < spots.length; j++)
                      () {
                        final s = spots[j];
                        final si = vis[s.barIndex];
                        final raw = spec.series[si].values;
                        final i = s.x.round();
                        final v = i < raw.length ? raw[i] : null;
                        if (v == null) return null;
                        final head = j == 0 && multi
                            ? '${spec.categoryLabel(i)}\n'
                            : '';
                        final name = multi
                            ? '${spec.series[si].name}: '
                            : '${spec.categoryLabel(i)}: ';
                        return LineTooltipItem(
                          '$head$name${fmtWithUnit(v, spec.unit)}',
                          _tipStyle(context),
                          textAlign: TextAlign.left,
                        );
                      }(),
                  ];
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- scatter ----

  Widget _scatter(BuildContext context, double g) {
    final p = context.palette;
    final vis = _visible;
    final spots = <ScatterSpot>[];
    final owner = <int>[];
    double? xl, xh, yl, yh;
    for (final si in vis) {
      for (final pt in spec.series[si].points) {
        xl = xl == null ? pt.x : math.min(xl, pt.x);
        xh = xh == null ? pt.x : math.max(xh, pt.x);
        yl = yl == null ? pt.y : math.min(yl, pt.y);
        yh = yh == null ? pt.y : math.max(yh, pt.y);
        spots.add(
          ScatterSpot(
            pt.x,
            pt.y,
            dotPainter: FlDotCirclePainter(
              radius: ChartSizes.scatterRadius * g,
              color: chartColor(p, si).withValues(alpha: 0.85),
              strokeColor: p.codeBackground,
              strokeWidth: AppBorder.thin,
            ),
          ),
        );
        owner.add(si);
      }
    }
    final xs = niceScale(xl ?? 0, xh ?? 1, zeroBase: false);
    final ys = niceScale(yl ?? 0, yh ?? 1, zeroBase: false);
    return ScatterChart(
      duration: Duration.zero,
      ScatterChartData(
        scatterSpots: spots,
        minX: xs.min,
        maxX: xs.max,
        minY: ys.min,
        maxY: ys.max,
        gridData: _grid(
          p,
          ys.step,
          vertical: true,
        ).copyWith(verticalInterval: xs.step),
        borderData: _border(p),
        titlesData: _titles(
          left: _leftTitles(context, ys.step),
          bottom: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: ChartSizes.bottomAxis,
              interval: xs.step,
              getTitlesWidget: (v, meta) =>
                  _axisText(context, meta, fmtCompact(v)),
            ),
          ),
        ),
        scatterTouchData: ScatterTouchData(
          touchSpotThreshold: 18,
          touchCallback: (e, r) {
            final s = r?.touchedSpot;
            _tick(s == null ? null : s.spot.x * 31 + s.spot.y);
            _touchEnded(e);
          },
          touchTooltipData: ScatterTouchTooltipData(
            getTooltipColor: (_) => p.surfaceHigh,
            tooltipBorder: BorderSide(color: p.borderStrong),
            tooltipBorderRadius: BorderRadius.circular(AppRadius.sm),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: ChartSizes.tooltipPadH,
              vertical: ChartSizes.tooltipPadV,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spot) {
              final idx = spots.indexOf(spot);
              final name = idx >= 0 && spec.series.length > 1
                  ? '${spec.series[owner[idx]].name}\n'
                  : '';
              return ScatterTooltipItem(
                '$name${fmtGrouped(spot.x)}, ${fmtWithUnit(spot.y, spec.unit)}',
                textStyle: _tipStyle(context),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- pie / donut ----

  Widget _pie(BuildContext context, double g) {
    final p = context.palette;
    final donut = spec.kind == ChartKind.donut;
    final vis = _visible;
    final total = vis.fold<double>(0, (a, i) => a + spec.slices[i].value);
    final sel = _touchedSlice != null && _touchedSlice! < vis.length
        ? vis[_touchedSlice!]
        : null;
    final radius = donut
        ? ChartSizes.pieRadius - ChartSizes.donutHole * 0.55 + 14
        : ChartSizes.pieRadius;
    final chart = PieChart(
      duration: Duration.zero,
      PieChartData(
        startDegreeOffset: -90,
        sectionsSpace: 0,
        centerSpaceRadius: donut
            ? ChartSizes.donutHole
            : ChartSizes.pieHoleSolid,
        sections: [
          for (var j = 0; j < vis.length; j++)
            PieChartSectionData(
              value: spec.slices[vis[j]].value * g + 1e-9,
              color: chartColor(p, vis[j]),
              radius:
                  radius + (vis[j] == sel ? ChartSizes.pieSelectedExtra : 0),
              showTitle: false,
              borderSide: BorderSide(
                color: p.codeBackground,
                width: ChartSizes.sliceGap,
              ),
            ),
        ],
        pieTouchData: PieTouchData(
          touchCallback: (e, r) {
            final idx = r?.touchedSection?.touchedSectionIndex;
            final valid = idx != null && idx >= 0 && idx < vis.length;
            _tick(valid ? idx : null);
            if (!e.isInterestedForInteractions && !valid) return;
            if (e is FlTapUpEvent ||
                e is FlPanEndEvent ||
                e is FlLongPressEnd) {
              return; // keep the last selection after the finger lifts
            }
            if (!valid) return;
            final s = spec.slices[vis[idx]];
            final pct = total > 0 ? (s.value / total * 100).round() : 0;
            setState(() {
              _touchedSlice = idx;
              _readout =
                  '${s.label}  ${fmtWithUnit(s.value, spec.unit)}  $pct%';
            });
          },
        ),
      ),
    );
    final centerValue = sel != null ? spec.slices[sel].value : total;
    final centerLabel = sel != null
        ? _short(spec.slices[sel].label)
        : ChartStrings.total;
    return Stack(
      alignment: Alignment.center,
      children: [
        chart,
        if (donut)
          IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fmtCompact(centerValue),
                  style: context.text.display.copyWith(
                    fontSize: ChartSizes.centerFont,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.unit.isEmpty
                      ? centerLabel
                      : '$centerLabel · ${spec.unit}',
                  style: context.text.caption.copyWith(
                    fontSize: ChartSizes.captionFont,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- radar ----

  Widget _radar(BuildContext context, double g) {
    final p = context.palette;
    final vis = _visible;
    final n = spec.categoryCount;
    return RadarChart(
      duration: Duration.zero,
      RadarChartData(
        radarShape: RadarShape.polygon,
        tickCount: ChartSizes.radarTicks,
        ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 1),
        tickBorderData: BorderSide(color: p.border),
        gridBorderData: BorderSide(color: p.border),
        radarBorderData: BorderSide(color: p.borderStrong),
        titleTextStyle: context.text.caption.copyWith(
          fontSize: ChartSizes.captionFont,
        ),
        titlePositionPercentageOffset: 0.14,
        getTitle: (i, angle) =>
            RadarChartTitle(text: _short(spec.categoryLabel(i)), angle: 0),
        dataSets: [
          for (final si in vis)
            RadarDataSet(
              fillColor: chartColor(
                p,
                si,
              ).withValues(alpha: ChartSizes.radarFillAlpha),
              borderColor: chartColor(p, si),
              borderWidth: ChartSizes.lineWidth,
              entryRadius: ChartSizes.dotRadius,
              dataEntries: [
                for (var i = 0; i < n; i++)
                  RadarEntry(
                    value:
                        (i < spec.series[si].values.length
                            ? spec.series[si].values[i] ?? 0
                            : 0) *
                        g,
                  ),
              ],
            ),
        ],
        radarTouchData: RadarTouchData(
          touchSpotThreshold: 24,
          touchCallback: (e, r) {
            final s = r?.touchedSpot;
            _tick(
              s == null
                  ? null
                  : (s.touchedDataSetIndex, s.touchedRadarEntryIndex),
            );
            if (s == null || e is FlTapUpEvent || e is FlPanEndEvent) return;
            final si = vis[s.touchedDataSetIndex];
            final i = s.touchedRadarEntryIndex;
            final raw = spec.series[si].values;
            final v = i < raw.length ? raw[i] : null;
            if (v == null) return;
            setState(() {
              _readout =
                  '${spec.series.length > 1 ? '${spec.series[si].name} · ' : ''}${spec.categoryLabel(i)}: ${fmtWithUnit(v, spec.unit)}';
            });
          },
        ),
      ),
    );
  }
}
