import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/preview.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_api.dart';
import '../../../data/file_cache.dart';
import '../../../data/files_api.dart';
import '../widgets/markdown/app_markdown.dart';
import '../widgets/markdown/code_block.dart';
import 'csv_parse.dart';
import 'file_info.dart';
import 'preview_actions.dart';
import 'preview_type.dart';
import 'preview_view.dart';

enum _TextState { loading, processing, failed, ready }

/// Preview for text-like files: markdown rendered, code and JSON with the
/// syntax palette, CSV as a table, plain and Office text as paged blocks.
/// Raw text comes from the cached bytes; Office files show the text the
/// server extracted.
class TextPreviewScreen extends StatefulWidget {
  const TextPreviewScreen({super.key, required this.file});

  final FileInfo file;

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen>
    with PreviewViewMixin {
  @override
  FileInfo get viewFile => widget.file;

  _TextState _state = _TextState.loading;
  PreviewType get _type => viewType;
  List<String> _blocks = const [];
  List<List<String>> _rows = const [];
  String _text = '';
  bool _truncated = false;
  bool _source = false;
  int _shown = PreviewConfig.firstBlocks;
  int _csvShown = PreviewConfig.csvFirstRows;
  double? _progress;
  bool _searching = false;
  String _query = '';
  int _matches = 0;
  final _search = TextEditingController();

  bool get _mono => _type == PreviewType.code || _type == PreviewType.json;
  bool get _searchable =>
      _type != PreviewType.csv && !(_type == PreviewType.markdown && !_source);

  @override
  void initState() {
    super.initState();
    loadSavedView();
    // Office files have no original to draw; their text is the sparky view.
    if (_type == PreviewType.office) {
      _state = _TextState.ready;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> _split(String text) {
    final lines = text.split('\n');
    return [
      for (var i = 0; i < lines.length; i += PreviewConfig.blockLines)
        lines
            .sublist(i, (i + PreviewConfig.blockLines).clamp(0, lines.length))
            .join('\n'),
    ];
  }

  Future<({String text, bool truncated})> _serverText() async {
    final r = await FilesApi.instance.text(
      widget.file.id,
      limit: PreviewConfig.extractedTextLimit,
    );
    return (text: r.text, truncated: r.truncated);
  }

  Future<({String text, bool truncated})> _rawText() async {
    final f = widget.file;
    final local = f.localPath;
    final hasLocal = local != null && File(local).existsSync();
    if (!hasLocal && f.size > PreviewConfig.maxTextBytes && f.id.isNotEmpty) {
      return _serverText();
    }
    final File file;
    try {
      file = await FileCache.instance.fetch(
        f,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (_) {
      if (f.id.isNotEmpty) return _serverText();
      rethrow;
    }
    final length = await file.length();
    final cut = length > PreviewConfig.maxTextBytes;
    final bytes = cut
        ? await file
              .openRead(0, PreviewConfig.maxTextBytes)
              .expand((c) => c)
              .toList()
        : await file.readAsBytes();
    return (text: utf8.decode(bytes, allowMalformed: true), truncated: cut);
  }

  Future<void> _load() async {
    setState(() {
      _state = _TextState.loading;
      _progress = null;
    });
    final f = widget.file;
    try {
      final r = isRawText(_type)
          ? await _rawText()
          : f.id.isEmpty
          ? null
          : await _serverText();
      if (r == null) {
        if (mounted) setState(() => _state = _TextState.processing);
        return;
      }
      var text = r.text;
      if (_type == PreviewType.json &&
          text.length <= PreviewConfig.jsonPrettyBytes) {
        try {
          text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
        } catch (_) {
          /* not valid JSON: shown as it is */
        }
      }
      var rows = const <List<String>>[];
      if (_type == PreviewType.csv &&
          text.length <= PreviewConfig.csvMaxBytes) {
        rows = parseCsv(text);
      }
      if (!mounted) return;
      setState(() {
        _text = text;
        _blocks = _split(text);
        _rows = rows;
        _truncated = r.truncated;
        _state = _TextState.ready;
      });
      _recount();
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _state = e.status == 404
              ? _TextState.processing
              : _TextState.failed,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _state = _TextState.failed);
    }
  }

  void _recount() {
    final q = _query.toLowerCase();
    var n = 0;
    if (q.isNotEmpty) {
      for (final b in _blocks) {
        final lower = b.toLowerCase();
        var i = lower.indexOf(q);
        while (i >= 0) {
          n++;
          i = lower.indexOf(q, i + q.length);
        }
      }
    }
    setState(() => _matches = n);
  }

  TextSpan _highlight(String block, TextStyle style, Color mark) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return TextSpan(text: block, style: style);
    final lower = block.toLowerCase();
    final spans = <InlineSpan>[];
    var from = 0;
    var i = lower.indexOf(q);
    while (i >= 0) {
      if (i > from) spans.add(TextSpan(text: block.substring(from, i)));
      spans.add(
        TextSpan(
          text: block.substring(i, i + q.length),
          style: TextStyle(backgroundColor: mark),
        ),
      );
      from = i + q.length;
      i = lower.indexOf(q, from);
    }
    if (from < block.length) spans.add(TextSpan(text: block.substring(from)));
    return TextSpan(style: style, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final original = view == PreviewView.original;
    return Scaffold(
      appBar: PreviewBar(
        file: widget.file,
        view: canSwitchView ? view : null,
        onView: pickView,
        extra: [
          if (original &&
              _state == _TextState.ready &&
              _type == PreviewType.markdown)
            IconButton(
              icon: AppIcon(
                PreviewIcons.rawView,
                size: AppIconSize.md,
                color: _source ? p.accent : null,
              ),
              tooltip: PreviewStrings.viewToggle,
              onPressed: () {
                Haptics.tap();
                setState(() {
                  _source = !_source;
                  _searching = false;
                  _query = '';
                });
              },
            ),
          if (original && _state == _TextState.ready && _searchable)
            IconButton(
              icon: AppIcon(
                _searching ? AppIcons.close : AppIcons.search,
                size: AppIconSize.md,
                color: _searching ? p.accent : null,
              ),
              tooltip: AppStrings.previewSearch,
              onPressed: () {
                Haptics.tap();
                setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _search.clear();
                    _query = '';
                    _matches = 0;
                  }
                });
              },
            ),
        ],
      ),
      body: DualBody(view: view, file: widget.file, original: _original(p)),
    );
  }

  /// The file as it is: raw text and code, or, for an Office file that
  /// cannot be drawn here, a card that opens it in another app.
  Widget _original(AppPalette p) {
    if (_type == PreviewType.office) {
      return FileInfoCard(
        file: widget.file,
        title: PreviewStrings.originalOfficeTitle,
        hint: PreviewStrings.originalOfficeHint,
        children: [FileActionButtons(file: widget.file)],
      );
    }
    return switch (_state) {
      _TextState.loading => Center(
        child: CircularProgressIndicator(value: _progress),
      ),
      _TextState.processing => PreviewMessage(
        title: AppStrings.previewProcessing,
        hint: AppStrings.previewProcessingHint,
        onRetry: _load,
      ),
      _TextState.failed => PreviewMessage(
        title: AppStrings.previewLoadFailed,
        error: true,
        onRetry: _load,
      ),
      _TextState.ready => _content(p),
    };
  }

  Widget _content(AppPalette p) {
    if (_text.trim().isEmpty) {
      return PreviewMessage(title: PreviewStrings.emptyFile);
    }
    final t = context.text;
    final body = switch (_type) {
      PreviewType.markdown when !_source => _markdown(),
      PreviewType.csv when _rows.isNotEmpty => _CsvTable(
        rows: _rows,
        shown: _csvShown,
        onMore: () => setState(() => _csvShown += PreviewConfig.csvMoreRows),
      ),
      _ => _blocksList(p),
    };
    return Column(
      children: [
        if (_searching)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
              vertical: AppSpacing.xs,
            ),
            child: TextField(
              controller: _search,
              autofocus: true,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: AppStrings.previewSearchHint,
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.lg),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            AppStrings.previewMatches(_matches),
                            style: t.caption,
                          ),
                        ),
                      ),
              ),
              onChanged: (v) {
                _query = v.trim();
                _recount();
              },
            ),
          ),
        Expanded(child: body),
      ],
    );
  }

  Widget _loadMore(VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Center(
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSizes.buttonHeight),
        ),
        onPressed: () {
          Haptics.tap();
          onTap();
        },
        child: const Text(PreviewStrings.loadMore),
      ),
    ),
  );

  /// Markdown through the chat renderer; LOAD MORE grows the prefix.
  Widget _markdown() {
    final lines = _text.split('\n');
    final limit = _shown * PreviewConfig.blockLines;
    final more = lines.length > limit;
    final data = more ? lines.take(limit).join('\n') : _text;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          AppMarkdown(data: data, citations: const [], streaming: false),
          if (more)
            _loadMore(() => setState(() => _shown += PreviewConfig.moreBlocks)),
          if (_truncated && !more) _truncatedNote(),
        ],
      ),
    );
  }

  Widget _truncatedNote() => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: Text(AppStrings.previewTruncated, style: context.text.caption),
  );

  Widget _blocksList(AppPalette p) {
    final t = context.text;
    final style = (_mono ? t.code : t.body).copyWith(color: p.textPrimary);
    final searching = _query.isNotEmpty;
    final count = searching ? _blocks.length : _shown.clamp(0, _blocks.length);
    final more = count < _blocks.length;
    final lang = codeLanguageOf(widget.file);
    const header = 0;
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        itemCount: header + count + 1,
        itemBuilder: (context, i) {
          final n = i - header;
          if (n == count) {
            return Column(
              children: [
                if (more)
                  _loadMore(
                    () => setState(() => _shown += PreviewConfig.moreBlocks),
                  ),
                if (_truncated && !more) _truncatedNote(),
              ],
            );
          }
          final block = _blocks[n];
          if (lang != null &&
              !searching &&
              block.length <= AppSizes.codeMaxHighlightChars) {
            final spans = CodeBlock.highlightSpans(block, lang, p);
            if (spans != null) {
              return Text.rich(TextSpan(style: style, children: spans));
            }
          }
          return Text.rich(
            _highlight(block, style, p.accent.withValues(alpha: 0.35)),
          );
        },
      ),
    );
  }
}

