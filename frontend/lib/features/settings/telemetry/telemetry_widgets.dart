import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/model_logo.dart';
import '../../../data/telemetry.dart';
import '../format.dart';
import 'telemetry_charts.dart';
import 'telemetry_controller.dart';
import 'telemetry_format.dart';
import 'telemetry_grouping.dart';

/// Text styles of the plain layout: Space Grotesk, tabular figures.
abstract final class TType {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _grotesk(double size, int weight, Color color) =>
      AppTextStyles.body.copyWith(
        fontSize: size,
        height: 1.25,
        color: color,
        fontVariations: [FontVariation.weight(weight.toDouble())],
        fontFeatures: _tabular,
      );

  /// Big summary figure.
  static TextStyle big(BuildContext c, {Color? color}) => _grotesk(
    TelemetrySizes.summaryNumber,
    600,
    color ?? c.palette.textPrimary,
  );

  /// Row title.
  static TextStyle title(BuildContext c, {Color? color}) =>
      _grotesk(AppFontSize.body, 500, color ?? c.palette.textPrimary);

  /// Row figure.
  static TextStyle figure(BuildContext c, {Color? color}) =>
      _grotesk(AppFontSize.body, 600, color ?? c.palette.textPrimary);

  /// Secondary line under a title.
  static TextStyle secondary(BuildContext c, {Color? color}) =>
      _grotesk(AppFontSize.label, 400, color ?? c.palette.textSecondary);

  /// Section header.
  static TextStyle section(BuildContext c) =>
      _grotesk(AppFontSize.bodySmall, 600, c.palette.textSecondary);

  /// Tiny timestamp: the one place Space Mono is allowed.
  static TextStyle stamp(BuildContext c) => AppTextStyles.caption.copyWith(
    color: c.palette.textTertiary,
    letterSpacing: 0,
  );
}

/// Width of a figure column, grown with the text scale (up to a limit).
double colWidth(BuildContext context, double w) {
  final f =
      MediaQuery.textScalerOf(context).scale(AppFontSize.body) /
      AppFontSize.body;
  return w * math.min(f, 1.2);
}

/// Red dot and "LIVE" in the app bar; hollow and grey when not streaming.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, required this.state, required this.paused});

  final LiveState state;
  final bool paused;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: TelemetryDurations.pulse,
      lowerBound: TelemetrySizes.liveDotMinOpacity,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final on = widget.state == LiveState.live && !widget.paused;
    final label = widget.paused
        ? TelemetryStrings.paused
        : widget.state == LiveState.live
        ? TelemetryStrings.live
        : TelemetryStrings.offline;
    final dot = Container(
      width: TelemetrySizes.liveDot,
      height: TelemetrySizes.liveDot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? p.accent : Colors.transparent,
        border: on
            ? null
            : Border.all(color: p.textTertiary, width: AppSizes.statusRing),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.screenPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          on ? FadeTransition(opacity: _c, child: dot) : dot,
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: TType.secondary(context, color: on ? p.accent : null)
                .copyWith(
                  letterSpacing: 1.2,
                  fontVariations: const [FontVariation.weight(700)],
                ),
          ),
        ],
      ),
    );
  }
}

/// A hairline between rows.
class Hairline extends StatelessWidget {
  const Hairline({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: AppBorder.thin,
    thickness: AppBorder.thin,
    color: context.palette.border,
  );
}

/// A section: plain title (and an optional trailing action), then content.
class TSection extends StatelessWidget {
  const TSection({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    required this.child,
    this.note,
  });

  final String title;
  final AppIconData? icon;
  final Widget? trailing;
  final Widget child;

  /// Small supporting line under the title.
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TelemetrySizes.sectionTop),
        Row(
          children: [
            if (icon != null) ...[
              AppIcon(
                icon!,
                size: TelemetrySizes.sectionIcon,
                color: context.palette.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(child: Text(title, style: TType.section(context))),
            ?trailing,
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              note!,
              style: TType.secondary(
                context,
                color: context.palette.textTertiary,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

/// Rows separated by hairlines (none above the first or below the last).
class PlainList extends StatelessWidget {
  const PlainList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Hairline(),
          children[i],
        ],
      ],
    );
  }
}

/// A flat text action ("Pause", "Show more").
class TextAction extends StatelessWidget {
  const TextAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.active = false,
  });

