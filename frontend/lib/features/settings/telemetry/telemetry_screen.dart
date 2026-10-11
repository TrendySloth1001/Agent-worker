import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/system_chrome.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/segmented.dart';
import '../../../data/telemetry.dart';
import '../../../data/telemetry_api.dart';
import '../format.dart';
import '../widgets/provider_card.dart';
import '../widgets/section_header.dart';
import '../widgets/usage_states.dart';
import 'telemetry_charts.dart';
import 'telemetry_controller.dart';
import 'telemetry_format.dart';
import 'telemetry_widgets.dart';

/// Owner-only: every model call, minute by minute. With [model] set it is
/// that model's detail screen (its own series and events, no breakdowns).
class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({super.key, this.provider, this.model, this.title});

  final String? provider, model, title;

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
      TelemetryApi(AppConfig.apiBaseUrl),
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
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const AppIcon(AppIcons.back, size: AppIconSize.md),
            tooltip: AppStrings.back,
            onPressed: () {
              Haptics.tap();
              Navigator.pop(context);
            },
          ),
          title: Text(
            widget.title ?? TelemetryStrings.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            ListenableBuilder(
              listenable: _c,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: LiveDot(state: _c.live, paused: _c.paused),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppBorder.thin),
            child: Divider(color: p.border),
          ),
        ),
        body: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => RefreshIndicator(
            color: p.accent,
            backgroundColor: p.surface,
            onRefresh: _c.reload,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < TelemetrySizes.loadMoreThreshold &&
                    _c.hasMore &&
                    !_c.loadingMore) {
                  unawaited(_c.loadMore());
                }
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _pad(_header(context)),
                  if (_c.overview == null)
                    _pad(_placeholder(context))
                  else ...[
                    _pad(_body(context, _c.overview!)),
                    _pad(_logHeader(context)),
                    _log(context),
                    _pad(_logFooter(context)),
                  ],
                ],
              ),
            ),
          ),
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
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Segmented<String>(
        value: _c.window,
        onChanged: _c.setWindow,
        options: [
          for (final w in TelemetryWindows.all)
            (w, TelemetryStrings.windowLabels[w]!),
        ],
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
        FlatCard(
          child: StatGrid(
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
        ),
        if (!widget.isDetail) ...[
          const SizedBox(height: AppSpacing.md),
          ChipRow(
            label: TelemetryStrings.filterProvider,
            values: [for (final x in o.providers) x.name],
            selected: _c.filters.provider,
            onSelect: _c.setProvider,
            display: providerLabel,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        ChipRow(
          label: TelemetryStrings.filterKind,
          values: {?_c.filters.kind, for (final x in o.kinds) x.name}.toList(),
          selected: _c.filters.kind,
          onSelect: _c.setKind,
        ),
        const SectionHeader(
          TelemetryStrings.charts,
          icon: TelemetryIcons.chart,
        ),
        if (_c.series != null) _charts(context, _c.series!),
        if (!widget.isDetail) ...[
          const SectionHeader(
            TelemetryStrings.models,
            icon: TelemetryIcons.models,
          ),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(TelemetryStrings.empty, style: context.text.caption),
          ),
        if (!widget.isDetail) ...[
          const SectionHeader(
            TelemetryStrings.providers,
            icon: TelemetryIcons.providers,
          ),
          FlatCard(
            child: Column(
              children: [
                for (final x in o.providers)
                  AggLine(
                    name: providerLabel(x.name),
                    agg: x.agg,
                    icon: TelemetryIcons.provider(x.name),
                  ),
              ],
            ),
          ),
          for (final pr in providers) ...[
            const SizedBox(height: AppSpacing.md),
            ProviderCard(key: ValueKey(pr.id), provider: pr),
          ],
        ],
        if (o.kinds.isNotEmpty) ...[
          const SectionHeader(
            TelemetryStrings.kinds,
            icon: TelemetryIcons.kinds,
          ),
          FlatCard(
            child: Column(
              children: [
                for (final x in o.kinds.take(TelemetrySizes.kindsShown))
                  AggLine(name: kindLabel(x.name), agg: x.agg),
              ],
            ),
          ),
        ],
        if (!widget.isDetail && o.users.isNotEmpty) ...[
          const SectionHeader(
            TelemetryStrings.users,
            icon: TelemetryIcons.users,
          ),
          FlatCard(
            child: Column(
              children: [
                for (final u in o.users.take(TelemetrySizes.usersShown))
                  UserLine(user: u),
              ],
            ),
          ),
        ],
        if (o.topErrors.isNotEmpty) ...[
          const SectionHeader(
            TelemetryStrings.topErrors,
            icon: TelemetryIcons.errors,
          ),
          FlatCard(
            child: Column(
              children: [
                for (final e in o.topErrors.take(TelemetrySizes.topErrorsShown))
                  ErrorLine(error: e),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _charts(BuildContext context, TelemetrySeries s) {
    final p = context.palette;
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: TelemetrySizes.chipHeight,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final b in TelemetryBuckets.all) ...[
                  TelemetryChip(
                    label: TelemetryStrings.bucketLabels[b]!,
                    selected: s.bucket == b,
                    onTap: () => _c.setBucket(b),
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _chartTitle(context, TelemetryStrings.chartRequests, [
            (p.textSecondary, TelemetryStrings.legendOk),
            (p.accent, TelemetryStrings.legendFailed),
          ]),
          RequestBars(series: s),
          const SizedBox(height: AppSpacing.lg),
          _chartTitle(context, TelemetryStrings.chartTokens, [
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
          _chartTitle(context, TelemetryStrings.chartLatency, [
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
                backgroundColor: p.border,
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
              style: context.text.caption.copyWith(
                color: context.palette.textPrimary,
              ),
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
        SectionHeader(
          widget.isDetail
              ? TelemetryStrings.recentEvents
              : TelemetryStrings.log,
          icon: TelemetryIcons.log,
        ),
        Wrap(
          spacing: AppSpacing.xs + AppSpacing.xxs,
          runSpacing: AppSpacing.xs + AppSpacing.xxs,
          children: [
            TelemetryChip(
              label: TelemetryStrings.failedOnly,
              icon: TelemetryIcons.failed,
              alert: true,
              selected: _c.failedOnly,
              onTap: () => _c.setFailedOnly(!_c.failedOnly),
            ),
            TelemetryChip(
              label: _c.paused
                  ? '${TelemetryStrings.resume}'
                        '${_c.heldCount > 0 ? ' +${_c.heldCount} ${TelemetryStrings.newEvents}' : ''}'
                  : TelemetryStrings.pause,
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

  Widget _log(BuildContext context) {
    final list = _c.events;
    if (list.isEmpty) {
      return _pad(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(TelemetryStrings.emptyLog, style: context.text.caption),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      sliver: SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) {
          final e = list[i];
          return EventRow(
            key: ValueKey(e.id),
            event: e,
            open: _open.contains(e.id),
            fresh: _c.fresh.contains(e.id),
            onTap: () => setState(
              () => _open.contains(e.id) ? _open.remove(e.id) : _open.add(e.id),
            ),
          );
        },
      ),
    );
  }

  Widget _logFooter(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        top: AppSpacing.md,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
      ),
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
                label: TelemetryStrings.loadMore,
                selected: false,
                onTap: _c.loadMore,
              )
            : Text(
                _c.events.isEmpty ? '' : TelemetryStrings.noMore,
                style: context.text.caption,
              ),
      ),
    );
  }
}
