import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/doc_models.dart';
import '../chat/widgets/markdown/app_markdown.dart';
import 'doc_controller.dart';
import 'doc_section_menu.dart';
import 'doc_text.dart';

// ASK AI on a selection: an answer card under the section, a persistent
// thread sheet per passage, and the notes panel listing every highlight,
// note and question in the document.

/// Opens the Q&A thread of the passage [quote] in [section]. With
/// [question] the question is sent at once (the sheet shows THINKING);
/// with [highlight] earlier questions about the same passage are shown and
/// the new one joins them.
Future<void> showDocAskSheet(
  BuildContext context,
  DocController controller,
  DocSection section, {
  required String quote,
  DocHighlight? highlight,
  String? question,
}) {
  return showM3Sheet<void>(
    context,
    builder: (sheet) => _AskSheet(
      controller: controller,
      section: section,
      quote: quote,
      highlight: highlight,
      question: question,
    ),
  );
}

class _AskSheet extends StatefulWidget {
  const _AskSheet({
    required this.controller,
    required this.section,
    required this.quote,
    this.highlight,
    this.question,
  });

  final DocController controller;
  final DocSection section;
  final String quote;
  final DocHighlight? highlight;
  final String? question;

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  DocHighlight? _h;
  String? _asking;
  String? _failed;
  String? _error;

  DocController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _h = widget.highlight;
    _c.addListener(_sync);
    final q = widget.question;
    if (q != null) _send(q);
  }

  @override
  void dispose() {
    _c.removeListener(_sync);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Follows the controller's copy of the highlight (a local placeholder
  /// becomes the saved one when the first answer lands).
  void _sync() {
    final h = _h;
    if (h == null || !mounted) return;
    DocHighlight? next;
    for (final x in _c.highlights) {
      if (identical(x, h) ||
          (h.id.isNotEmpty && x.id == h.id) ||
          (h.id.isEmpty &&
              x.id.isNotEmpty &&
              x.sectionId == h.sectionId &&
              x.quote == h.quote &&
              x.color == DocConfig.askColor)) {
        next = x;
        break;
      }
    }
    if (next == null) {
      // Removed elsewhere.
      if (_asking == null && _c.pendingQuestion(h) == null) {
        Navigator.maybePop(context);
      }
      return;
    }
    setState(() => _h = next);
  }

  Future<void> _send(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || _asking != null) return;
    setState(() {
      _asking = q;
      _failed = null;
      _error = null;
    });
    _input.clear();
    _toBottom();
    final saved = await _c.ask(widget.section, widget.quote, q, on: _h);
    if (!mounted) return;
    setState(() {
      _asking = null;
      if (saved != null) {
        _h = saved;
      } else {
        _failed = q;
        _error = _c.lastError ?? DocStrings.askFailed;
      }
    });
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppDurations.normal,
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final thread = _h?.thread ?? const <DocQa>[];
    final pendingQ = _asking ?? (_h == null ? null : _c.pendingQuestion(_h!));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height * DocSizes.askSheetFactor,
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${DocStrings.qaThread} · '
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
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                  ),
                  children: [
                    _QuoteBar(quote: widget.quote),
                    for (final qa in thread)
                      _Exchange(
                        controller: _c,
                        section: widget.section,
                        question: qa.question,
                        answer: qa.answer,
                      ),
                    if (pendingQ != null)
                      _Exchange(
                        controller: _c,
                        section: widget.section,
                        question: pendingQ,
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _error!,
                                style: t.meta.copyWith(color: p.accent),
                              ),
                            ),
                            if (_failed != null)
                              DocTextButton(
                                label: DocStrings.retry,
                                icon: DocIcons.regenerate,
                                onTap: () => _send(_failed!),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: DocSizes.askInputMaxLines,
                        style: t.body,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(
                          hintText: DocStrings.followUpHint,
                        ),
                        onSubmitted: _send,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ListenableBuilder(
                      listenable: _input,
                      builder: (context, _) => DocTextButton(
                        label: DocStrings.askSend,
                        filled: true,
                        onTap: _asking != null || _input.text.trim().isEmpty
                            ? null
                            : () => _send(_input.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteBar extends StatelessWidget {
  const _QuoteBar({required this.quote});

  final String quote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: p.accent, width: AppBorder.thick),
        ),
      ),
      child: Text(
        quote,
        maxLines: DocSizes.notePreviewLines,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodySmall.copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}

/// One question and its answer (THINKING while [answer] is null).
class _Exchange extends StatelessWidget {
  const _Exchange({
    required this.controller,
    required this.section,
    required this.question,
    this.answer,
  });

  final DocController controller;
  final DocSection section;
  final String question;
  final String? answer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(DocStrings.youAsked, style: t.meta),
          const SizedBox(height: AppSpacing.xxs),
          Text(question, style: t.body.copyWith(color: p.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                answer == null ? DocStrings.thinking : DocStrings.answerLabel,
                style: t.meta.copyWith(color: p.accent),
              ),
              const Spacer(),
              if (answer != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: answer!));
                    Haptics.received();
                    if (context.mounted) {
                      docToast(context, DocStrings.copiedAnswer);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Text(DocStrings.copyAnswer, style: t.meta),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (answer == null)
            const _Dots()
          else
            AppMarkdown(
              data: answer!,
              citations: controller.doc.sources,
              evidence: section.evidence,
              streaming: false,
            ),
        ],
      ),
    );
  }
}