/// Small CSV as a scrollable table: a header row, a row-number gutter and
/// LOAD MORE for the rest.
class _CsvTable extends StatelessWidget {
  const _CsvTable({
    required this.rows,
    required this.shown,
    required this.onMore,
  });

  final List<List<String>> rows;
  final int shown;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final cols = rows
        .take(shown)
        .fold<int>(0, (m, r) => r.length > m ? r.length : m)
        .clamp(1, PreviewConfig.csvMaxColumns);
    final visible = rows.take(shown).toList();
    // Column width from the longest of the first rows, within the limits.
    final widths = [
      for (var c = 0; c < cols; c++)
        (visible
                        .take(PreviewConfig.csvFirstRows)
                        .fold<int>(
                          0,
                          (m, r) =>
                              c < r.length && r[c].length > m ? r[c].length : m,
                        ) *
                    PreviewSizes.csvCharWidth +
                AppSpacing.lg * 2)
            .clamp(PreviewSizes.csvCellMinWidth, PreviewSizes.csvCellMaxWidth),
    ];
    final total = widths.fold<double>(0, (a, b) => a + b);
    final more = rows.length > shown;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: total + PreviewSizes.csvGutterWidth,
        child: Column(
          children: [
            Expanded(
              child: SelectionArea(
                child: ListView.builder(
                  itemCount: visible.length + 1,
                  itemBuilder: (context, i) {
                    if (i == visible.length) {
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              PreviewStrings.rows(visible.length, rows.length),
                              style: t.caption,
                            ),
                          ),
                          if (more)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md,
                              ),
                              child: FilledButton.tonal(
                                onPressed: () {
                                  Haptics.tap();
                                  onMore();
                                },
                                child: const Text(PreviewStrings.loadMore),
                              ),
                            ),
                        ],
                      );
                    }
                    final header = i == 0;
                    final row = visible[i];
                    return Container(
                      height: PreviewSizes.csvRowHeight,
                      decoration: BoxDecoration(
                        color: header
                            ? Theme.of(context).colorScheme.surfaceContainerHigh
                            : null,
                        border: Border(bottom: BorderSide(color: p.border)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: PreviewSizes.csvGutterWidth,
                            child: Center(
                              child: Text(header ? '' : '$i', style: t.caption),
                            ),
                          ),
                          for (var c = 0; c < cols; c++)
                            SizedBox(
                              width: widths[c],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                child: Text(
                                  c < row.length ? row[c] : '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (header ? t.label : t.code).copyWith(
                                    color: p.textPrimary,
                                    fontWeight: header ? FontWeight.w700 : null,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