  final String label;
  final AppIconData? icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TelemetrySizes.tabHeight),
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.lg),
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  AppIcon(
                    icon!,
                    size: TelemetrySizes.actionIcon,
                    color: active ? p.accent : p.textPrimary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  label,
                  style: TType.secondary(
                    context,
                    color: active ? p.accent : p.textPrimary,
                  ).copyWith(fontVariations: const [FontVariation.weight(600)]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- summary ------------------------------------------------------------------

class SummaryStat {
  const SummaryStat(
    this.value,
    this.label, {
    this.sub,
    this.alert = false,
    this.unit = false,
    this.icon,
  });

  final AppIconData? icon;

  /// The value ends in a unit (ms, s) that is drawn small.
  final bool unit;
  final String value, label;
  final String? sub;
  final bool alert;
}

/// One row of big numbers with small labels and thin vertical dividers.
class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.stats});

  final List<SummaryStat> stats;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                width: AppBorder.thin,
                thickness: AppBorder.thin,
                color: p.border,
              ),
            Expanded(child: _cell(context, stats[i], first: i == 0)),
          ],
        ],
      ),
    );
  }

  Widget _value(BuildContext context, SummaryStat s) {
    final big = TType.big(context, color: s.alert ? p(context).accent : null);
    final m = s.unit ? RegExp(r'^([\d.,]+)(\D+)$').firstMatch(s.value) : null;
    if (m == null) return Text(s.value, maxLines: 1, style: big);
    return Text.rich(
      TextSpan(
        text: m.group(1),
        children: [
          TextSpan(
            text: m.group(2),
            style: big.copyWith(fontSize: AppFontSize.body),
          ),
        ],
      ),
      maxLines: 1,
      style: big,
    );
  }

  AppPalette p(BuildContext context) => context.palette;

  Widget _cell(BuildContext context, SummaryStat s, {required bool first}) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        left: first ? 0 : AppSpacing.md,
        right: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _value(context, s),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              if (s.icon != null) ...[
                AppIcon(
                  s.icon!,
                  size: TelemetrySizes.actionIcon,
                  color: s.alert ? p.accent : p.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Flexible(
                child: Text(
                  s.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TType.secondary(context),
                ),
              ),
            ],
          ),
          if (s.sub != null)
            Text(
              s.sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TType.secondary(
                context,
                color: s.alert ? p.accent : p.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

// ---- activity -------------------------------------------------------------------

enum Metric { requests, tokens, latency }

/// Flat text tabs with an underline under the chosen one.
class MetricTabs extends StatelessWidget {
  const MetricTabs({super.key, required this.value, required this.onChanged});

  final Metric value;
  final ValueChanged<Metric> onChanged;

  static const _labels = {
    Metric.requests: TelemetryCopy.metricRequests,
    Metric.tokens: TelemetryCopy.metricTokens,
    Metric.latency: TelemetryCopy.metricLatency,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        for (final m in Metric.values)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xl),
              child: InkWell(
                onTap: () {
                  Haptics.tap();
                  onChanged(m);
                },
                child: Container(
                  height: TelemetrySizes.tabHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: m == value ? p.textPrimary : Colors.transparent,
                        width: TelemetrySizes.tabUnderline,
                      ),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _labels[m]!,
                      style: TType.title(
                        context,
                        color: m == value ? p.textPrimary : p.textTertiary,
                      ).copyWith(fontSize: AppFontSize.bodySmall),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A dot and a word, for chart legends.
class LegendItem extends StatelessWidget {
  const LegendItem(this.color, this.label, {super.key});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: AppSizes.quotaDot,
        height: AppSizes.quotaDot,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
      Text(label, style: TType.secondary(context)),
    ],
  );
}

/// The one chart: requests (failures in red), tokens or latency.
class ActivityChart extends StatelessWidget {
  const ActivityChart({super.key, required this.series, required this.metric});

  final TelemetrySeries series;
  final Metric metric;

  @override
  Widget build(BuildContext context) {
    return switch (metric) {
      Metric.requests => ActivityBars(
        series: series,
        value: (x) => x.requests,
        failed: (x) => x.failed,
        format: (v) => compact(v.round()),
        label: TelemetryCopy.metricRequests.toLowerCase(),
      ),
      Metric.tokens => ActivityBars(
        series: series,
        value: (x) => x.tokensIn + x.tokensOut,
        format: (v) => compact(v.round()),
        label: TelemetryCopy.metricTokens.toLowerCase(),
      ),
      Metric.latency => LatencyLines(series: series),
    };
  }
}

// ---- filters -----------------------------------------------------------------------

/// Kind menu and, when a provider is chosen, a way to clear it.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.kinds,
    required this.kind,
    required this.onKind,
    this.provider,
    this.onClearProvider,
  });

  final List<String> kinds;
  final String? kind;
  final ValueChanged<String?> onKind;
  final String? provider;
  final VoidCallback? onClearProvider;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        PopupMenuButton<String?>(
          tooltip: TelemetryCopy.kindMenu,
          position: PopupMenuPosition.under,
          onSelected: (v) {
            Haptics.tap();
            onKind(v);
          },
          itemBuilder: (_) => [
            PopupMenuItem<String?>(
              value: null,
              child: Text(TelemetryCopy.kindAll, style: TType.title(context)),
            ),
            for (final k in kinds)
              PopupMenuItem<String?>(
                value: k,
                child: Text(
                  kindLabel(k),
                  style: TType.title(
                    context,
                    color: k == kind ? p.accent : null,
                  ),
                ),
              ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: TelemetrySizes.tabHeight,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${TelemetryCopy.kindMenu}  ',
                  style: TType.secondary(context),
                ),
                Text(
                  kind == null ? TelemetryCopy.kindAll : kindLabel(kind!),
                  style: TType.secondary(
                    context,
                    color: p.textPrimary,
                  ).copyWith(fontVariations: const [FontVariation.weight(600)]),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppIcon(
                  AppIcons.expand,
                  size: AppIconSize.sm,
                  color: p.textSecondary,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (provider != null)
          InkWell(
            onTap: () {
              Haptics.tap();
              onClearProvider?.call();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TelemetrySizes.tabHeight,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    providerLabel(provider!),
                    style: TType.secondary(context, color: p.textPrimary)
                        .copyWith(
                          fontVariations: const [FontVariation.weight(600)],
                        ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppIcon(
                    AppIcons.close,
                    size: AppIconSize.sm,
                    color: p.textSecondary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---- rows ---------------------------------------------------------------------------

/// Failure rate; red only above [TelemetrySizes.failWarn].
Color failColor(BuildContext context, TelemetryAgg a) =>
    a.failureRate > TelemetrySizes.failWarn
    ? context.palette.accent
    : context.palette.textTertiary;

/// The Groq-style rate-limit line: "7.6k / 8k tokens left · resets in 1m".
String? rateLimitLine(
  Iterable<ModelTelemetry> models,
  String provider,
  DateTime now,
) {
  TelemetryRateLimit? best;
  var bestRatio = 2.0;
  for (final m in models) {
    final r = m.rateLimit;
    if (m.provider != provider || r == null) continue;
    final lim = r.limitTokens ?? r.limitRequests;
    final rem = r.remainingTokens ?? r.remainingRequests;
    if (lim == null || rem == null || lim == 0) continue;
    final ratio = rem / lim;
    if (ratio < bestRatio) {
      bestRatio = ratio;
      best = r;
    }
  }
  if (best == null) return null;
  final tokens = best.limitTokens != null && best.remainingTokens != null;
  final left = tokens ? best.remainingTokens! : best.remainingRequests!;
  final limit = tokens ? best.limitTokens! : best.limitRequests!;
  final unit = tokens ? TelemetryCopy.tokensLeft : TelemetryCopy.requestsLeft;
  final reset = best.resetsAt;
  return [
    '${compact(left)} / ${compact(limit)} $unit',
    if (reset != null && reset.isAfter(now))
      '${TelemetryCopy.resetsIn} ${shortSpan(reset.difference(now))}',
  ].join(TelemetryStrings.separator);
}

/// One provider: icon, name, sparkline, requests and failure rate.
class ProviderRow extends StatelessWidget {
  const ProviderRow({
    super.key,
    required this.provider,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final NamedAgg provider;
  final bool selected;
  final VoidCallback onTap;

  /// Rate-limit line, when the provider reports one.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = provider.agg;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TelemetrySizes.rowPad),
        child: Row(
          children: [
            AppIcon(
              TelemetryIcons.provider(provider.name),
              size: TelemetrySizes.providerIcon,
              color: selected ? p.accent : p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    providerLabel(provider.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TType.title(context),
                  ),
                  if (detail != null)
                    Text(detail!, maxLines: 2, style: TType.secondary(context)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Sparkline(values: provider.spark),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: colWidth(context, TelemetrySizes.colRequests),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(compact(a.requests), style: TType.figure(context)),
                  Text(
                    pct(a.failureRate),
                    style: TType.secondary(
                      context,
                      color: failColor(context, a),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Column captions above the models list.
class ModelColumns extends StatelessWidget {
  const ModelColumns({super.key});

  @override
  Widget build(BuildContext context) {
    Widget col(String t, double w) => SizedBox(
      width: colWidth(context, w),
      child: Text(
        t,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TType.secondary(context, color: context.palette.textTertiary),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          const Spacer(),
          col(TelemetryCopy.colRequests, TelemetrySizes.colRequests + 8),
          col(TelemetryCopy.colFail, TelemetrySizes.colFail),
          col(TelemetryCopy.colP50, TelemetrySizes.colP50),
        ],
      ),
    );
  }
}

/// A key and value on one line (inline detail).
class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.color});

  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TType.secondary(context)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TType.secondary(
                context,
                color: color ?? context.palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One model: name and providers, requests, failure rate and p50; tap for
/// first token, tokens, last call and recent errors.
class ModelRow extends StatelessWidget {
  const ModelRow({
    super.key,
    required this.group,
    required this.open,
    required this.onTap,
    required this.now,
    this.errors = const [],
  });

  final ModelGroup group;
  final bool open;
  final VoidCallback onTap;
  final DateTime now;
  final List<ErrorGroup> errors;

  @override
  Widget build(BuildContext context) {
    final a = group.agg;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TelemetrySizes.rowPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ModelLogo(
                  group.key,
                  provider: group.providers.firstOrNull,
                  size: TelemetrySizes.providerIcon,
                  color: context.palette.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TType.title(context),
                      ),
                      Text(
                        [
                          for (final p in group.providers) providerLabel(p),
                        ].join(TelemetryStrings.separator),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TType.secondary(context),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: colWidth(context, TelemetrySizes.colRequests + 8),
                  child: Text(
                    compact(a.requests),
                    textAlign: TextAlign.end,
                    style: TType.figure(context),
                  ),
                ),
                SizedBox(
                  width: colWidth(context, TelemetrySizes.colFail),
                  child: Text(
                    pct(a.failureRate),
                    textAlign: TextAlign.end,
                    style: TType.secondary(
                      context,
                      color: failColor(context, a),
                    ),
                  ),
                ),
                SizedBox(
                  width: colWidth(context, TelemetrySizes.colP50),
                  child: Text(
                    ms(a.latencyP50),
                    textAlign: TextAlign.end,
                    style: TType.secondary(
                      context,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: TelemetryDurations.expand,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: open
                  ? _details(context)
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    final p = context.palette;
    final a = group.agg;
    final codes = group.failuresByCode.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final cool = group.cooldownLeft(now);
    final last = group.lastError;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValue(
            TelemetryCopy.detailTtft,
            '${ms(a.ttftP50)}${TelemetryStrings.separator}${TelemetryStrings.avg.toLowerCase()} ${ms(a.ttftAvg)}',
          ),
          KeyValue(
            TelemetryCopy.detailLatency,
            '${ms(a.latencyP50)}${TelemetryStrings.slash}${ms(a.latencyP95)}',
          ),
          KeyValue(TelemetryCopy.detailTokens, inOut(a.tokensIn, a.tokensOut)),
          KeyValue(
            TelemetryCopy.detailLastCall,
            a.lastAt == null
                ? TelemetryCopy.detailNever
                : agoShort(a.lastAt!, now),
          ),
          if (a.unknown > 0)
            KeyValue(TelemetryCopy.noStatus, grouped(a.unknown)),
          if (cool != null)
            KeyValue(
              TelemetryCopy.detailCooldown,
              countdown(cool),
              color: p.accent,
            ),
          if (codes.isNotEmpty)
            KeyValue(
              TelemetryCopy.detailErrors,
              [
                for (final e in codes)
                  '${e.key} ${TelemetryStrings.times}${e.value}',
              ].join(TelemetryStrings.separator),
              color: p.accent,
            ),
          if (last != null)
            KeyValue(
              TelemetryCopy.detailLastError,
              '${agoShort(last.at, now)}'
              '${last.message == null ? '' : '\n${last.message}'}',
            ),
          for (final e in errors)
            for (final m in e.messages.keys.take(1))
              KeyValue(e.code, '${TelemetryStrings.times}${e.count}  $m'),
        ],
      ),
    );
  }
}

/// A failure group: code in red, model, count and last seen; tap for messages.
class ErrorRow extends StatelessWidget {
  const ErrorRow({
    super.key,
    required this.group,
    required this.open,
    required this.onTap,
    required this.now,
  });

  final ErrorGroup group;
  final bool open;
  final VoidCallback onTap;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final messages = group.messages.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TelemetrySizes.rowPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TType.title(context, color: p.accent),
                      ),
                      Text(
                        group.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TType.secondary(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${TelemetryStrings.times}${grouped(group.count)}',
                      style: TType.figure(context),
                    ),
                    if (group.lastAt != null)
                      Text(
                        agoShort(group.lastAt!, now),
                        style: TType.secondary(context, color: p.textTertiary),
                      ),
                  ],
                ),
              ],
            ),
            AnimatedSize(
              duration: TelemetryDurations.expand,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: open && messages.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final m in messages)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xs,
                              ),
                              child: Text(
                                '${m.key}  ${TelemetryStrings.times}${m.value}',
                                style: TType.secondary(context),
                              ),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who called: email, role, and requests in range.
class UserRow extends StatelessWidget {
  const UserRow({super.key, required this.user});

  final UserTelemetry user;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TelemetrySizes.rowPad),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.email ?? TelemetryCopy.system,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TType.title(context),
                ),
                Text(
                  [
                    if (u.role != null) u.role!,
                    '${TelemetryCopy.today} ${grouped(u.todayRequests)}'
                        '${u.todayFailed > 0 ? ' · ${u.todayFailed} ${TelemetryCopy.summaryFailed.toLowerCase()}' : ''}',
                  ].join(TelemetryStrings.separator),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TType.secondary(
                    context,
                    color: u.todayFailed > 0 ? p.accent : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(compact(u.window.requests), style: TType.figure(context)),
              Text(
                '${compact(u.window.tokens)} ${TelemetryStrings.tokensShort.toLowerCase()}',
                style: TType.secondary(context, color: p.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One recent call; failures show a code, tap for the details.
class CallRow extends StatelessWidget {
  const CallRow({
    super.key,
    required this.event,
    required this.open,
    required this.onTap,
  });

  final TelemetryEvent event;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final p = context.palette;
    final tokens = e.tokens;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: TelemetrySizes.eventTimeWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(clock(e.ts), style: TType.stamp(context)),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.model ?? providerLabel(e.provider),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TType.title(
                          context,
                        ).copyWith(fontSize: AppFontSize.bodySmall),
                      ),
                      Text(
                        [
                          kindLabel(e.purpose),
                          ms(e.latencyMs),
                          if (tokens > 0)
                            '${compact(tokens)} ${TelemetryStrings.tokensShort.toLowerCase()}',
                        ].join(TelemetryStrings.separator),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TType.secondary(context),
                      ),
                    ],
                  ),
                ),
                if (e.failed)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      e.errorCode ?? '${e.status}',
                      style: TType.secondary(context, color: p.accent),
                    ),
                  )
                else if (e.unknown)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      AppStrings.dash,
                      style: TType.secondary(context, color: p.textTertiary),
                    ),
                  ),
              ],
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: TelemetrySizes.eventTimeWidth,
                ),
                child: Text(
                  [
                    providerLabel(e.provider),
                    if (e.status != null) '${e.status}',
                    if (e.ttftMs != null)
                      '${TelemetryStrings.ttft.toLowerCase()} ${ms(e.ttftMs)}',
                    e.userEmail ?? TelemetryCopy.system,
                    ?e.errorMessage,
                  ].join(TelemetryStrings.separator),
                  style: TType.secondary(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
