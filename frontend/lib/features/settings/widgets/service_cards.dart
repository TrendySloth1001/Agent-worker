import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/dot_meter.dart';
import '../../../data/usage.dart';
import '../format.dart';
import 'section_header.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';

/// Title row (with optional trailing) above a column of [InfoRow]s.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.title,
    required this.children,
    required this.icon,
    this.trailing,
    this.onTap,
  });

  final String title;
  final AppIconData icon;
  final Widget? trailing;
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FlatCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: IconLabel(
                  icon: icon,
                  text: title,
                  style: context.text.label,
                  iconSize: AppIconSize.sm,
                  expand: true,
                ),
              ),
              ?trailing,
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}

String _upper(String? v) => v == null ? AppStrings.dash : v.toUpperCase();

class GithubCard extends StatelessWidget {
  const GithubCard({super.key, required this.github});

  final GithubService github;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final g = github;
    final failed = g.error != null;
    final fraction = g.usedFraction;
    final (label, color, hollow) = !g.configured
        ? (AppStrings.statusMissing, p.textTertiary, true)
        : failed
        ? (AppStrings.failed, p.accent, false)
        : (AppStrings.statusOk, p.textPrimary, false);
    return _ServiceCard(
      title: AppStrings.githubToken,
      icon: AppIcons.github,
      trailing: Row(
        children: [
          StatusDot(color: color, hollow: hollow),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: t.caption.copyWith(color: failed ? p.accent : null),
          ),
        ],
      ),
      children: [
        InfoRow(
          AppStrings.keyLabel,
          g.keyHint ?? AppStrings.keyNotSet,
          valueColor: g.keyHint == null ? p.accent : null,
          icon: AppIcons.key,
        ),
        if (g.login != null)
          InfoRow(AppStrings.account, '${AppStrings.handle}${g.login}'),
        if (g.limit != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${count(g.remaining)}${AppStrings.slash}${count(g.limit)}',
                    style: t.metric,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${AppStrings.remaining} ${AppStrings.perHour}',
                  style: t.caption,
                ),
              ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: AppSpacing.md),
            DotMeter(fraction: fraction, litColor: p.textPrimary),
          ],
          if (g.resetsAt != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(children: [MetaChip(resetsLabel(g.resetsAt!))]),
          ],
        ],
        if (g.limitLabel != null) InfoRow(AppStrings.limitLabel, g.limitLabel!),
        if (g.purpose != null) InfoRow(AppStrings.purpose, g.purpose!),
        if (failed) InfoRow(AppStrings.failed, g.error!, valueColor: p.accent),
      ],
    );
  }
}

class EmbeddingsCard extends StatelessWidget {
  const EmbeddingsCard({super.key, required this.embeddings});

  final EmbeddingsService embeddings;

  @override
  Widget build(BuildContext context) {
    final e = embeddings;
    return _ServiceCard(
      title: AppStrings.embeddings,
      icon: AppIcons.embeddings,
      children: [
        InfoRow(AppStrings.provider, _upper(e.provider)),
        InfoRow(AppStrings.model, e.model ?? AppStrings.dash),
        InfoRow(AppStrings.dimensions, count(e.dimensions)),
        InfoRow(
          AppStrings.today,
          '${compact(e.requestsToday)} ${AppStrings.reqShort}${AppStrings.separator}'
          '${compact(e.textsToday)} ${AppStrings.texts}',
        ),
        if (e.limitLabel != null) InfoRow(AppStrings.limitLabel, e.limitLabel!),
      ],
    );
  }
}

class SearchCard extends StatelessWidget {
  const SearchCard({super.key, required this.search});

  final SearchService search;

  @override
  Widget build(BuildContext context) {
    return _ServiceCard(
      title: AppStrings.search,
      icon: AppIcons.search,
      children: [
        InfoRow(AppStrings.provider, _upper(search.provider)),
        InfoRow(
          AppStrings.today,
          '${compact(search.today)} ${AppStrings.requests}',
        ),
        InfoRow(
          AppStrings.thisMonth,
          '${compact(search.month)} ${AppStrings.requests}',
        ),
        if (search.limitLabel != null)
          InfoRow(AppStrings.limitLabel, search.limitLabel!),
      ],
    );
  }
}

class KnowledgeCard extends StatelessWidget {
  const KnowledgeCard({super.key, required this.kb, required this.onOpen});

  final KbStats? kb;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _ServiceCard(
      title: AppStrings.knowledge,
      icon: AppIcons.knowledge,
      onTap: onOpen,
      trailing: Row(
        children: [
          Text(AppStrings.openKnowledge, style: context.text.caption),
          AppIcon(
            AppIcons.chevronRight,
            size: AppIconSize.md,
            color: p.textSecondary,
          ),
        ],
      ),
      children: [
        InfoRow(AppStrings.sourcesCount, count(kb?.sources)),
        InfoRow(AppStrings.chunks, count(kb?.chunks)),
      ],
    );
  }
}
