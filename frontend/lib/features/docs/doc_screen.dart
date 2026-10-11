import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/docs.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/dot_meter.dart';
import '../../data/chat_event.dart';
import '../../data/doc_models.dart';
import '../chat/share/share_sheet.dart';
import '../chat/widgets/markdown/app_markdown.dart';
import '../chat/widgets/markdown/evidence_sheet.dart';
import '../chat/widgets/open_url.dart';
import 'doc_controller.dart';
import 'doc_export.dart';
import 'doc_highlights.dart';
import 'doc_progress.dart';
import 'doc_registry.dart';
import 'doc_section_menu.dart';
import 'doc_toc.dart';

/// Opens the reader for doc [id] (live while it is being written).
Future<void> openDoc(BuildContext context, String id, {Doc? seed}) {
  Haptics.tap();
  final controller = DocRegistry.instance.watch(id, seed: seed);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DocScreen(controller: controller)),
  );
}

/// Full-page reader: header, live progress, one markdown block per section
/// (only the writing one streams), References, and a TOC (rail on wide
/// screens, pinned pill on phones).
class DocScreen extends StatefulWidget {
  const DocScreen({super.key, required this.controller});

  final DocController controller;

  @override
  State<DocScreen> createState() => _DocScreenState();
}

class _DocScreenState extends State<DocScreen> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  final _current = ValueNotifier(0);
  static const _refsKey = '\u0000references';

  DocController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.attach();
    _c.loadHighlights();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    // A running doc stays attached so the chat card keeps updating.
    if (!_c.doc.isRunning) _c.detach();
    _scroll.dispose();
    _current.dispose();
    super.dispose();
  }

  GlobalKey _key(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// TOC entry ids in order: sections, then References.
  List<String> _entryIds(Doc doc) => [
    for (final s in doc.body) s.id,
    if (doc.references.isNotEmpty) _refsKey,
  ];

  bool _measureQueued = false;

  /// Positions are only current after the frame the scroll triggers, so
  /// the current section is measured then (once per frame).
  void _onScroll() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    final ids = _entryIds(_c.doc);
    final view = context.findRenderObject() as RenderBox?;
    if (view == null || ids.isEmpty) return;
    final line =
        view.localToGlobal(Offset.zero).dy +
        view.size.height * DocSizes.currentLine;
    var current = 0;
    for (final (i, id) in ids.indexed) {
      final box = _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= line) current = i;
    }
    _current.value = current;
  }

  Future<void> _jump(int index) async {
    final ids = _entryIds(_c.doc);
    if (index < 0 || index >= ids.length) return;
    final target = _keys[ids[index]]?.currentContext;
    if (target == null) return;
    _current.value = index;
    await Scrollable.ensureVisible(
      target,
      duration: AppDurations.slow,
      curve: Curves.easeOutCubic,
    );
  }

  void _openToc() => showDocToc(
    context,
    entries: docTocEntries(_c.doc),
    current: _current.value,
    onJump: _jump,
  );

  /// Body text tuned for long reading; everything else as in chat.
  ThemeData _readingTheme(ThemeData base) {
    final t = base.extension<AppTextTheme>()!;
    final reading = AppTextTheme(
      display: t.display,
      headline: t.headline,
      metric: t.metric,
      title: t.title,
      body: t.body.copyWith(
        fontSize: DocSizes.body,
        height: DocSizes.bodyHeight,
      ),
      bodySmall: t.bodySmall.copyWith(fontSize: DocSizes.bodySmall),
      label: t.label,
      caption: t.caption,
      button: t.button,
      code: t.code,
    );
    return base.copyWith(
      extensions: [
        for (final e in base.extensions.values)
          if (e is! AppTextTheme) e,
        reading,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reading = _readingTheme(Theme.of(context));
    return AnnotatedRegion(
      value: systemOverlayFor(context),
      child: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: _c,
            builder: (context, _) => LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= DocSizes.wideBreakpoint;
                final entries = docTocEntries(_c.doc);
                final reader = _reader(context, reading, wide);
                return Column(
                  children: [
                    _TopBar(
                      title: _c.doc.title,
                      onBack: () => Navigator.maybePop(context),
                      onExport: _c.loaded && _c.doc.body.isNotEmpty
                          ? () => exportDoc(context, _c.doc)
                          : null,
                      onToc: wide || entries.isEmpty ? null : _openToc,
                    ),
                    Expanded(
                      child: wide
                          ? Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth:
                                      DocSizes.maxWidth +
                                      DocSizes.railWidth +
                                      DocSizes.railGap,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: DocSizes.headerTop,
                                      ),
                                      child: ValueListenableBuilder(
                                        valueListenable: _current,
                                        builder: (context, current, _) =>
                                            DocTocRail(
                                              entries: entries,
                                              current: current,
                                              onJump: _jump,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: DocSizes.railGap),
                                    Expanded(child: reader),
                                  ],
                                ),
                              ),
                            )
                          : Stack(
                              children: [
                                Positioned.fill(child: reader),
                                Positioned(
                                  left: AppSpacing.screenPadding,
                                  right: AppSpacing.screenPadding,
                                  bottom:
                                      MediaQuery.paddingOf(context).bottom +
                                      AppSpacing.md,
                                  child: Center(
                                    child: ValueListenableBuilder(
                                      valueListenable: _current,
                                      builder: (context, current, _) =>
                                          DocTocPill(
                                            entries: entries,
                                            current: current,
                                            onTap: _openToc,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _column(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: DocSizes.maxWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: child,
      ),
    ),
  );

  Widget _reader(BuildContext context, ThemeData reading, bool wide) {
    final doc = _c.doc;
    final body = doc.body;
    final refs = doc.references;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: _column(_Header(controller: _c))),
        if (showsDocProgress(doc) && _c.loaded)
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedProgress(
              child: _column(DocProgressBar(controller: _c)),
            ),
          ),
        if (!_c.loaded && body.isEmpty)
          SliverToBoxAdapter(
            child: _column(
              _c.loadError != null
                  ? _LoadError(message: _c.loadError!, onRetry: _c.refresh)
                  : const _SectionSkeleton(goal: '', writing: true),
            ),
          ),
        for (final (i, s) in body.indexed)
          SliverToBoxAdapter(
            child: _column(
              KeyedSubtree(
                key: _key(s.id),
                child: Padding(
                  padding: const EdgeInsets.only(top: DocSizes.sectionGap),
                  child: DocSectionView(
                    controller: _c,
                    section: s,
                    number: i + 1,
                    reading: reading,
                  ),
                ),
              ),
            ),
          ),
        if (refs.isNotEmpty)
          SliverToBoxAdapter(
            child: _column(
              KeyedSubtree(
                key: _key(_refsKey),
                child: Padding(
                  padding: const EdgeInsets.only(top: DocSizes.sectionGap),
                  child: DocReferences(
                    references: refs,
                    evidence: doc.evidence,
                  ),
                ),
              ),
            ),
          ),
        if (doc.glossary.isNotEmpty)
          SliverToBoxAdapter(
            child: _column(
              Padding(
                padding: const EdgeInsets.only(top: DocSizes.sectionGap),
                child: _Glossary(terms: doc.glossary),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: DocSizes.bottomClear + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }
}

class _PinnedProgress extends SliverPersistentHeaderDelegate {
  _PinnedProgress({required this.child});

  final Widget child;

  @override
  double get minExtent => DocSizes.progressExtent;

  @override
  double get maxExtent => DocSizes.progressExtent;

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) =>
      ColoredBox(
        color: context.palette.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: child,
        ),
      );

  @override
  bool shouldRebuild(_PinnedProgress old) => old.child != child;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onBack,
    this.onExport,
    this.onToc,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onExport;
  final VoidCallback? onToc;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget icon(AppIconData data, String label, VoidCallback? onTap) =>
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    Haptics.tap();
                    onTap();
                  },
            child: SizedBox.square(
              dimension: DocSizes.topBar,
              child: AppIcon(
                data,
                size: AppIconSize.lg,
                color: onTap == null ? p.textTertiary : p.textPrimary,
              ),
            ),
          ),
        );
    return Container(
      height: DocSizes.topBar,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          icon(DocIcons.back, AppStrings.back, onBack),
          Expanded(
            child: Text(
              (title.isEmpty ? DocStrings.card : title).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.caption.copyWith(color: p.textSecondary),
            ),
          ),
          if (onToc != null) icon(DocIcons.toc, DocStrings.tocOpen, onToc),
          icon(DocIcons.export, DocStrings.export, onExport),
        ],
      ),
    );
  }
}

