import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/telemetry.dart';
import '../../../data/telemetry_api.dart';
import '../format.dart';
import '../widgets/provider_card.dart';
import '../widgets/settings_kit.dart';
import '../widgets/usage_states.dart';
import 'telemetry_charts.dart';
import 'telemetry_controller.dart';
import 'telemetry_format.dart';
import 'telemetry_widgets.dart';

/// Owner-only: every model call, minute by minute. With [model] set it is
/// that model's detail screen (its own series and events, no breakdowns).
class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({
    super.key,
    this.provider,
    this.model,
    this.title,
    this.api,
  });

  final String? provider, model, title;

  /// Test seam; defaults to the app's API.
  final TelemetryApi? api;

  bool get isDetail => model != null || provider != null;

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen> {
  late final TelemetryController _c;
  final Set<String> _open = {};
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _c = TelemetryController(
      widget.api ?? TelemetryApi(AppConfig.apiBaseUrl),
      locked: TelemetryFilters(provider: widget.provider, model: widget.model),
    )..start();
    _tick = Timer.periodic(TelemetryDurations.countdownTick, (_) {
      final cooling =
          _c.overview?.models.any((m) => m.cooldownLeft(_now) != null) ?? false;
      _now = DateTime.now();
      if (cooling && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < TelemetrySizes.loadMoreThreshold &&
              _c.hasMore &&
              !_c.loadingMore) {
            unawaited(_c.loadMore());
          }
          return false;
        },
        child: M3Page(
          title: widget.title ?? TelemetryStrings.title,
          onRefresh: _c.reload,
          actions: [LiveDot(state: _c.live, paused: _c.paused)],
          slivers: [
            _pad(Builder(builder: _header)),
            if (_c.overview == null)
              _pad(Builder(builder: _placeholder))
            else ...[
              _pad(Builder(builder: (ctx) => _body(ctx, _c.overview!))),
              _pad(Builder(builder: _logHeader)),
              _log(),
              _pad(Builder(builder: _logFooter)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pad(Widget child) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
    sliver: SliverToBoxAdapter(child: child),
  );

  // ---- header: window, big numbers, filters ----------------------------------

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final w in TelemetryWindows.all)
              ButtonSegment(
                value: w,
                label: Text(TelemetryStrings.windowLabels[w]!),
              ),
          ],
          selected: {_c.window},
          onSelectionChanged: (v) {
            Haptics.tap();
            _c.setWindow(v.first);
          },
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    if (_c.error != null && !_c.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: UsageError(onRetry: _c.reload, loading: _c.loading),
      );
    }
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.lg),
      child: SkeletonCard(height: AppSizes.statusStripSkeletonHeight),
    );
  }

  Widget _body(BuildContext context, TelemetryOverview o) {
    final a = o.totals;
    final scope = AppScope.of(context);
    final providers = scope.usage.usage?.providers ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_c.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          UsageError(onRetry: _c.reload, stale: true, loading: _c.loading),
        ],
        const SizedBox(height: AppSpacing.lg),
        StatGrid(
          tiles: [
            StatTile(TelemetryStrings.requests, grouped(a.requests)),
            StatTile(
              TelemetryStrings.failed,
              grouped(a.failed),
              alert: a.failed > 0,
              sub: pct(a.failureRate),
            ),
            StatTile(
              TelemetryStrings.tokensIn,
              compact(a.tokensIn),
              sub: grouped(a.tokensIn),
            ),
            StatTile(
              TelemetryStrings.tokensOut,
              compact(a.tokensOut),
              sub: grouped(a.tokensOut),
            ),
            StatTile(
              TelemetryStrings.p50,
              ms(a.latencyP50),
              sub: '${TelemetryStrings.p95} ${ms(a.latencyP95)}',
            ),
            StatTile(
              TelemetryStrings.ttft,
              ms(a.ttftP50),
              sub: '${TelemetryStrings.avg} ${ms(a.ttftAvg)}',
            ),
          ],
        ),
        if (!widget.isDetail) ...[
          const SizedBox(height: AppSpacing.md),
          ChipRow(
            label: TelemetryCopy.filterProvider,
            values: [for (final x in o.providers) x.name],
            selected: _c.filters.provider,
            onSelect: _c.setProvider,
            display: providerLabel,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        ChipRow(
          label: TelemetryCopy.filterKind,
          values: {?_c.filters.kind, for (final x in o.kinds) x.name}.toList(),
          selected: _c.filters.kind,
          onSelect: _c.setKind,
        ),
        SettingsGroupHeader(TelemetryCopy.charts),
        if (_c.series != null) _charts(context, _c.series!),
        if (!widget.isDetail) ...[
          SettingsGroupHeader(TelemetryCopy.models),
          for (final m in o.models) ...[
            ModelRow(
              key: ValueKey(m.id),
              model: m,
              now: _now,
              onOpen: () => _openModel(m),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
        if (o.totals.requests == 0)
          const M3Empty(icon: TelemetryIcons.chart, title: TelemetryCopy.empty),
        if (!widget.isDetail) ...[
          SettingsGroupHeader(TelemetryCopy.providers),
          M3Group(
            children: [
              for (final x in o.providers)
                AggLine(
                  name: providerLabel(x.name),
                  agg: x.agg,
                  icon: TelemetryIcons.provider(x.name),
                ),
            ],
          ),
          for (final pr in providers) ...[
            const SizedBox(height: AppSpacing.md),
            ProviderCard(key: ValueKey(pr.id), provider: pr),
          ],
        ],
        if (o.kinds.isNotEmpty) ...[
          SettingsGroupHeader(TelemetryCopy.kinds),
          M3Group(
            children: [
              for (final x in o.kinds.take(TelemetrySizes.kindsShown))
                AggLine(name: kindLabel(x.name), agg: x.agg),
            ],
          ),
        ],
        if (!widget.isDetail && o.users.isNotEmpty) ...[
          SettingsGroupHeader(TelemetryCopy.users),
          M3Group(
            children: [
              for (final u in o.users.take(TelemetrySizes.usersShown))
                UserLine(user: u),
            ],
          ),
        ],
        if (o.topErrors.isNotEmpty) ...[
          SettingsGroupHeader(TelemetryCopy.topErrors),
          M3Group(
            children: [
              for (final e in o.topErrors.take(TelemetrySizes.topErrorsShown))
                ErrorLine(error: e),
            ],
          ),
        ],
      ],
    );
  }

  Widget _charts(BuildContext context, TelemetrySeries s) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return M3Card(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final b in TelemetryBuckets.all)
                  ButtonSegment(
                    value: b,
                    label: Text(TelemetryCopy.bucketLabels[b]!),
                  ),
              ],
              selected: {s.bucket},
              onSelectionChanged: (v) {
                Haptics.tap();
                _c.setBucket(v.first);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _chartTitle(context, TelemetryCopy.chartRequests, [
            (p.textSecondary, TelemetryStrings.legendOk),
            (p.accent, TelemetryStrings.legendFailed),
          ]),
          RequestBars(series: s),
          const SizedBox(height: AppSpacing.lg),
          _chartTitle(context, TelemetryCopy.chartTokens, [
            (p.textPrimary, TelemetryStrings.legendIn),
            (p.accent, TelemetryStrings.legendOut),
          ]),
          SeriesLines(
            series: s,
            first: (x) => x.tokensIn,
            second: (x) => x.tokensOut,
            firstLabel: TelemetryStrings.legendIn,
            secondLabel: TelemetryStrings.legendOut,
            format: (v) => compact(v.round()),
          ),
          const SizedBox(height: AppSpacing.lg),
          _chartTitle(context, TelemetryCopy.chartLatency, [
            (p.textPrimary, TelemetryStrings.legendLatency),
            (p.accent, TelemetryStrings.legendTtft),
          ]),
          SeriesLines(
            series: s,
            first: (x) => x.latencyP50,
            second: (x) => x.ttftP50,
            firstLabel: TelemetryStrings.legendLatency,
            secondLabel: TelemetryStrings.legendTtft,
            format: (v) => ms(v.round()),
          ),
          if (_c.loading)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: LinearProgressIndicator(
                minHeight: AppSizes.attachProgress,
                color: p.accent,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chartTitle(
    BuildContext context,
    String title,
    List<(Color, String)> legend,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ChartLegend(items: legend),
        ],
      ),
    );
  }

  void _openModel(ModelTelemetry m) {
    Haptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TelemetryScreen(
          provider: m.provider,
          model: m.model,
          title: m.name,
        ),
      ),
    );
  }

  // ---- live log ---------------------------------------------------------------

  Widget _logHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupHeader(
          widget.isDetail ? TelemetryCopy.recentEvents : TelemetryCopy.log,
        ),
        Wrap(
          spacing: AppSpacing.xs + AppSpacing.xxs,
          runSpacing: AppSpacing.xs + AppSpacing.xxs,
          children: [
            TelemetryChip(
              label: TelemetryCopy.failedOnly,
              icon: TelemetryIcons.failed,
              alert: true,
              selected: _c.failedOnly,
              onTap: () => _c.setFailedOnly(!_c.failedOnly),
            ),
            TelemetryChip(
              label: _c.paused
                  ? '${TelemetryCopy.resume}'
                        '${_c.heldCount > 0 ? ' +${_c.heldCount} ${TelemetryStrings.newEvents}' : ''}'
                  : TelemetryCopy.pause,
              icon: _c.paused ? TelemetryIcons.resume : TelemetryIcons.pause,
              selected: _c.paused,
              onTap: _c.togglePause,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _log() {
    final list = _c.events;
    if (list.isEmpty) {
      return _pad(
        const M3Empty(icon: TelemetryIcons.log, title: TelemetryCopy.emptyLog),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      sliver: SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) {
          final e = list[i];
          return M3Cell(
            key: ValueKey(e.id),
            index: i,
            count: list.length,
            selected: _c.fresh.contains(e.id),
            child: EventRow(
              event: e,
              open: _open.contains(e.id),
              fresh: _c.fresh.contains(e.id),
              onTap: () => setState(
                () =>
                    _open.contains(e.id) ? _open.remove(e.id) : _open.add(e.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _logFooter(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Center(
        child: _c.loadingMore
            ? SizedBox.square(
                dimension: AppIconSize.sm,
                child: CircularProgressIndicator(
                  strokeWidth: AppBorder.thick,
                  color: p.accent,
                ),
              )
            : _c.hasMore
            ? TelemetryChip(
                label: TelemetryCopy.loadMore,
                selected: false,
                onTap: _c.loadMore,
              )
            : Text(
                _c.events.isEmpty ? '' : TelemetryCopy.noMore,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