/// Three pulsing dots while an answer is being written.
class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: DocSizes.pulse)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: DocSizes.pulseMin, end: 1.0).animate(_anim),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Container(
              width: DocSizes.statusDot,
              height: DocSizes.statusDot,
              decoration: BoxDecoration(
                color: context.palette.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Answer cards under a section: one per asked-about passage, showing the
/// latest question and answer; tap opens the whole thread.
class DocQaCards extends StatelessWidget {
  const DocQaCards({
    super.key,
    required this.controller,
    required this.section,
    required this.highlights,
  });

  final DocController controller;
  final DocSection section;
  final List<DocHighlight> highlights;

  @override
  Widget build(BuildContext context) {
    final asked = [
      for (final h in highlights)
        if (h.hasThread || controller.pendingQuestion(h) != null) h,
    ];
    if (asked.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final h in asked)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _QaCard(
                controller: controller,
                section: section,
                highlight: h,
              ),
            ),
        ],
      ),
    );
  }
}

class _QaCard extends StatelessWidget {
  const _QaCard({
    required this.controller,
    required this.section,
    required this.highlight,
  });

  final DocController controller;
  final DocSection section;
  final DocHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final h = highlight;
    final pending = controller.pendingQuestion(h);
    final last = h.hasThread ? h.thread.last : null;
    final question = pending ?? last?.question ?? '';
    return Semantics(
      button: true,
      label: DocStrings.openThread,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          showDocAskSheet(
            context,
            controller,
            section,
            quote: h.quote,
            highlight: h,
          );
        },
        // A rounded tonal card with an accent bar on the left. The bar is a
        // one-sided border, so the radius comes from the clip (Flutter only
        // allows a borderRadius on uniform borders).
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SettingsSizes.groupOuterRadius),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              border: Border(
                left: BorderSide(color: p.accent, width: DocSizes.qaBar),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AppIcon(
                      DocIcons.qa,
                      size: AppIconSize.sm,
                      color: p.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        h.thread.length > 1
                            ? '${DocStrings.qaThread} · '
                                  '${DocStrings.qaCount(h.thread.length)}'
                            : DocStrings.qaThread,
                        style: t.meta,
                      ),
                    ),
                    AppIcon(
                      DocIcons.open,
                      size: AppIconSize.sm,
                      color: p.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '“${h.quote}”',
                  maxLines: DocSizes.qaQuoteLines,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall.copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(question, style: t.meta.copyWith(color: p.textPrimary)),
                const SizedBox(height: AppSpacing.xs),
                if (pending != null)
                  Text(
                    DocStrings.thinking,
                    style: t.meta.copyWith(color: p.accent),
                  )
                else if (last != null)
                  AppMarkdown(
                    data: last.answer,
                    citations: controller.doc.sources,
                    evidence: section.evidence,
                    streaming: false,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Notes panel -------------------------------------------------------------------

/// Every highlight, note and question of the document; tap one to jump to
/// its section (questions open their thread), DELETE removes it.
Future<void> showDocNotes(
  BuildContext context,
  DocController controller, {
  required void Function(String sectionId) onJump,
}) {
  Haptics.tap();
  return showM3Sheet<void>(
    context,
    builder: (sheet) => _Notes(controller: controller, onJump: onJump),
  );
}

class _Notes extends StatelessWidget {
  const _Notes({required this.controller, required this.onJump});

  final DocController controller;
  final void Function(String sectionId) onJump;

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
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final all = controller.allHighlights;
            return Column(
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
                  child: Text(DocStrings.notesTitle, style: t.meta),
                ),
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    child: Text(DocStrings.notesEmpty, style: t.bodySmall),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: all.length,
                      itemBuilder: (context, i) {
                        final h = all[i];
                        final section = controller.doc.section(h.sectionId);
                        return _NoteRow(
                          controller: controller,
                          highlight: h,
                          number: section == null
                              ? 0
                              : controller.doc.body.indexOf(section) + 1,
                          heading: section?.heading ?? '',
                          border: p.border,
                          onOpen: () {
                            Navigator.pop(context);
                            if (h.hasThread && section != null) {
                              showDocAskSheet(
                                context,
                                controller,
                                section,
                                quote: h.quote,
                                highlight: h,
                              );
                            } else {
                              onJump(h.sectionId);
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.controller,
    required this.highlight,
    required this.number,
    required this.heading,
    required this.border,
    required this.onOpen,
  });

  final DocController controller;
  final DocHighlight highlight;
  final int number;
  final String heading;
  final Color border;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final h = highlight;
    final kind = h.hasThread
        ? DocStrings.notesQuestions
        : h.hasNote
        ? DocStrings.notesNotes
        : DocStrings.notesHighlights;
    final last = h.hasThread ? h.thread.last : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onOpen();
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$kind · ${DocStrings.sectionNo(number)} $heading',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.meta.copyWith(
                      color: h.hasThread ? p.accent : p.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '“${h.quote}”',
                    maxLines: DocSizes.noteRowQuoteLines,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall.copyWith(fontStyle: FontStyle.italic),
                  ),
                  if (h.hasNote) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      h.note!,
                      maxLines: DocSizes.noteRowAnswerLines,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall.copyWith(color: p.textPrimary),
                    ),
                  ],
                  if (last != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      last.question,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.meta.copyWith(color: p.textPrimary),
                    ),
                    Text(
                      last.answer,
                      maxLines: DocSizes.noteRowAnswerLines,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.tap();
                controller.removeHighlight(h);
              },
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: AppIcon(
                  DocIcons.close,
                  size: AppIconSize.sm,
                  color: p.textTertiary,
                  semanticLabel: DocStrings.delete,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
