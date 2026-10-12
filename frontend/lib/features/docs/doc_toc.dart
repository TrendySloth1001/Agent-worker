import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/doc_models.dart';
import 'doc_progress.dart';

/// One line of the table of contents.
typedef DocTocEntry = ({String number, String heading, String? status});

/// TOC lines for [doc]: its sections, then References when it has any.
List<DocTocEntry> docTocEntries(Doc doc) => [
  for (final (i, s) in doc.body.indexed)
    (
      number: DocStrings.sectionNo(i + 1),
      heading: s.heading.isEmpty ? s.goal : s.heading,
      status: s.status,
    ),
  if (doc.references.isNotEmpty)
    (number: '', heading: DocStrings.references, status: null),
];

/// The list itself, shared by the rail and the sheet.
class DocTocList extends StatelessWidget {
  const DocTocList({
    super.key,
    required this.entries,
    required this.current,
    required this.onJump,
    this.shrinkWrap = false,
  });

  final List<DocTocEntry> entries;
  final int current;
  final ValueChanged<int> onJump;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return ListView.builder(
      shrinkWrap: shrinkWrap,
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final active = i == current;
        return InkWell(
          onTap: () {
            Haptics.tap();
            onJump(i);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: DocSizes.tocRow),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: active ? p.accent : p.border,
                  width: active ? AppBorder.thick : AppBorder.thin,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: DocSizes.referenceIdWidth,
                  child: Text(
                    e.number,
                    style: t.caption.copyWith(
                      color: active ? p.accent : p.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    e.heading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall.copyWith(
                      color: active ? p.textPrimary : p.textSecondary,
                      fontWeight: active ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (e.status != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  DocStatusDot(status: e.status!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Wide screens: the TOC beside the text, always visible.
class DocTocRail extends StatelessWidget {
  const DocTocRail({
    super.key,
    required this.entries,
    required this.current,
    required this.onJump,
  });

  final List<DocTocEntry> entries;
  final int current;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DocSizes.railWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Text(DocStrings.contents, style: context.text.caption),
          ),
          Expanded(
            child: DocTocList(
              entries: entries,
              current: current,
              onJump: onJump,
            ),
          ),
        ],
      ),
    );
  }
}

/// Phones: a pinned pill "§3/8 Heading" that opens the TOC sheet.
class DocTocPill extends StatelessWidget {
  const DocTocPill({
    super.key,
    required this.entries,
    required this.current,
    required this.onTap,
  });

  final List<DocTocEntry> entries;
  final int current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    final t = context.text;
    final i = current.clamp(0, entries.length - 1);
    final e = entries[i];
    final sections = entries.where((x) => x.status != null).length;
    final label = e.status == null
        ? DocStrings.referencesLabel
        : DocStrings.sectionOf(i + 1, sections);
    return Semantics(
      button: true,
      label: DocStrings.tocOpen,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: DocSizes.pillMaxWidth),
          child: Glass(
            radius: AppRadius.pill,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SizedBox(
              height: DocSizes.pillHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    DocIcons.toc,
                    size: AppIconSize.sm,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label, style: t.caption.copyWith(color: p.accent)),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      e.status == null ? '' : e.heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall.copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The TOC as a bottom sheet; picking a line jumps there.
Future<void> showDocToc(
  BuildContext context, {
  required List<DocTocEntry> entries,
  required int current,
  required ValueChanged<int> onJump,
}) {
  return showM3Sheet<void>(
    context,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * DocSizes.tocSheetFactor,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.lg,
                AppSpacing.screenPadding,
                AppSpacing.sm,
              ),
              child: Text(DocStrings.contents, style: sheet.text.caption),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: DocTocList(
                  entries: entries,
                  current: current,
                  shrinkWrap: true,
                  onJump: (i) {
                    Navigator.pop(sheet);
                    onJump(i);
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    ),
  );
}
