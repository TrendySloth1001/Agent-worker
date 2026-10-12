import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/dot_meter.dart';
import '../../../core/widgets/icon_label.dart';
import '../../../data/telemetry.dart';
import '../format.dart';
import '../widgets/section_header.dart';
import 'telemetry_controller.dart';
import 'telemetry_format.dart';

/// Pulsing red dot while the stream is connected; hollow otherwise.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        on ? FadeTransition(opacity: _c, child: dot) : dot,
        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
        Text(
          label,
          style: context.text.caption.copyWith(
            color: on ? p.accent : p.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// One big number with a mono caption above it.
class StatTile extends StatelessWidget {
  const StatTile(
    this.label,
    this.value, {
    super.key,
    this.alert = false,
    this.sub,
  });

  final String label, value;
  final String? sub;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.caption, maxLines: 1),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: t.metric.copyWith(color: alert ? p.accent : null),
          ),
        ),
        if (sub != null)
          Text(
            sub!,
            style: t.caption.copyWith(color: alert ? p.accent : null),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// Tiles in a fixed number of columns, wrapping on narrow screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / TelemetrySizes.statTileMinWidth)
            .floor()
            .clamp(1, TelemetrySizes.statColumns);
        final w = (c.maxWidth - AppSpacing.md * (cols - 1)) / cols;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.lg,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

/// Mono pill that inverts when selected.
class TelemetryChip extends StatelessWidget {
  const TelemetryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.alert = false,
  });

  final String label;
  final bool selected, alert;
  final AppIconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.textInverse : (alert ? p.accent : p.textSecondary);
    return GestureDetector(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Container(
        height: TelemetrySizes.chipHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.chipHorizontalPadding,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: selected
              ? (alert ? p.accent : p.textPrimary)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? (alert ? p.accent : p.textPrimary)
                : (alert ? p.accent : p.borderStrong),
            width: AppBorder.thin,
          ),
        ),
        child: icon == null
            ? Text(label, style: context.text.caption.copyWith(color: fg))
            : IconLabel(
                icon: icon!,
                text: label,
                style: context.text.caption,
                color: fg,
              ),
      ),
    );
  }
}

/// A horizontally scrolling row of single-choice chips; null is ALL.
class ChipRow extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelect,
    this.display = kindLabel,
  });

  final String label;
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final String Function(String) display;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TelemetrySizes.chipHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Center(child: Text(label, style: context.text.caption)),
          const SizedBox(width: AppSpacing.sm),
          TelemetryChip(
            label: TelemetryStrings.filterAll,
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final v in values) ...[
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            TelemetryChip(
              label: display(v),
              selected: selected == v,
              onTap: () => onSelect(selected == v ? null : v),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small tag: OK in neutral, a failure code in red.
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.ok, this.code});

  final bool ok;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = ok
        ? TelemetryStrings.statusOk
        : (code ?? TelemetryStrings.statusFailed).toUpperCase();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.caption.copyWith(
        color: ok ? p.textSecondary : p.accent,
      ),
    );
  }
}

/// Every model: requests, failure rate, tokens, latency, cooldown, rate
/// limit. Tap expands the details; DETAILS opens the model screen.
class ModelRow extends StatefulWidget {
  const ModelRow({
    super.key,
    required this.model,
    required this.now,
    required this.onOpen,
  });

