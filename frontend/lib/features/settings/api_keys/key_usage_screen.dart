import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/api_keys.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../core/widgets/model_logo.dart';
import '../../../data/api_keys_api.dart';
import '../format.dart';
import '../telemetry/telemetry_format.dart';
import '../telemetry/telemetry_widgets.dart';

/// "Your usage": the caller's own calls on their own keys, last 7 or 30
/// days. Same look as the owner telemetry screen, but only their data.
class KeyUsageScreen extends StatefulWidget {
  const KeyUsageScreen({super.key, this.api});

  /// Test seam.
  final ApiKeysApi? api;

  static Future<void> open(BuildContext context) {
    Haptics.tap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const KeyUsageScreen()));
  }

  @override
  State<KeyUsageScreen> createState() => _KeyUsageScreenState();
}

class _KeyUsageScreenState extends State<KeyUsageScreen> {
  late final _api = widget.api ?? ApiKeysApi.instance;
  int _days = 7;
  KeyUsage? _usage;
  bool _loading = true;
  bool _failed = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final u = await _api.usage(_days);
      if (!mounted || gen != _gen) return;
      setState(() {
        _usage = u;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _setDays(int d) {
    if (d == _days) return;
    Haptics.tap();
    _days = d;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final u = _usage;
    return M3Page(
      title: KeyUsageStrings.title,
      onRefresh: _load,
      slivers: [
        M3Body(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                KeyUsageStrings.lead,
                style: context.text.bodySmall.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ),
            _Range(days: _days, onChanged: _setDays),
            if (u == null && _loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (u == null || _failed && u.requests == 0)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  KeyUsageStrings.loadFailed,
                  textAlign: TextAlign.center,
                  style: context.text.body.copyWith(
                    color: context.palette.error,
                  ),
                ),
              )
            else if (u.requests == 0)
              M3Empty(
                icon: ApiKeysIcons.usage,
                title: KeyUsageStrings.empty,
                hint: KeyUsageStrings.emptyHint,
              )
            else
              ..._content(context, u),
          ],
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, KeyUsage u) => [
    const SizedBox(height: AppSpacing.lg),
    SummaryRow(
      stats: [
        SummaryStat(compact(u.requests), KeyUsageStrings.requests),
        SummaryStat(compact(u.tokens), KeyUsageStrings.tokens),
        SummaryStat(
          ms(u.avgLatencyMs),
          KeyUsageStrings.latency,
          unit: u.avgLatencyMs != null,
        ),
        SummaryStat(
          compact(u.errors),
          KeyUsageStrings.failed,
          alert: u.errors > 0,
        ),
      ],
    ),
    TSection(
      title: KeyUsageStrings.byDay,
      icon: TelemetryIcons.chart,
      child: _DayBars(u.byDay),
    ),
    if (u.byProvider.isNotEmpty)
      TSection(
        title: KeyUsageStrings.byProvider,
        icon: TelemetryIcons.providers,
        child: PlainList(
          children: [
            for (final p in u.byProvider)
              _UsageRow(
                key: ValueKey('provider-${p.label}'),
                logo: ModelLogo(null, provider: p.label, size: AppIconSize.md),
                title: providerLabel(p.label),
                bucket: p,
              ),
          ],
        ),
      ),
    if (u.byModel.isNotEmpty)
      TSection(
        title: KeyUsageStrings.byModel,
        icon: TelemetryIcons.models,
        child: PlainList(
          children: [
            for (final m in u.byModel.take(ApiKeysSizes.usageTopModels))
              _UsageRow(
                key: ValueKey('model-${m.provider}-${m.label}'),
                logo: ModelLogo(
                  m.label,
                  provider: m.provider,
                  size: AppIconSize.md,
                ),
                title: m.label.split('/').last,
                bucket: m,
              ),
          ],
        ),
      ),
  ];
}

/// 7 / 30 days.
class _Range extends StatelessWidget {
  const _Range({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 7, label: Text(KeyUsageStrings.days7)),
        ButtonSegment(value: 30, label: Text(KeyUsageStrings.days30)),
      ],
      selected: {days},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// One bar per day; grey like the owner charts, the failed share in red.
class _DayBars extends StatelessWidget {
  const _DayBars(this.days);

  final List<UsageBucket> days;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = days.fold<int>(0, (m, d) => math.max(m, d.requests));
    final maxY = math.max(4, top).toDouble();
    final every = math.max(
      1,
      (days.length / TelemetrySizes.chartXLabels).ceil(),
    );
    final axis = context.text.caption.copyWith(color: p.textSecondary);
    return SizedBox(
      height: ApiKeysSizes.usageBarsHeight,
      child: BarChart(
        duration: Duration.zero,
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceBetween,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 2,
            getDrawingHorizontalLine: (_) => FlLine(
              color: p.border.withValues(alpha: TelemetrySizes.gridAlpha),
              strokeWidth: AppBorder.thin,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: TelemetrySizes.chartLeftAxis,
                interval: maxY / 2,
                getTitlesWidget: (v, meta) => v == meta.max
                    ? const SizedBox.shrink()
                    : Text(compact(v.round()), style: axis),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: TelemetrySizes.chartBottomAxis,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 ||
                      i >= days.length ||
                      (days.length - 1 - i) % every != 0) {
                    return const SizedBox.shrink();
                  }
                  final d = days[i].label;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      d.length >= 10
                          ? '${d.substring(8, 10)}/${d.substring(5, 7)}'
                          : d,
                      style: axis,
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) =>
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, gi, rod, ri) {
                final d = days[group.x];
                return BarTooltipItem(
                  '${d.label}\n${d.requests} ${KeyUsageStrings.tooltipRequests}',
                  context.text.caption.copyWith(color: p.textPrimary),
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: days[i].requests.toDouble(),
                    width: days.length > 14
                        ? ApiKeysSizes.usageBarWidth / 2
                        : ApiKeysSizes.usageBarWidth,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(TelemetrySizes.chartBarRadius),
                    ),
                    color: p.textSecondary,
                    rodStackItems: days[i].errors > 0
                        ? [
                            BarChartRodStackItem(
                              0,
                              (days[i].requests - days[i].errors).toDouble(),
                              p.textSecondary,
                            ),
                            BarChartRodStackItem(
                              (days[i].requests - days[i].errors).toDouble(),
                              days[i].requests.toDouble(),
                              p.accent,
                            ),
                          ]
                        : const [],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    super.key,
    required this.logo,
    required this.title,
    required this.bucket,
  });

  final Widget logo;
  final String title;
  final UsageBucket bucket;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          logo,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TType.title(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  KeyUsageStrings.modelLine(
                    bucket.requests,
                    bucket.tokens,
                    compact(bucket.tokens),
                  ),
                  style: TType.secondary(context),
                ),
              ],
            ),
          ),
          if (bucket.errors > 0)
            Text(
              '${bucket.errors} ${KeyUsageStrings.failed.toLowerCase()}',
              style: TType.secondary(context, color: p.accent),
            ),
        ],
      ),
    );
  }
}
