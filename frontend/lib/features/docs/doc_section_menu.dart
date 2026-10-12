import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/doc_models.dart';
import '../chat/share/share_sheet.dart';
import 'doc_controller.dart';
import 'doc_text.dart';

enum _SectionAction {
  regenerate,
  regenerateWith,
  addBelow,
  expand,
  shorten,
  simplify,
  instruct,
  edit,
  versions,
}

/// Short message at the bottom of the screen.
void docToast(BuildContext context, String text) {
  final p = context.palette;
  final t = context.text;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: p.surfaceHigh,
        content: Text(text, style: t.meta),
      ),
    );
}

/// The ⋯ menu by a section heading.
Future<void> showDocSectionMenu(
  BuildContext context,
  DocController controller,
  DocSection section,
) async {
  Haptics.tap();
  if (section.isWriting || controller.isRewriting(section.id)) {
    docToast(context, DocStrings.busy);
    return;
  }
  final action = await showShareSheet<_SectionAction>(
    context,
    title: '${DocStrings.menuTitle} ${section.heading}',
    options: const [
      (_SectionAction.regenerate, DocIcons.regenerate, DocStrings.regenerate),
      (
        _SectionAction.regenerateWith,
        DocIcons.regenerate,
        DocStrings.regenerateWith,
      ),
      (_SectionAction.expand, DocIcons.expand, DocStrings.expand),
      (_SectionAction.shorten, DocIcons.shorten, DocStrings.shorten),
      (_SectionAction.simplify, DocIcons.simplify, DocStrings.simplify),
      (_SectionAction.instruct, DocIcons.instruct, DocStrings.instruct),
      (_SectionAction.edit, DocIcons.edit, DocStrings.edit),
      (_SectionAction.addBelow, DocIcons.add, DocStrings.addBelow),
      (_SectionAction.versions, DocIcons.versions, DocStrings.versions),
    ],
  );
  if (action == null || !context.mounted) return;
  Future<void> rewrite(DocRewriteOp op, {String? instruction}) async {
    final ok = await controller.rewrite(
      section.id,
      op,
      instruction: instruction,
    );
    if (!ok && context.mounted) docToast(context, DocStrings.actionFailed);
  }

  switch (action) {
    case _SectionAction.regenerate:
      await rewrite(DocRewriteOp.regenerate);
    case _SectionAction.regenerateWith:
      final text = await showDocTextPrompt(
        context,
        title: DocStrings.regenerateTitle,
        hint: DocStrings.regenerateHint,
        action: DocStrings.regenerate,
      );
      if (text != null) {
        await rewrite(DocRewriteOp.regenerate, instruction: text);
      }
    case _SectionAction.addBelow:
      final input = await showDocAddSection(context);
      if (input == null || !context.mounted) return;
      final ok = await controller.addSection(
        after: section.id,
        heading: input.$1,
        goal: input.$2,
      );
      if (!ok && context.mounted) {
        docToast(context, controller.lastError ?? DocStrings.addFailed);
      }
    case _SectionAction.expand:
      await rewrite(DocRewriteOp.expand);
    case _SectionAction.shorten:
      await rewrite(DocRewriteOp.shorten);
    case _SectionAction.simplify:
      await rewrite(DocRewriteOp.simplify);
    case _SectionAction.instruct:
      final text = await showDocTextPrompt(
        context,
        title: DocStrings.instructTitle,
        hint: DocStrings.instructHint,
        action: DocStrings.apply,
      );
      if (text != null) await rewrite(DocRewriteOp.custom, instruction: text);
    case _SectionAction.edit:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              DocSectionEditor(controller: controller, section: section),
        ),
      );
    case _SectionAction.versions:
      await showDocVersions(context, controller, section);
  }
}

/// A sheet with one text field; returns the text, or null when cancelled.
Future<String?> showDocTextPrompt(
  BuildContext context, {
  required String title,
  required String hint,
  required String action,
  String? quote,
  bool allowEmpty = false,
}) {
  return showM3Sheet<String>(
    context,
    builder: (sheet) => _TextPrompt(
      title: title,
      hint: hint,
      action: action,
      quote: quote,
      allowEmpty: allowEmpty,
    ),
  );
}

/// Heading and optional goal for a new section; null when cancelled.
Future<(String, String)?> showDocAddSection(BuildContext context) {
  return showM3Sheet<(String, String)>(
    context,
    builder: (sheet) => const _AddSection(),
  );
}

class _AddSection extends StatefulWidget {
  const _AddSection();

  @override
  State<_AddSection> createState() => _AddSectionState();
}

class _AddSectionState extends State<_AddSection> {
  final _heading = TextEditingController();
  final _goal = TextEditingController();

  @override
  void dispose() {
    _heading.dispose();
    _goal.dispose();
    super.dispose();
  }

