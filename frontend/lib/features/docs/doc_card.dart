import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/doc_models.dart';
import 'doc_controller.dart';
import 'doc_progress.dart';
import 'doc_registry.dart';
import 'doc_screen.dart';
import 'doc_section_menu.dart';
import 'doc_text.dart';

/// The chat card for a reply that is a document (`meta.doc`): title,
/// status, one dot per section, word count and OPEN. Stays live through
/// [DocRegistry] while the doc is being written.
class DocCard extends StatefulWidget {
  const DocCard({super.key, required this.link, this.registry});

  final DocLink link;

  /// Defaults to [DocRegistry.instance] (tests pass their own).
  final DocRegistry? registry;

  @override
  State<DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<DocCard> {
  DocController? _live;

  DocRegistry get _registry => widget.registry ?? DocRegistry.instance;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(DocCard old) {
    super.didUpdateWidget(old);
    if (old.link.id != widget.link.id) _bind();
  }

  void _bind() {
    final link = widget.link;
    var live = _registry.peek(link.id);
    // Saved as running: it may still be (or have finished meanwhile).
    if (live == null && DocStatus.isRunning(link.status)) {
      live = _registry.watch(
        link.id,
        seed: Doc(id: link.id, title: link.title, status: link.status),
      );
    }
    _live = live;
  }

  void _open() {
    final link = widget.link;
    openDoc(
      context,
      link.id,
      seed: Doc(id: link.id, title: link.title, status: link.status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    if (live == null) return _card(context, widget.link);
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) => _card(
        context,
        live.loaded || live.doc.title.isNotEmpty
            ? DocLink.of(live.doc)
            : widget.link,
      ),
    );
  }

  Widget _card(BuildContext context, DocLink d) {
    final p = context.palette;
    final t = context.text;
    final running = DocStatus.isRunning(d.status);
    final bad =
        d.status == DocStatus.failed || d.status == DocStatus.interrupted;
    final done = d.sections.where((s) => s == DocSectionStatus.done).length;
    final total = d.sectionCount;
    final meta = [
      if (d.words > 0) DocStrings.words(d.words),
      if (total > 0) DocStrings.doneOf(done, total),
    ].join(DocStrings.sep);
    return Semantics(
      button: true,
      label: '${DocStrings.card} ${d.title}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          _open();
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: p.border, width: AppBorder.thin),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppIcon(
                    DocIcons.doc,
                    size: AppIconSize.sm,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(DocStrings.card, style: t.meta),
                  const Spacer(),
                  Text(
                    DocStrings.status(d.status),
                    style: t.meta.copyWith(
                      color: running || bad ? p.accent : p.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                d.title.trim().isEmpty ? DocStrings.untitled : d.title,
                maxLines: DocSizes.cardTitleLines,
                overflow: TextOverflow.ellipsis,
                style: t.title.copyWith(fontWeight: FontWeight.w600),
              ),
              if (d.sections.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: DocSizes.cardDotGap,
                  runSpacing: DocSizes.cardDotGap,
                  children: [
                    for (final s in d.sections)
                      DocStatusDot(status: s, size: DocSizes.cardDot),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.meta,
                    ),
                  ),
                  DocTextButton(
                    label: DocStrings.open,
                    icon: DocIcons.open,
                    filled: true,
                    onTap: _open,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
