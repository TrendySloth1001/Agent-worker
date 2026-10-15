import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/preview.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/file_insight.dart';
import '../../../data/files_api.dart';
import '../widgets/attachment_views.dart';
import '../widgets/markdown/app_markdown.dart';
import 'preview_actions.dart';
import 'sparky_text.dart';

enum _Phase { loading, ready, error }

/// What sparky understands from a file, nicely laid out: a short summary and
/// key points, the text as clean markdown (documents, audio), the caption and
/// text read from a picture, or a timeline of frames and speech (video).
/// Everything is read from the server and cached there; "Read it now" asks
/// sparky to read the file when it has not.
class SparkyView extends StatefulWidget {
  const SparkyView({super.key, required this.file});

  final FileInfo file;

  @override
  State<SparkyView> createState() => _SparkyViewState();
}

class _SparkyViewState extends State<SparkyView> {
  _Phase _phase = _Phase.loading;
  InsightData? _data;
  bool _reading = false;
  bool _readFailed = false;

  // Extracted text, paged.
  String _text = '';
  int _chars = 0;
  bool _more = false;
  bool _loadingMore = false;

  FileUnderstanding get _api => FileUnderstanding.instance;
  FileKind get _kind => widget.file.kind;
  bool get _hasBody => _kind == FileKind.document || _kind == FileKind.audio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _phase = _Phase.loading);
    try {
      final data = await _api.insight(widget.file.id);
      if (!mounted) return;
      _data = data;
      _text = '';
      _more = false;
      if (_hasBody && data.hasText) await _page(0);
      if (mounted) setState(() => _phase = _Phase.ready);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  Future<void> _page(int offset) async {
    final r = await _api.text(
      widget.file.id,
      offset: offset,
      limit: PreviewConfig.sparkyPage,
    );
    if (!mounted) return;
    setState(() {
      _text = offset == 0 ? r.text : '$_text${r.text}';
      _chars = r.chars;
      _more = r.truncated;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    Haptics.tap();
    setState(() => _loadingMore = true);
    try {
      await _page(_text.length);
    } catch (_) {
      Haptics.error();
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _read() async {
    if (_reading) return;
    Haptics.tap();
    setState(() {
      _reading = true;
      _readFailed = false;
    });
    try {
      final data = await _api.read(widget.file.id);
      if (!mounted) return;
      _data = data;
      if (_hasBody && data.hasText && _text.isEmpty) await _page(0);
    } catch (_) {
      Haptics.error();
      if (mounted) _readFailed = true;
    }
    if (mounted) setState(() => _reading = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final Widget body;
    if (_phase == _Phase.loading) {
      body = Center(
        child: Semantics(
          label: PreviewStrings.sparkyLoading,
          child: const CircularProgressIndicator(),
        ),
      );
    } else if (_phase == _Phase.error || data == null) {
      body = PreviewMessage(
        title: PreviewStrings.sparkyErrorTitle,
        hint: PreviewStrings.sparkyErrorHint,
        error: true,
        onRetry: _load,
      );
    } else {
      body = _content(data);
    }
    return KeyedSubtree(key: const ValueKey('sparky-view'), child: body);
  }

  Widget _content(InsightData d) {
    if (d.processing) {
      return PreviewMessage(
        title: PreviewStrings.sparkyBusyTitle,
        hint: PreviewStrings.sparkyBusyHint,
        onRetry: _load,
      );
    }
    if (_kind != FileKind.image && !d.hasText && d.video == null) {
      return PreviewMessage(
        title: PreviewStrings.sparkyNoTextTitle,
        hint: PreviewStrings.sparkyNoTextHint,
      );
    }
    final insight = d.insight;
    final children = <Widget>[];
    switch (_kind) {
      case FileKind.image:
        if (insight == null) return _notRead();
        children.addAll(_imageBlocks(insight));
      case FileKind.video:
        children.addAll(_videoBlocks(d));
      case FileKind.document:
      case FileKind.audio:
        children.add(
          insight == null ? _summarizeCard() : _summaryCard(insight),
        );
        if (insight != null && insight.keyPoints.isNotEmpty) {
          children.add(_keyPoints(insight.keyPoints));
        }
        children.add(_textBlock());
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: PreviewSizes.sparkyMaxWidth,
        ),
        child: SelectionArea(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ),
    );
  }

  // ---- blocks ------------------------------------------------------------

  Widget _notRead() {
    return PreviewMessage(
      title: PreviewStrings.sparkyNotReadTitle,
      hint: _readFailed
          ? PreviewStrings.sparkyReadFailed
          : PreviewStrings.sparkyNotReadHint,
      error: _readFailed,
      action: _readButton(PreviewStrings.sparkyReadNow),
    );
  }

  Widget _readButton(String label) => FilledButton(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, AppSizes.buttonHeight),
    ),
    onPressed: _reading ? null : _read,
    child: _reading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: AppIconSize.md,
                height: AppIconSize.md,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text(PreviewStrings.sparkyReading),
            ],
          )
        : Text(label),
  );

  Widget _card({required String title, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                PreviewIcons.viewSparky,
                size: AppIconSize.sm,
                color: context.palette.accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: context.text.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _body(String text) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.bodyLarge!.copyWith(color: context.palette.textPrimary),
  );

  Widget _summaryCard(FileInsight i) =>
      _card(title: PreviewStrings.sparkySummary, child: _body(i.summary));

  Widget _summarizeCard() {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      title: PreviewStrings.sparkySummary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _readFailed
                ? PreviewStrings.sparkyReadFailed
                : PreviewStrings.sparkyNoSummaryHint,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: _readFailed ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _readButton(PreviewStrings.sparkySummarize),
        ],
      ),
    );
  }

  Widget _keyPoints(List<String> points) {
    final p = context.palette;
    return _card(
      title: PreviewStrings.sparkyKeyPoints,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      right: AppSpacing.md,
                    ),
                    child: Container(
                      width: PreviewSizes.timelineDot,
                      height: PreviewSizes.timelineDot,
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: _body(point)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _textBlock() {
    final t = context.text;
    final left = (_chars - _text.length).clamp(0, _chars);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _kind == FileKind.audio
              ? PreviewStrings.sparkyTranscript
              : PreviewStrings.sparkyText,
          style: t.caption,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppMarkdown(
          data: readableMarkdown(_text),
          citations: const [],
          streaming: false,
        ),
        if (_more)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Center(
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.buttonHeight),
                ),
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(PreviewStrings.sparkyMore(left)),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _imageBlocks(FileInsight i) {
    final t = context.text;
    return [
      if ((i.caption ?? i.summary).isNotEmpty)
        _card(
          title: PreviewStrings.sparkyCaption,
          child: _body(i.caption ?? i.summary),
        ),
      if (i.keyPoints.isNotEmpty) _keyPoints(i.keyPoints),
      if (i.ocr != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(PreviewStrings.sparkyOcr, style: t.caption),
            const SizedBox(height: AppSpacing.sm),
            AppMarkdown(
              data: readableMarkdown(i.ocr!),
              citations: const [],
              streaming: false,
            ),
          ],
        ),
    ];
  }

  List<Widget> _videoBlocks(InsightData d) {
    final insight = d.insight;
    final v = d.video;
    final entries = v == null ? const <TimelineEntry>[] : timelineOf(v);
    final needsRead = insight == null || (v != null && !v.hasCaptions);
    return [
      if (insight != null) _summaryCard(insight),
      if (insight != null && insight.keyPoints.isNotEmpty)
        _keyPoints(insight.keyPoints),
      if (needsRead && v != null && v.frames.isNotEmpty)
        _card(
          title: insight == null
              ? PreviewStrings.sparkySummary
              : PreviewStrings.sparkyTimeline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _readFailed
                    ? PreviewStrings.sparkyReadFailed
                    : PreviewStrings.sparkyDescribeHint,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _readButton(PreviewStrings.sparkyReadNow),
            ],
          ),
        ),
      if (entries.isNotEmpty) _Timeline(entries: entries),
      if (v != null && v.transcriptStatus == 'silent')
        _note(PreviewStrings.sparkySilentVideo),
      if (v != null && v.transcriptStatus == 'no_audio')
        _note(PreviewStrings.sparkyNoAudio),
      if (v != null && v.frames.isEmpty) _note(PreviewStrings.sparkyNoFrames),
    ];
  }

  Widget _note(String text) => Text(text, style: context.text.caption);
}

/// Frames and speech by time: a time column, a rail with dots, the text.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(
              PreviewIcons.timeline,
              size: AppIconSize.sm,
              color: p.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(PreviewStrings.sparkyTimeline, style: t.caption),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < entries.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: PreviewSizes.timeColumn,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      formatDuration(entries[i].t),
                      style: t.code.copyWith(color: p.textTertiary),
                    ),
                  ),
                ),
                Column(
                  children: [
                    Container(
                      width: PreviewSizes.timelineDot,
                      height: PreviewSizes.timelineDot,
                      margin: const EdgeInsets.only(top: AppSpacing.xs),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entries[i].speech ? p.textTertiary : p.accent,
                      ),
                    ),
                    if (i < entries.length - 1)
                      Expanded(
                        child: Container(
                          width: PreviewSizes.timelineLine,
                          color: p.border,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Text(
                      entries[i].text,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: entries[i].speech
                            ? p.textSecondary
                            : p.textPrimary,
                        fontStyle: entries[i].speech
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
