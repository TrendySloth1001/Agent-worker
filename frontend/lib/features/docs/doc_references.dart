import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/theme/app_palette.dart';
import '../../data/chat_event.dart';
import '../chat/widgets/markdown/citation_chip.dart';
import '../chat/widgets/markdown/evidence_sheet.dart';
import '../chat/widgets/source_chips.dart';

/// Which group of the bibliography a source belongs to.
enum RefGroup {
  web(DocStrings.refWeb),
  knowledge(DocStrings.refKnowledge),
  files(DocStrings.refFiles),
  chats(DocStrings.refChats);

  const RefGroup(this.label);
  final String label;

  static RefGroup of(Citation c) => switch (c.kind) {
    CitationKind.web => web,
    CitationKind.kb => c.site == 'doc' || c.site == 'file' ? files : knowledge,
    CitationKind.file || CitationKind.doc => files,
    CitationKind.conversation => chats,
  };
}

/// Cited sources split by [RefGroup], each group in first-use order. Empty
/// groups are left out.
List<(RefGroup, List<Citation>)> groupReferences(List<Citation> references) => [
  for (final g in RefGroup.values)
    if (references.any((c) => RefGroup.of(c) == g))
      (
        g,
        [
          for (final c in references)
            if (RefGroup.of(c) == g) c,
        ],
      ),
];

/// The bibliography: one rounded card per group of sources. A row has the
/// site logo, name, title (two lines), domain and how often it is cited.
/// Tap opens the source card (VISIT); long-press shows the passage.
class DocReferences extends StatelessWidget {
  const DocReferences({
    super.key,
    required this.references,
    this.counts = const {},
    this.evidence = const [],
  });

  final List<Citation> references;

  /// Times each source id is cited in the document.
  final Map<String, int> counts;
  final List<Evidence> evidence;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final groups = groupReferences(references);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(DocStrings.referencesLabel, style: t.caption),
        const SizedBox(height: AppSpacing.xs),
        Text(
          DocStrings.references,
          style: t.title.copyWith(
            fontSize: DocSizes.sectionHeading,
            height: DocSizes.sectionHeadingHeight,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: DocSizes.headingGap),
        for (final (group, items) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Text('${group.label}  ${items.length}', style: t.caption),
          ),
          _GroupCard(
            children: [
              for (final c in items)
                DocReferenceRow(
                  citation: c,
                  count: counts[c.id] ?? 0,
                  onTap: () =>
                      showSourceCard(context, c, used: (counts[c.id] ?? 0) > 0),
                  onLongPress: () => showEvidenceSheet(context, c, evidence),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: AppBorder.thin,
                thickness: AppBorder.thin,
                indent: DocSizes.referenceInset,
                color: p.border,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One source in the bibliography.
class DocReferenceRow extends StatelessWidget {
  const DocReferenceRow({
    super.key,
    required this.citation,
    required this.count,
    required this.onTap,
    this.onLongPress,
  });

  final Citation citation;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final c = citation;
    final domain = citeDomain(c);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SiteFavicon(citation: c, size: DocSizes.referenceFavicon),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    citeShortName(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    c.title.isEmpty ? c.url : c.title,
                    maxLines: DocSizes.referenceTitleLines,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall.copyWith(color: p.textPrimary),
                  ),
                  if (domain.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      domain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: p.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  DocStrings.citedTimes(count),
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
