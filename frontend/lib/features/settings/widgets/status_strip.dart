import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/usage.dart';
import '../format.dart';
import 'section_header.dart';

/// Top summary: overall health plus three headline numbers.
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.usage, required this.health});

  final UsageSnapshot usage;
  final HealthStatus? health;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final offline = health != null && !health!.online;
    final degraded = health != null && !health!.ok;
    final (label, color, hollow) = offline
        ? (AppStrings.offline, p.accent, true)
        : degraded
        ? (AppStrings.degraded, p.accent, false)
        : (AppStrings.allSystems, p.textPrimary, false);
    final total = usage.providers.length;
    final atLimit = usage.atLimit;
    final uncapped = usage.totals.uncappedProviders;
    final known = usage.totals.knownDailyRequests;
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: color, hollow: hollow),
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: t.label.copyWith(color: color)),
            ],
          ),
          if (atLimit.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${atLimit.length} '
              '${atLimit.length == 1 ? AppStrings.providerAtLimit : AppStrings.providersAtLimit}'
              '${AppStrings.separator}'
              '${atLimit.map((e) => e.name.toUpperCase()).join(', ')}',
              style: t.caption.copyWith(color: p.accent),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stat(
                context,
                AppStrings.requestsToday,
                grouped(usage.requestsToday),
              ),
              _stat(
                context,
                AppStrings.tokensToday,
                compact(usage.tokensToday),
              ),
              _stat(
                context,
                AppStrings.providersActive,
                '${usage.activeProviders}${AppStrings.slash}$total',
              ),
            ],
          ),
          if (known != null || uncapped.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(color: p.border, height: AppBorder.thin),
            const SizedBox(height: AppSpacing.md),
            Text(AppStrings.expectedCapacity, style: t.caption),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                if (known != null)
                  '${AppStrings.approx} ${grouped(known)} ${AppStrings.requests}',
                if (uncapped.isNotEmpty)
                  '${known != null ? '${AppStrings.plus} ' : ''}'
                      '${uncapped.map((e) => e.toUpperCase()).join(', ')} '
                      '${AppStrings.noDailyCapSuffix}',
              ].join(' '),
              style: t.label,
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: context.text.metric),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.caption,
          ),
        ],
      ),
    );
  }
}