/// Title, subtitle, the mono meta line and the abstract.
class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final DocController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final doc = controller.doc;
    final hasTitle = doc.title.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: DocSizes.headerTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DocStatusDot(
                status: doc.isRunning
                    ? DocSectionStatus.writing
                    : DocSectionStatus.done,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(DocStrings.card, style: t.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasTitle)
            Text(
              doc.title,
              style: t.headline.copyWith(
                fontSize: DocSizes.title,
                height: DocSizes.titleHeight,
              ),
            )
          else
            const _Bars(widths: [0.8, 0.5], height: DocSizes.title * 0.8),
          if (doc.subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              doc.subtitle,
              style: t.body.copyWith(
                fontSize: DocSizes.subtitle,
                height: DocSizes.subtitleHeight,
                color: p.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            DocStrings.meta(
              words: doc.wordCount,
              sources: doc.references.isNotEmpty
                  ? doc.references.length
                  : doc.sources.length,
              status: doc.status,
            ),
            style: t.caption,
          ),
          if (doc.notice != null || doc.error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              doc.error ?? doc.notice!,
              style: t.caption.copyWith(
                color: doc.error != null ? p.accent : p.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Divider(height: AppBorder.thin, color: p.border),
          if (doc.summary.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(DocStrings.abstractLabel, style: t.caption),
            const SizedBox(height: AppSpacing.sm),
            Text(
              doc.summary.trim(),
              style: t.body.copyWith(
                fontSize: DocSizes.abstractSize,
                height: DocSizes.bodyHeight,
                color: p.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

/// One section: §n, heading, ⋯ menu, then a skeleton, the streaming text
/// or the finished text. Rebuilds on its own section's tick only; the
/// rendered markdown is reused while nothing it shows has changed.
class DocSectionView extends StatefulWidget {
  const DocSectionView({
    super.key,
    required this.controller,
    required this.section,
    required this.number,
    required this.reading,
  });

  final DocController controller;
  final DocSection section;
  final int number;
  final ThemeData reading;

  @override
  State<DocSectionView> createState() => _DocSectionViewState();
}

class _DocSectionViewState extends State<DocSectionView> {
  Widget? _body;
  Object? _bodyKey;

  DocController get _c => widget.controller;
  DocSection get _s => widget.section;

  Future<void> _onSelection(DocSelectionAction action, String quote) async {
    if (quote.isEmpty) return;
    switch (action) {
      case DocSelectionAction.highlight:
        final ok = await _c.addHighlight(anchorHighlight(_s, quote));
        if (!ok && mounted) docToast(context, DocStrings.highlightFailed);
      case DocSelectionAction.note:
        final note = await showDocTextPrompt(
          context,
          title: DocStrings.noteTitle,
          hint: DocStrings.noteHint,
          action: DocStrings.save,
          quote: quote,
        );
        if (note == null) return;
        final ok = await _c.addHighlight(
          anchorHighlight(_s, quote, note: note),
        );
        if (!ok && mounted) docToast(context, DocStrings.highlightFailed);
      case DocSelectionAction.ask:
        final ask = await showDocTextPrompt(
          context,
          title: DocStrings.askTitle,
          hint: DocStrings.askHint,
          action: DocStrings.apply,
          quote: quote,
        );
        if (ask == null) return;
        final ok = await _c.rewrite(
          _s.id,
          DocRewriteOp.custom,
          instruction: ask,
          selection: quote,
        );
        if (!ok && mounted) docToast(context, DocStrings.actionFailed);
      case DocSelectionAction.copyCite:
        await Clipboard.setData(
          ClipboardData(
            text: DocStrings.citeQuote(
              quote: quote,
              title: _c.doc.title,
              section: widget.number,
              heading: _s.heading,
              app: AppStrings.appName,
            ),
          ),
        );
        Haptics.received();
        if (mounted) docToast(context, DocStrings.copiedCite);
    }
  }

  Future<void> _manageHighlights(List<DocHighlight> list) async {
    Haptics.tap();
    String clip(String s) => s.length <= DocSizes.quotePreviewChars
        ? s
        : '${s.substring(0, DocSizes.quotePreviewChars - 1)}…';
    final pick = await showShareSheet<DocHighlight>(
      context,
      title: DocStrings.highlightsRemove,
      options: [for (final h in list) (h, DocIcons.highlight, clip(h.quote))],
    );
    if (pick != null) await _c.removeHighlight(pick);
  }

  /// The section text, rebuilt only when what it shows changed.
  Widget _markdown(List<DocHighlight> highlights) {
    final quotes = [for (final h in highlights) h.quote];
    final key = (
      _s.markdown,
      _s.isWriting,
      _c.doc.sources.length,
      _s.evidence.length,
      quotes.join('\u0001'),
      widget.reading.brightness,
    );
    if (_body != null && key == _bodyKey) return _body!;
    _bodyKey = key;
    final data = applyHighlights(sectionBody(_s), quotes);
    return _body = Theme(
      data: widget.reading,
      child: Builder(
        builder: (context) => AppMarkdown(
          data: data,
          citations: _c.doc.sources,
          evidence: _s.evidence.isEmpty ? _c.doc.evidence : _s.evidence,
          streaming: _s.isWriting,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c.sectionListenable(_s.id),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final s = _s;
    final highlights = _c.highlightsFor(s.id);
    final hasText = s.markdown.trim().isNotEmpty;
    final Widget body;
    if (s.isFailed && !hasText) {
      body = _FailedCard(
        message: s.error,
        onRetry: s.retryable
            ? () => _c.rewrite(s.id, DocRewriteOp.regenerate)
            : null,
      );
    } else if (!hasText) {
      body = _SectionSkeleton(
        goal: s.goal,
        targetWords: s.targetWords,
        writing: s.isWriting,
      );
    } else {
      body = DocSelectionArea(
        onAction: _onSelection,
        child: _markdown(highlights),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        DocStrings.sectionNo(widget.number),
                        style: t.caption.copyWith(
                          color: s.isWriting ? p.accent : p.textTertiary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      DocStatusDot(status: s.status),
                      if (s.isWriting) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          DocStrings.writingNow,
                          style: t.caption.copyWith(color: p.accent),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    s.heading.isEmpty ? s.goal : s.heading,
                    style: t.title.copyWith(
                      fontSize: DocSizes.sectionHeading,
                      height: DocSizes.sectionHeadingHeight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (_c.loaded)
              Semantics(
                button: true,
                label: DocStrings.menuTitle,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showDocSectionMenu(context, _c, s),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: AppIcon(
                      DocIcons.more,
                      size: AppIconSize.md,
                      color: p.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DocSizes.headingGap),
        body,
        if (s.isFailed && hasText && s.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(s.error!, style: t.caption.copyWith(color: p.accent)),
        ],
        DocMarginNotes(highlights: highlights, onRemove: _c.removeHighlight),
        if (highlights.any((h) => !h.hasNote)) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _manageHighlights(highlights),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      DocIcons.highlight,
                      size: AppIconSize.sm,
                      color: p.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      DocStrings.highlightCount(highlights.length),
                      style: t.caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A section not written yet: its goal over dot-matrix placeholder lines.
class _SectionSkeleton extends StatefulWidget {
  const _SectionSkeleton({
    required this.goal,
    this.targetWords = 0,
    required this.writing,
  });

  final String goal;
  final int targetWords;
  final bool writing;

  @override
  State<_SectionSkeleton> createState() => _SectionSkeletonState();
}

class _SectionSkeletonState extends State<_SectionSkeleton>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: DocSizes.pulse * 2,
  );

  @override
  void initState() {
    super.initState();
    if (widget.writing) _anim.repeat();
  }

  @override
  void didUpdateWidget(_SectionSkeleton old) {
    super.didUpdateWidget(old);
    if (widget.writing && !_anim.isAnimating) _anim.repeat();
    if (!widget.writing && _anim.isAnimating) _anim.stop();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.writing ? DocStrings.writingNow : DocStrings.pending,
                style: t.caption.copyWith(
                  color: widget.writing ? p.accent : p.textTertiary,
                ),
              ),
              const Spacer(),
              if (widget.targetWords > 0)
                Text(DocStrings.target(widget.targetWords), style: t.caption),
            ],
          ),
          if (widget.goal.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.goal,
              style: t.bodySmall.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const _Bars(widths: DocSizes.skeletonLines),
          const SizedBox(height: AppSpacing.md),
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) => DotMeter(
              fraction: widget.writing ? _anim.value : 0,
              litColor: p.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder text lines.
class _Bars extends StatelessWidget {
  const _Bars({required this.widths, this.height = DocSizes.skeletonBar});

  final List<double> widths;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, w) in widths.indexed) ...[
          if (i > 0) const SizedBox(height: DocSizes.skeletonGap),
          FractionallySizedBox(
            widthFactor: w,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: p.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FailedCard extends StatelessWidget {
  const _FailedCard({this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.accent, width: AppBorder.thin),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DocStrings.sectionFailed,
                  style: t.caption.copyWith(color: p.accent),
                ),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(message!, style: t.bodySmall),
                ],
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: AppSpacing.md),
            DocTextButton(
              label: DocStrings.retrySection,
              icon: DocIcons.regenerate,
              onTap: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DocSizes.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: context.text.body.copyWith(color: context.palette.accent),
          ),
          const SizedBox(height: AppSpacing.md),
          DocTextButton(label: AppStrings.retry, onTap: onRetry),
        ],
      ),
    );
  }
}

/// The bibliography: cited sources in first-use order, hanging ids.
class DocReferences extends StatelessWidget {
  const DocReferences({
    super.key,
    required this.references,
    this.evidence = const [],
  });

  final List<Citation> references;
  final List<Evidence> evidence;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final style = t.body.copyWith(
      fontSize: DocSizes.referenceSize,
      height: DocSizes.referenceHeight,
    );
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
        for (final c in references)
          InkWell(
            onTap: () => c.url.isEmpty
                ? showEvidenceSheet(context, c, evidence)
                : openUrl(context, c.url),
            onLongPress: () => showEvidenceSheet(context, c, evidence),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: DocSizes.referenceIdWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Text('[${c.id}]', style: t.caption),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: style,
                        children: [
                          TextSpan(
                            text: c.title.isEmpty ? c.site : c.title,
                            style: style.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: '. '),
                          if (c.isKb || c.url.isEmpty)
                            TextSpan(
                              text: DocStrings.knowledgeBase,
                              style: style.copyWith(
                                fontStyle: FontStyle.italic,
                                color: p.textSecondary,
                              ),
                            )
                          else ...[
                            if (c.site.isNotEmpty)
                              TextSpan(
                                text: '${c.site}. ',
                                style: style.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: p.textSecondary,
                                ),
                              ),
                            TextSpan(
                              text: c.url,
                              style: t.caption.copyWith(
                                color: p.textTertiary,
                                decoration: TextDecoration.underline,
                                decorationColor: p.border,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Glossary extends StatelessWidget {
  const _Glossary({required this.terms});

  final List<DocGlossaryTerm> terms;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(DocStrings.glossary, style: t.caption),
        const SizedBox(height: AppSpacing.md),
        for (final g in terms)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text.rich(
              TextSpan(
                style: t.bodySmall.copyWith(color: context.palette.textPrimary),
                children: [
                  TextSpan(
                    text: '${g.term}  ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: g.definition),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
