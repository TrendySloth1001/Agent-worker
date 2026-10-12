import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../data/chat_api.dart';
import '../../data/doc_models.dart';
import '../chat/share/share_sheet.dart';
import 'doc_controller.dart';
import 'doc_diff.dart';
import 'doc_section_menu.dart';

// Edit one selected passage: pick EXPLAIN / SIMPLIFY / EXPAND / ADD
// CITATIONS / REWRITE, read a before/after preview, then ACCEPT (the
// section is saved as a new revision, with UNDO) or DISCARD.

/// Runs the whole flow for [quote] in [section].
Future<void> editDocPassage(
  BuildContext context,
  DocController controller,
  DocSection section,
  String quote,
) async {
  Haptics.tap();
  if (section.isWriting || controller.isRewriting(section.id)) {
    docToast(context, DocStrings.busy);
    return;
  }
  final op = await showShareSheet<DocSelectionOp>(
    context,
    title: DocStrings.editPassageTitle,
    options: const [
      (DocSelectionOp.explain, DocIcons.explain, DocStrings.opExplain),
      (DocSelectionOp.simplify, DocIcons.simplify, DocStrings.opSimplify),
      (DocSelectionOp.expand, DocIcons.expand, DocStrings.opExpand),
      (DocSelectionOp.cite, DocIcons.cite, DocStrings.opCite),
      (DocSelectionOp.rewrite, DocIcons.instruct, DocStrings.opRewrite),
    ],
  );
  if (op == null || !context.mounted) return;
  String? instruction;
  if (op == DocSelectionOp.rewrite) {
    instruction = await showDocTextPrompt(
      context,
      title: DocStrings.rewriteTitle,
      hint: DocStrings.rewriteHint,
      action: DocStrings.opRewrite.replaceAll('…', ''),
      quote: quote,
    );
    if (instruction == null || !context.mounted) return;
  }
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    builder: (sheet) => _Preview(
      controller: controller,
      section: section,
      op: op,
      quote: quote,
      instruction: instruction,
    ),
  );
  if (accepted != true || !context.mounted) return;
  final p = context.palette;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: p.surfaceHigh,
        content: Text(DocStrings.applied, style: context.text.label),
        action: SnackBarAction(
          label: DocStrings.undo,
          textColor: p.accent,
          onPressed: () async {
            final ok = await controller.undoEdit(section.id);
            if (ok) Haptics.received();
          },
        ),
      ),
    );
}

class _Preview extends StatefulWidget {
  const _Preview({
    required this.controller,
    required this.section,
    required this.op,
    required this.quote,
    this.instruction,
  });

  final DocController controller;
  final DocSection section;
  final DocSelectionOp op;
  final String quote;
  final String? instruction;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  DocSelectionEdit? _edit;
  String? _error;
  bool _saving = false;
  List<DocDiffPiece>? _diff;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _edit = null;
      _error = null;
    });
    try {
      final e = await widget.controller.previewSelection(
        widget.section.id,
        widget.op,
        widget.quote,
        instruction: widget.instruction,
      );
      if (!mounted) return;
      setState(() {
        _edit = e;
        _diff = e.isInsert ? null : docWordDiff(e.original, e.replacement);
      });
    } catch (e) {
      if (!mounted) return;
      Haptics.error();
      setState(
        () => _error = e is ApiException && e.status == 422
            ? e.message
            : (e is ApiException ? e.message : DocStrings.previewFailed),
      );
    }
  }

  Future<void> _accept() async {
    final e = _edit;
    if (e == null || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.controller.applyEdit(widget.section.id, e);
    if (!mounted) return;
    if (ok) {
      Haptics.received();
      Navigator.pop(context, true);
    } else {
      Haptics.error();
      setState(() {
        _saving = false;
        _error = DocStrings.actionFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final edit = _edit;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * DocSizes.previewSheetFactor,
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
              child: Text(
                '${DocStrings.previewTitle} · '
                '${DocStrings.opLabel(widget.op.name)}',
                style: t.caption,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                children: [
                  if (_error != null)
                    Text(_error!, style: t.bodySmall.copyWith(color: p.accent))
                  else if (edit == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xl,
                      ),
                      child: Center(
                        child: Text(
                          DocStrings.working,
                          style: t.caption.copyWith(color: p.accent),
                        ),
                      ),
                    )
                  else if (edit.isInsert) ...[
                    _Block(
                      label: DocStrings.previewAdded,
                      child: _plain(context, edit.replacement, added: true),
                    ),
                  ] else ...[
                    _Block(
                      label: DocStrings.previewBefore,
                      child: _diff == null
                          ? _plain(context, edit.original)
                          : _spans(context, removed: true),
                    ),
                    _Block(
                      label: DocStrings.previewAfter,
                      child: _diff == null
                          ? _plain(context, edit.replacement, added: true)
                          : _spans(context, removed: false),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DocTextButton(
                    label: DocStrings.discard,
                    onTap: _saving ? null : () => Navigator.pop(context, false),
                  ),
                  if (_error != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    DocTextButton(
                      label: DocStrings.retry,
                      filled: true,
                      onTap: _load,
                    ),
                  ] else ...[
                    const SizedBox(width: AppSpacing.sm),
                    DocTextButton(
                      label: DocStrings.accept,
                      icon: DocIcons.accept,
                      filled: true,
                      onTap: edit == null || _saving ? null : _accept,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _plain(BuildContext context, String text, {bool added = false}) =>
      Text(
        text,
        maxLines: DocSizes.previewTextLines,
        overflow: TextOverflow.ellipsis,
        style: context.text.body.copyWith(
          color: added ? context.palette.textPrimary : null,
        ),
      );

  /// Words kept as is, removed ones struck (before) or added ones marked
  /// (after).
  Widget _spans(BuildContext context, {required bool removed}) {
    final p = context.palette;
    final base = context.text.body;
    return Text.rich(
      TextSpan(
        children: [
          for (final (kind, text) in _diff!)
            if (kind == DocDiffKind.same)
              TextSpan(text: text)
            else if (removed && kind == DocDiffKind.removed)
              TextSpan(
                text: text,
                style: TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: p.textTertiary,
                ),
              )
            else if (!removed && kind == DocDiffKind.added)
              TextSpan(
                text: text,
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
              ),
        ],
      ),
      style: base,
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: context.text.caption),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}