  final ModelTelemetry model;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  State<ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends State<ModelRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final a = m.agg;
    final p = context.palette;
    final t = context.text;
    final cd = m.cooldownLeft(widget.now);
    final failing = a.failed > 0;
    return FlatCard(
      onTap: () {
        Haptics.tap();
        setState(() => _open = !_open);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: IconLabel(
                  icon: TelemetryIcons.provider(m.provider),
                  text: m.name,
                  style: t.label,
                  iconSize: AppIconSize.sm,
                  expand: true,
                ),
              ),
              if (cd != null) ...[
                const SizedBox(width: AppSpacing.sm),
                IconLabel(
                  icon: TelemetryIcons.cooldown,
                  text: '${TelemetryStrings.cooldown} ${countdown(cd)}',
                  style: t.caption,
                  color: p.accent,
                ),
              ] else if (a.requests == 0) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  m.inRegistry
                      ? TelemetryStrings.unused
                      : TelemetryStrings.notRouted,
                  style: t.caption,
                ),
              ],
            ],
          ),
          Text(
            '${providerLabel(m.provider)}${TelemetryStrings.separator}'
            '${m.model ?? TelemetryStrings.noModel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          StatGrid(
            tiles: [
              StatTile(TelemetryStrings.requests, grouped(a.requests)),
              StatTile(
                TelemetryStrings.failureRate,
                pct(a.failureRate),
                alert: failing,
                sub: '${a.failed} ${TelemetryStrings.failed}',
              ),
              StatTile(
                TelemetryStrings.tokensShort,
                compact(a.tokens),
                sub: inOut(a.tokensIn, a.tokensOut),
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
              StatTile(
                TelemetryStrings.lastCall,
                a.lastAt == null ? AppStrings.dash : clock(a.lastAt!),
                sub: a.lastAt == null ? null : agoLabel(a.lastAt!, widget.now),
              ),
            ],
          ),
          if (m.rateLimit != null) ...[
            const SizedBox(height: AppSpacing.md),
            _rate(context, m.rateLimit!),
          ],
          AnimatedSize(
            duration: AppDurations.normal,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? _details(context, m)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _rate(BuildContext context, TelemetryRateLimit r) {
    final p = context.palette;
    final limit = r.limitRequests;
    final left = r.remainingRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(TelemetryStrings.rateLimit, style: context.text.caption),
        const SizedBox(height: AppSpacing.xs),
        if (limit != null && left != null && limit > 0)
          DotMeter(
            fraction: 1 - left / limit,
            litColor: left == 0 ? p.accent : p.textPrimary,
          ),
        InfoRow(
          TelemetryStrings.rateRequests,
          '${grouped(left)}${TelemetryStrings.slash}${grouped(limit)}',
          valueColor: left == 0 ? p.accent : null,
        ),
        if (r.limitTokens != null)
          InfoRow(
            TelemetryStrings.rateTokens,
            '${grouped(r.remainingTokens)}${TelemetryStrings.slash}'
            '${grouped(r.limitTokens)}',
          ),
        if (r.resetsAt != null)
          InfoRow(TelemetryStrings.rateResets, resetsLabel(r.resetsAt!)),
      ],
    );
  }

  Widget _details(BuildContext context, ModelTelemetry m) {
    final p = context.palette;
    final t = context.text;
    final e = m.lastError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Divider(color: p.border, height: AppBorder.thin),
        if (m.failuresByCode.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(TelemetryStrings.failuresByCode, style: t.caption),
          for (final c in m.failuresByCode.entries)
            InfoRow(
              c.key.toUpperCase(),
              grouped(c.value),
              valueColor: p.accent,
            ),
        ],
        if (e != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(TelemetryStrings.lastError, style: t.caption),
          InfoRow(
            clock(e.at),
            '${(e.code ?? TelemetryStrings.statusFailed).toUpperCase()}'
            '${TelemetryStrings.separator}${kindLabel(e.kind ?? '')}',
            valueColor: p.accent,
          ),
          if (e.message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            SelectableText(e.message!, style: t.bodySmall),
          ],
        ],
        InfoRow(
          TelemetryStrings.latency,
          '${TelemetryStrings.avg} ${ms(m.agg.latencyAvg)}',
        ),
        if (m.agg.units != m.agg.requests)
          InfoRow(TelemetryStrings.units, grouped(m.agg.units)),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: TelemetryChip(
            label: TelemetryStrings.openDetail,
            icon: TelemetryIcons.chevron,
            selected: false,
            onTap: widget.onOpen,
          ),
        ),
      ],
    );
  }
}

/// One line of the live log; tap shows every field.
class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.event,
    required this.open,
    required this.fresh,
    required this.onTap,
  });

  final TelemetryEvent event;
  final bool open, fresh;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final p = context.palette;
    final t = context.text;
    final tokens = e.tokens;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.border, width: AppBorder.thin),
            left: BorderSide(
              color: e.ok ? Colors.transparent : p.accent,
              width: AppBorder.thick,
            ),
          ),
          color: fresh ? p.surfaceRaised : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: TelemetrySizes.eventTimeWidth,
                  child: Text(
                    clock(e.ts),
                    style: t.caption.copyWith(color: p.textPrimary),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: TelemetrySizes.eventKindMax,
                  ),
                  child: Text(
                    kindLabel(e.purpose),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    e.model ?? providerLabel(e.provider),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: TelemetrySizes.eventStatusWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: StatusTag(ok: e.ok, code: e.errorCode),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                const SizedBox(width: TelemetrySizes.eventTimeWidth),
                Expanded(
                  child: Text(
                    [
                      ms(e.latencyMs),
                      if (e.ttftMs != null)
                        '${TelemetryStrings.ttft} ${ms(e.ttftMs)}',
                      if (tokens > 0)
                        '${compact(tokens)} ${TelemetryStrings.tokensShort}',
                      if (e.attempt != null && e.attempt! > 1)
                        '${TelemetryStrings.times}${e.attempt}',
                      e.userEmail ?? TelemetryStrings.system,
                    ].join(TelemetryStrings.separator),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption,
                  ),
                ),
              ],
            ),
            if (open) _details(context),
          ],
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    final e = event;
    final p = context.palette;
    String v(Object? x) => x == null ? AppStrings.dash : '$x';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRow(TelemetryStrings.fieldTime, e.ts.toIso8601String()),
          InfoRow(TelemetryStrings.fieldProvider, providerLabel(e.provider)),
          InfoRow(TelemetryStrings.fieldModel, v(e.model)),
          InfoRow(TelemetryStrings.fieldKind, e.kind.toUpperCase()),
          InfoRow(TelemetryStrings.fieldPurpose, kindLabel(e.purpose)),
          InfoRow(
            TelemetryStrings.fieldStatus,
            '${e.ok ? TelemetryStrings.statusOk : TelemetryStrings.statusFailed}'
            '${e.status == null ? '' : ' ${e.status}'}',
            valueColor: e.ok ? null : p.accent,
          ),
          if (!e.ok) ...[
            InfoRow(
              TelemetryStrings.fieldError,
              v(e.errorCode?.toUpperCase()),
              valueColor: p.accent,
            ),
            if (e.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              SelectableText(e.errorMessage!, style: context.text.bodySmall),
            ],
          ],
          InfoRow(TelemetryStrings.fieldLatency, ms(e.latencyMs)),
          InfoRow(TelemetryStrings.fieldTtft, ms(e.ttftMs)),
          InfoRow(
            TelemetryStrings.fieldTokens,
            '${grouped(e.promptTokens)}${TelemetryStrings.slash}'
            '${grouped(e.completionTokens)}',
          ),
          InfoRow(TelemetryStrings.fieldCount, '${e.count}'),
          InfoRow(TelemetryStrings.fieldAttempt, v(e.attempt)),
          InfoRow(
            TelemetryStrings.fieldUser,
            e.userEmail ?? e.userId ?? TelemetryStrings.system,
          ),
          InfoRow(TelemetryStrings.fieldRequest, v(e.requestId)),
          InfoRow(TelemetryStrings.fieldConversation, v(e.conversationId)),
          InfoRow(TelemetryStrings.fieldId, e.id),
        ],
      ),
    );
  }
}

