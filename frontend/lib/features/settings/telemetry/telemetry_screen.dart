import '../../../core/constants/mascot.dart';
import '../../../core/widgets/mascot.dart';
import 'dart:async';

import 'package:flutter/material.dart';

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
import '../widgets/usage_states.dart';
import 'telemetry_controller.dart';
import 'telemetry_format.dart';
import 'telemetry_grouping.dart';
import 'telemetry_widgets.dart';

/// Owner-only: every model call, minute by minute. Plain type and hairlines,
/// no cards: summary, activity, providers, models, cost per message, errors,
/// users and the latest calls.
class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({super.key, this.api});

  /// Test seam; defaults to the app's API.
  final TelemetryApi? api;

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen> {
  late final TelemetryController _c;
  final Set<String> _open = {};
  Metric _metric = Metric.requests;
  bool _allCalls = false;
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _c = TelemetryController(widget.api ?? TelemetryApi(AppConfig.apiBaseUrl))
      ..start();
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

  void _toggle(String key) => setState(() {
    if (!_open.remove(key)) _open.add(key);
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => M3Page(
        title: TelemetryStrings.title,
        onRefresh: _c.reload,
        actions: [LiveDot(state: _c.live, paused: _c.paused)],
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            sliver: SliverToBoxAdapter(
              child: Builder(
                builder: (context) => _c.overview == null
                    ? _placeholder(context)
                    : _body(context, _c.overview!),
              ),
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: LinearProgressIndicator(
        minHeight: AppBorder.thin,
        color: context.palette.accent,
        backgroundColor: context.palette.border,
      ),
    );
  }

  // ---- body ---------------------------------------------------------------------

  Widget _body(BuildContext context, TelemetryOverview o) {
    final a = o.totals;
    final p = context.palette;
    final provider = _c.filters.provider;
    final models = groupModels(o.models);
    final errors = groupErrors(o.topErrors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
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
        const SizedBox(height: AppSpacing.xs),
        FilterBar(
          kinds: {?_c.filters.kind, for (final x in o.kinds) x.name}.toList(),
          kind: _c.filters.kind,
          onKind: _c.setKind,
          provider: provider,
          onClearProvider: () => _c.setProvider(null),
        ),
        if (_c.error != null) ...[
          UsageError(onRetry: _c.reload, stale: true, loading: _c.loading),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.md),
        SummaryRow(
          stats: [
            SummaryStat(
              compact(a.requests),
              TelemetryCopy.summaryRequests,
              icon: TelemetryIcons.log,
            ),
            SummaryStat(
              compact(a.failed),
              TelemetryCopy.summaryFailed,
              sub: pct(a.failureRate),
              alert: a.failed > 0 && a.failureRate > TelemetrySizes.failWarn,
              icon: TelemetryIcons.failed,
            ),
            SummaryStat(
              compact(a.tokens),
              TelemetryCopy.summaryTokens,
              icon: TelemetryIcons.tokens,
            ),
            SummaryStat(
              ms(a.latencyP50),
              TelemetryCopy.summaryP50,
              unit: true,
              icon: TelemetryIcons.latency,
            ),
          ],
        ),
        if (a.unknown > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              '${grouped(a.unknown)} ${TelemetryCopy.unknownNote}',
              style: TType.secondary(context, color: p.textTertiary),
            ),
          ),
        if (a.requests == 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: Column(
              children: [
                const Mascot(
                  state: MascotState.sleeping,
                  size: MascotSizes.large,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  TelemetryCopy.empty,
                  textAlign: TextAlign.center,
                  style: TType.secondary(context),
                ),
              ],
            ),
          ),
        _activity(context),
        if (o.providers.isNotEmpty) _providers(context, o),
        if (models.groups.isNotEmpty) _models(context, models, errors),
        if (provider == null && o.turns != null) _turns(context, o.turns!),
        if (provider == null && o.budgets != null)
          _budgets(context, o.budgets!),
        if (errors.isNotEmpty) _errors(context, errors),
        _calls(context),
      ],
    );
  }

  Widget _activity(BuildContext context) {
    final p = context.palette;
    final s = _c.series;
    return TSection(
      title: TelemetryCopy.activity,
      icon: TelemetryIcons.chart,
      trailing: Wrap(
        spacing: AppSpacing.md,
        children: switch (_metric) {
          Metric.requests => [
            LegendItem(
              p.textSecondary,
              TelemetryStrings.legendOk.toLowerCase(),
            ),
            LegendItem(p.accent, TelemetryStrings.legendFailed.toLowerCase()),
          ],
          Metric.tokens => const [],
          Metric.latency => [
            LegendItem(p.textPrimary, TelemetryStrings.legendLatency),
            LegendItem(p.textTertiary, TelemetryStrings.legendTtft),
          ],
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricTabs(
            value: _metric,
            onChanged: (m) => setState(() => _metric = m),
          ),
          const Hairline(),
          const SizedBox(height: AppSpacing.md),
          if (s != null) ActivityChart(series: s, metric: _metric),
          if (_c.loading)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: LinearProgressIndicator(
                minHeight: AppBorder.thin,
                color: p.accent,
                backgroundColor: p.border,
              ),
            ),
        ],
      ),
    );
  }

  Widget _providers(BuildContext context, TelemetryOverview o) {
    return TSection(
      title: TelemetryCopy.providers,
      icon: TelemetryIcons.providers,
      child: PlainList(
        children: [
          for (final x in o.providers)
            ProviderRow(
              key: ValueKey('provider-${x.name}'),
              provider: x,
              selected: _c.filters.provider == x.name,
              detail: rateLimitLine(o.models, x.name, _now),
              onTap: () =>
                  _c.setProvider(_c.filters.provider == x.name ? null : x.name),
            ),
        ],
      ),
    );
  }

  Widget _models(
    BuildContext context,
    ({List<ModelGroup> groups, int hidden}) models,
    List<ErrorGroup> errors,
  ) {
    return TSection(
      title: TelemetryCopy.models,
      icon: TelemetryIcons.models,
      note: models.hidden > 0
          ? '${TelemetryCopy.modelsUnused}: ${models.hidden}'
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ModelColumns(),
          const Hairline(),
          PlainList(
            children: [
              for (final g in models.groups)
                ModelRow(
                  key: ValueKey('model-${g.key}'),
                  group: g,
                  now: _now,
                  open: _open.contains('model-${g.key}'),
                  errors: [
                    for (final e in errors)
                      if (e.model == g.key) e,
                  ],
                  onTap: () => _toggle('model-${g.key}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _turns(BuildContext context, TurnTelemetry t) {
    return TSection(
      title: TelemetryCopy.perTurn,
      icon: TelemetryIcons.tokens,
      note: TelemetryCopy.turnExtraNote,
      child: SummaryRow(
        stats: [
          SummaryStat(compact(t.turns), TelemetryCopy.turnMessages),
          SummaryStat(
            t.auxAvg.toStringAsFixed(1),
            TelemetryCopy.turnExtraCalls,
            sub: '${TelemetryStrings.avg.toLowerCase()}, max ${t.auxMax}',
          ),
          SummaryStat(
            ms(t.ttftAvg),
            TelemetryCopy.turnTtft,
            unit: true,
            sub: '${TelemetryStrings.p50.toLowerCase()} ${ms(t.ttftP50)}',
          ),
        ],
      ),
    );
  }

  Widget _budgets(BuildContext context, TelemetryBudgets b) {
    return TSection(
      title: TelemetryCopy.budgets,
      icon: TelemetryIcons.tokens,
      note: TelemetryCopy.budgetsNote,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SummaryRow(
            stats: [
              SummaryStat(compact(b.skips), TelemetryCopy.budgetSkips),
              SummaryStat(compact(b.waits), TelemetryCopy.budgetWaits),
              SummaryStat(
                compact(b.auxDeferred),
                TelemetryCopy.budgetAuxDeferred,
                sub:
                    '${compact(b.auxCacheHits)} ${TelemetryCopy.budgetAuxCached.toLowerCase()}',
              ),
              SummaryStat(compact(b.userCaps), TelemetryCopy.budgetUserCaps),
            ],
          ),
          if (b.scopes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            PlainList(
              children: [
                for (final s in b.scopes.take(TelemetrySizes.budgetsShown))
                  KeyValue(budgetScopeLabel(s.scope), budgetLine(s)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _errors(BuildContext context, List<ErrorGroup> errors) {
    return TSection(
      title: TelemetryCopy.errors,
      icon: TelemetryIcons.errors,
      child: PlainList(
        children: [
          for (final e in errors.take(TelemetrySizes.topErrorsShown))
            ErrorRow(
              key: ValueKey('error-${e.code}-${e.model}'),
              group: e,
              now: _now,
              open: _open.contains('error-${e.code}-${e.model}'),
              onTap: () => _toggle('error-${e.code}-${e.model}'),
            ),
        ],
      ),
    );
  }

  Widget _calls(BuildContext context) {
    final list = _c.events;
    final shown = _allCalls
        ? list.take(TelemetrySizes.callsShown + TelemetrySizes.callsMore)
        : list.take(TelemetrySizes.callsShown);
    return TSection(
      title: TelemetryCopy.recentCalls,
      icon: TelemetryIcons.log,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextAction(
            label: TelemetryCopy.failedOnly,
            icon: TelemetryIcons.failed,
            active: _c.failedOnly,
            onTap: () => _c.setFailedOnly(!_c.failedOnly),
          ),
          TextAction(
            label: _c.paused
                ? '${TelemetryCopy.resume}${_c.heldCount > 0 ? ' +${_c.heldCount}' : ''}'
                : TelemetryCopy.pause,
            icon: _c.paused ? TelemetryIcons.resume : TelemetryIcons.pause,
            active: _c.paused,
            onTap: _c.togglePause,
          ),
        ],
      ),
      child: list.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                TelemetryCopy.emptyLog,
                style: TType.secondary(context),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PlainList(
                  children: [
                    for (final e in shown)
                      CallRow(
                        key: ValueKey('call-${e.id}'),
                        event: e,
                        open: _open.contains('call-${e.id}'),
                        onTap: () => _toggle('call-${e.id}'),
                      ),
                  ],
                ),
                if (list.length > TelemetrySizes.callsShown)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 0),
                      child: TextAction(
                        label: _allCalls
                            ? TelemetryCopy.showLess
                            : TelemetryCopy.showMore,
                        onTap: () => setState(() => _allCalls = !_allCalls),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