  void _submit() {
    final h = _heading.text.trim();
    if (h.isEmpty) return;
    Haptics.tap();
    Navigator.pop(context, (h, _goal.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(DocStrings.addSectionTitle, style: t.meta),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _heading,
                autofocus: true,
                style: t.body,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: DocStrings.addHeadingHint,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _goal,
                minLines: 1,
                maxLines: DocSizes.instructMaxLines,
                style: t.body,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: DocStrings.addGoalHint,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DocTextButton(
                    label: DocStrings.cancel,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ListenableBuilder(
                    listenable: _heading,
                    builder: (context, _) => DocTextButton(
                      label: DocStrings.addAction,
                      filled: true,
                      onTap: _heading.text.trim().isEmpty ? null : _submit,
                    ),
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

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.hint,
    required this.action,
    this.quote,
    this.allowEmpty = false,
  });

  final String title, hint, action;
  final String? quote;
  final bool allowEmpty;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _text.text.trim();
    if (v.isEmpty && !widget.allowEmpty) return;
    Haptics.tap();
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: t.meta),
              if (widget.quote != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.only(left: AppSpacing.md),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: p.accent, width: AppBorder.thick),
                    ),
                  ),
                  child: Text(
                    widget.quote!,
                    maxLines: DocSizes.notePreviewLines,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 1,
                maxLines: DocSizes.instructMaxLines,
                style: t.body,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: widget.hint),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DocTextButton(
                    label: DocStrings.cancel,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ListenableBuilder(
                    listenable: _text,
                    builder: (context, _) => DocTextButton(
                      label: widget.action,
                      filled: true,
                      onTap: _text.text.trim().isEmpty && !widget.allowEmpty
                          ? null
                          : _submit,
                    ),
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

/// Pill button (tonal, or solid when [filled]); [filled] for the main action, null [onTap]
/// greys it out.
class DocTextButton extends StatelessWidget {
  const DocTextButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.icon,
    this.accent = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool accent;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    final fill = accent ? p.accent : p.textPrimary;
    final fg = filled
        ? p.textInverse
        : (enabled ? (accent ? p.accent : p.textPrimary) : p.textTertiary);
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                Haptics.tap();
                onTap!();
              }
            : null,
        child: Container(
          height: DocSizes.cardButtonHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: filled
                ? (enabled ? fill : p.surfaceHigh)
                : (accent
                      ? p.accent.withValues(alpha: M3Sizes.tagAlpha)
                      : Theme.of(context).colorScheme.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                AppIcon(icon!, size: AppIconSize.sm, color: fg),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: context.text.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: filled && !enabled ? p.textTertiary : fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen markdown editor for one section (like the message editor).
class DocSectionEditor extends StatefulWidget {
  const DocSectionEditor({
    super.key,
    required this.controller,
    required this.section,
  });

  final DocController controller;
  final DocSection section;

  @override
  State<DocSectionEditor> createState() => _DocSectionEditorState();
}

class _DocSectionEditorState extends State<DocSectionEditor> {
  late final _text = TextEditingController(text: widget.section.markdown);
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await widget.controller.saveSection(
      widget.section.id,
      _text.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Haptics.received();
      docToast(context, DocStrings.saved);
      Navigator.pop(context);
    } else {
      Haptics.error();
      docToast(context, DocStrings.actionFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DocSizes.maxWidth),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${DocStrings.editTitle} · '
                          '${widget.section.heading}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.meta,
                        ),
                      ),
                      DocTextButton(
                        label: DocStrings.cancel,
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      DocTextButton(
                        label: DocStrings.save,
                        filled: true,
                        onTap: _saving ? null : _save,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: p.borderStrong,
                          width: AppBorder.thin,
                        ),
                      ),
                      child: TextField(
                        controller: _text,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: t.code.copyWith(color: p.textPrimary),
                        decoration: const InputDecoration(
                          hintText: DocStrings.editHint,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
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

/// Saved versions of a section; RESTORE puts one back.
Future<void> showDocVersions(
  BuildContext context,
  DocController controller,
  DocSection section,
) {
  return showM3Sheet<void>(
    context,
    builder: (sheet) => _Versions(controller: controller, section: section),
  );
}

class _Versions extends StatefulWidget {
  const _Versions({required this.controller, required this.section});

  final DocController controller;
  final DocSection section;

  @override
  State<_Versions> createState() => _VersionsState();
}

class _VersionsState extends State<_Versions> {
  late final _load = widget.controller.versions(widget.section.id);

  Future<void> _restore(DocRevision r) async {
    final ok = await widget.controller.saveSection(
      widget.section.id,
      r.markdown,
    );
    if (!mounted) return;
    if (ok) {
      Haptics.received();
      docToast(context, DocStrings.restored);
      Navigator.pop(context);
    } else {
      Haptics.error();
      docToast(context, DocStrings.actionFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * DocSizes.tocSheetFactor,
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
                '${DocStrings.versions} · '
                '${widget.section.heading}',
                style: t.meta,
              ),
            ),
            Flexible(
              child: FutureBuilder<List<DocRevision>>(
                future: _load,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: AppBorder.thick,
                        ),
                      ),
                    );
                  }
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.screenPadding),
                      child: Text(
                        snap.hasError
                            ? DocStrings.actionFailed
                            : DocStrings.noVersions,
                        style: t.bodySmall,
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final r = list[i];
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.screenPadding),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: p.border)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    DocStrings.version(
                                      r.version,
                                      r.reason,
                                      r.createdAt,
                                    ),
                                    style: t.meta,
                                  ),
                                ),
                                DocTextButton(
                                  label: DocStrings.restore,
                                  icon: DocIcons.restore,
                                  onTap: () => _restore(r),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              r.markdown.trim(),
                              maxLines: DocSizes.versionPreviewLines,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
