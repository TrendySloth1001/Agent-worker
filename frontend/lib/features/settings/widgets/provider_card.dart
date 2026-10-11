import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/dot_meter.dart';
import '../../../data/usage.dart';
import '../format.dart';
import 'section_header.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';

/// One provider: key, live quota, today's usage. Tap to expand details.
class ProviderCard extends StatefulWidget {
  const ProviderCard({super.key, required this.provider});

  final ProviderUsage provider;

  @override
  State<ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<ProviderCard> {
  bool _open = false;

  ProviderUsage get _p => widget.provider;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final attention =
        _p.status == ProviderStatus.exhausted ||
        _p.status == ProviderStatus.limited;
    final (statusLabel, dotColor, hollow) = switch (_p.status) {
      ProviderStatus.ok => (AppStrings.statusOk, p.textPrimary, false),
      ProviderStatus.limited => (AppStrings.statusLimited, p.accent, true),
      ProviderStatus.exhausted => (AppStrings.statusExhausted, p.accent, false),
      ProviderStatus.missing => (
        AppStrings.statusMissing,
        p.textTertiary,
        true,
      ),
      ProviderStatus.unknown => (
        AppStrings.statusUnknown,
        p.textTertiary,
        true,
      ),
    };
    return FlatCard(
      onTap: () {
        Haptics.tap();
        setState(() => _open = !_open);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconLabel(
                      icon: AppIcons.provider(_p.id),
                      text: _p.name.toUpperCase(),
                      style: t.label,
                      iconSize: AppIconSize.sm,
                      expand: true,
                    ),
                    if (_p.plan != null)
                      Text(
                        _p.plan!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusDot(color: dotColor, hollow: hollow),
              const SizedBox(width: AppSpacing.sm),
              Text(
                statusLabel,
                style: t.caption.copyWith(color: attention ? p.accent : null),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _keyRow(context),
          if (_p.configured && _p.quota != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _quota(context, _p.quota!, attention),
          ],
          const SizedBox(height: AppSpacing.md),
          Divider(color: p.border, height: AppBorder.thin),
          _limits(context),
          const SizedBox(height: AppSpacing.lg),
          _footer(context),
          AnimatedSize(
            duration: AppDurations.normal,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? _details(context)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _keyRow(BuildContext context) {
    final p = context.palette;
    final hint = _p.keyHint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(
          AppStrings.keyLabel,
          hint ?? AppStrings.keyNotSet,
          valueColor: hint == null ? p.accent : null,
          icon: AppIcons.key,
        ),
        if (hint == null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.keyNotSetHint,
            style: context.text.bodySmall.copyWith(color: p.textTertiary),
          ),
        ],
      ],
    );
  }

  Widget _quota(BuildContext context, ProviderQuota q, bool attention) {
    final p = context.palette;
    final t = context.text;
    final fraction = q.fraction;
    final big = q.limit != null
        ? '${count(q.used)}${AppStrings.slash}${count(q.limit)}'
        : count(q.used);
    final period = switch (q.period) {
      QuotaPeriod.day =>
        q.rolling ? AppStrings.periodRolling : AppStrings.periodDay,
      QuotaPeriod.month => AppStrings.periodMonth,
      QuotaPeriod.minute => AppStrings.periodMinute,
      QuotaPeriod.unknown => AppStrings.dash,
    };
    final reset = q.resetsAt == null ? null : resetsLabel(q.resetsAt!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  big,
                  style: t.metric.copyWith(color: attention ? p.accent : null),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(period, style: t.caption),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (fraction != null)
          DotMeter(
            fraction: fraction,
            litColor: attention ? p.accent : p.textPrimary,
          )
        else
          Text(AppStrings.noLimitKnown, style: t.caption),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (q.perModel) const MetaChip(AppStrings.perModel),
            MetaChip(q.official ? AppStrings.official : AppStrings.tracked),
            if (reset != null)
              MetaChip(reset, emphasis: _p.status == ProviderStatus.exhausted),
          ],
        ),
      ],
    );
  }

  Widget _limits(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final c = _p.capacity;
    final w = _p.tokensWindow;
    final parts = [
      if (c.requestsPerDay != null)
        '${grouped(c.requestsPerDay)} ${AppStrings.requests}',
      if (c.tokensPerDay != null)
        '${compact(c.tokensPerDay)} ${AppStrings.tokens}',
    ];
    final wf = w?.usedFraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in _p.limits)
          InfoRow(
            l.label.toUpperCase(),
            l.value == null
                ? AppStrings.notPublished
                : '${grouped(l.value)}${l.perModel ? ' ${AppStrings.perModelSuffix}' : ''}',
            valueColor: l.value == null ? p.textTertiary : null,
          ),
        InfoRow(
          AppStrings.expectedPerDay,
          parts.isEmpty
              ? AppStrings.noDailyCapPublished
              : parts.join(AppStrings.separator),
          valueColor: parts.isEmpty ? p.textTertiary : null,
        ),
        if (w != null && w.limit != null) ...[
          InfoRow(
            AppStrings.tokensThisMinute,
            '${grouped(w.remaining)}${AppStrings.slash}${grouped(w.limit)} ${AppStrings.left}',
          ),
          if (wf != null) ...[
            const SizedBox(height: AppSpacing.sm),
            DotMeter(fraction: wf, litColor: p.textPrimary),
          ],
        ],
        if (_p.limitsSource != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _p.limitsSource!,
            style: t.caption.copyWith(color: p.textTertiary),
          ),
        ],
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final d = _p.today;
    final failed = (d.failures ?? 0) > 0;
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: t.caption,
              children: [
                TextSpan(text: '${AppStrings.today} '),
                TextSpan(
                  text:
                      '${compact(d.requests)} ${AppStrings.reqShort}${AppStrings.separator}'
                      '${compact(d.tokens)} ${AppStrings.tokShort}',
                  style: t.caption.copyWith(color: p.textPrimary),
                ),
                if (failed)
                  TextSpan(
                    text:
                        '${AppStrings.separator}${d.failures} ${AppStrings.failShort}',
                    style: t.caption.copyWith(color: p.accent),
                  ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppIcon(
          _open ? AppIcons.collapse : AppIcons.expand,
          size: AppIconSize.md,
          color: p.textSecondary,
        ),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Divider(color: p.border, height: AppBorder.thin),
        const SizedBox(height: AppSpacing.md),
        Text(AppStrings.modelsLabel, style: t.caption),
        const SizedBox(height: AppSpacing.sm),
        if (_p.models.isEmpty)
          Text(AppStrings.noModels, style: t.caption)
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final m in _p.models) MetaChip(m)],
          ),
        const SizedBox(height: AppSpacing.xs),
        InfoRow(
          AppStrings.monthLabel,
          '${compact(_p.month.requests)} ${AppStrings.reqShort}${AppStrings.separator}'
          '${compact(_p.month.tokens)} ${AppStrings.tokShort}',
        ),
        InfoRow(
          AppStrings.coolingLabel,
          count(_p.coolingModels),
          valueColor: _p.coolingModels > 0 ? p.accent : null,
        ),
        InfoRow(
          AppStrings.lastLimitHit,
          _p.lastLimitHitAt == null
              ? AppStrings.never
              : agoLabel(_p.lastLimitHitAt!),
        ),
      ],
    );
  }
}