/// Requests, failures and tokens for one named slice (provider or kind).
class AggLine extends StatelessWidget {
  const AggLine({super.key, required this.name, required this.agg, this.icon});

  final String name;
  final TelemetryAgg agg;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: AppIconSize.xs, color: p.textSecondary),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          ],
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(color: p.textPrimary),
            ),
          ),
          Text(
            [
              grouped(agg.requests),
              if (agg.failed > 0)
                '${agg.failed} ${TelemetryStrings.statusFailed}',
              '${compact(agg.tokens)} ${TelemetryStrings.tokensShort}',
              ms(agg.latencyP50),
            ].join(TelemetryStrings.separator),
            style: t.caption.copyWith(
              color: agg.failed > 0 ? p.accent : p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who called: today and in the window.
class UserLine extends StatelessWidget {
  const UserLine({super.key, required this.user});

  final UserTelemetry user;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final t = context.text;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  u.email ?? TelemetryStrings.system,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.label,
                ),
              ),
              if (u.role != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(u.role!.toUpperCase(), style: t.caption),
              ],
            ],
          ),
          InfoRow(
            TelemetryStrings.today,
            '${grouped(u.todayRequests)} ${TelemetryStrings.requests}'
            '${TelemetryStrings.separator}${compact(u.todayTokens)} '
            '${TelemetryStrings.tokensShort}'
            '${u.todayFailed > 0 ? '${TelemetryStrings.separator}${u.todayFailed} ${TelemetryStrings.failed}' : ''}',
            valueColor: u.todayFailed > 0 ? p.accent : null,
          ),
          InfoRow(
            TelemetryStrings.inWindow,
            '${grouped(u.window.requests)} ${TelemetryStrings.requests}'
            '${TelemetryStrings.separator}${compact(u.window.tokens)} '
            '${TelemetryStrings.tokensShort}'
            '${u.window.failed > 0 ? '${TelemetryStrings.separator}${u.window.failed} ${TelemetryStrings.failed}' : ''}',
            valueColor: u.window.failed > 0 ? p.accent : null,
          ),
        ],
      ),
    );
  }
}

/// A grouped failure: code, model, count and the message.
class ErrorLine extends StatelessWidget {
  const ErrorLine({super.key, required this.error});

  final TopError error;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final t = context.text;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.alert, size: AppIconSize.xs, color: p.accent),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Text(
                (e.code ?? TelemetryStrings.statusFailed).toUpperCase(),
                style: t.caption.copyWith(color: p.accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${providerLabel(e.provider)}${TelemetryStrings.separator}'
                  '${e.model ?? TelemetryStrings.noModel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
                ),
              ),
              Text(
                '${TelemetryStrings.times}${grouped(e.count)}',
                style: t.caption.copyWith(color: p.textPrimary),
              ),
            ],
          ),
          if (e.message != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                e.message!,
                maxLines: TelemetrySizes.errorLines,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall,
              ),
            ),
          if (e.lastAt != null) Text(agoLabel(e.lastAt!), style: t.caption),
        ],
      ),
    );
  }
}
