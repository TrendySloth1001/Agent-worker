import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/chat_event.dart';
import '../open_url.dart';
import 'citation_chip.dart';

/// Opens the sheet that shows which passage of a source backs a claim.
Future<void> showEvidenceSheet(
  BuildContext context,
  Citation citation,
  List<Evidence> evidence,
) {
  final p = context.palette;
  final items = [
    for (final e in evidence)
      if (e.tag == citation.id) e,
  ].take(MdSizes.evidenceMaxItems).toList();
  Haptics.tap();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (sheet) => _EvidenceSheet(
      citation: citation,
      items: items,
      onOpen: () {
        Navigator.pop(sheet);
        visitUrl(context, citation.url);
      },
    ),
  );
}

class _EvidenceSheet extends StatelessWidget {
  const _EvidenceSheet({
    required this.citation,
    required this.items,
    required this.onOpen,
  });

  final Citation citation;
  final List<Evidence> items;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.lg,
                AppSpacing.screenPadding,
                AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SiteFavicon(citation: citation, size: AppIconSize.md),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          citation.title.isEmpty
                              ? citation.url
                              : citation.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.body,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          citeDomain(citation).isEmpty
                              ? citation.url
                              : citeDomain(citation),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: AppBorder.thin, color: p.border),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  if (items.isEmpty)
                    if (citation.snippet.isNotEmpty)
                      _Passage(text: citation.snippet),
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xl),
                    _EvidenceBlock(item: items[i]),
                  ],
                ],
              ),
            ),
            Divider(height: AppBorder.thin, color: p.border),
            _Action(
              icon: AppIcons.openExternal,
              label: AppStrings.openSource,
              onTap: onOpen,
            ),
            if (items.isNotEmpty)
              _Action(
                icon: AppIcons.copy,
                label: AppStrings.copyQuote,
                onTap: () =>
                    _toast(context, items.first.quote, AppStrings.quoteCopied),
              ),
            _Action(
              icon: AppIcons.link,
              label: AppStrings.copyLinkAction,
              onTap: () => _toast(context, citation.url, AppStrings.copyLink),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toast(BuildContext context, String value, String note) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    await Clipboard.setData(ClipboardData(text: value));
    messenger?.showSnackBar(SnackBar(content: Text(note)));
  }
}

class _EvidenceBlock extends StatelessWidget {
  const _EvidenceBlock({required this.item});

  final Evidence item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppStrings.evidenceClaim, style: t.caption),
        const SizedBox(height: AppSpacing.xs),
        _Barred(
          color: p.border,
          child: Text(item.claim, style: t.body),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(AppStrings.evidencePassage, style: t.caption),
        const SizedBox(height: AppSpacing.xs),
        _Passage(text: item.quote),
        const SizedBox(height: AppSpacing.md),
        _Strength(score: item.score),
      ],
    );
  }
}

class _Passage extends StatelessWidget {
  const _Passage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Barred(
      color: p.accent,
      child: Text(
        text,
        style: context.text.code.copyWith(
          fontSize: AppFontSize.bodySmall,
          color: p.textPrimary,
        ),
      ),
    );
  }
}

class _Barred extends StatelessWidget {
  const _Barred({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: MdSizes.evidenceBar,
            child: ColoredBox(color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Strength extends StatelessWidget {
  const _Strength({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final filled = (score.clamp(0.0, 1.0) * MdSizes.evidenceMeterDots)
        .ceil()
        .clamp(1, MdSizes.evidenceMeterDots);
    final label = score >= MdSizes.evidenceStrongScore
        ? AppStrings.evidenceStrong
        : score >= MdSizes.evidencePartialScore
        ? AppStrings.evidencePartial
        : AppStrings.evidenceWeak;
    return Row(
      children: [
        Text(AppStrings.evidenceMatch, style: t.caption),
        const SizedBox(width: AppSpacing.sm),
        for (var i = 0; i < MdSizes.evidenceMeterDots; i++) ...[
          if (i > 0) const SizedBox(width: MdSizes.evidenceMeterGap),
          Container(
            width: MdSizes.evidenceMeterDot,
            height: MdSizes.evidenceMeterDot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? p.accent : Colors.transparent,
              border: Border.all(
                color: i < filled ? p.accent : p.border,
                width: AppBorder.thin,
              ),
            ),
          ),
        ],
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: t.label),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: SizedBox(
          height: AppSizes.rowHeight,
          child: Row(
            children: [
              AppIcon(
                icon,
                size: AppIconSize.md,
                color: context.palette.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: context.text.label),
            ],
          ),
        ),
      ),
    );
  }
}
