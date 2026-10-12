import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_files.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_api.dart';
import '../../../data/files_api.dart';
import 'preview_actions.dart';

enum _TextState { loading, processing, failed, ready }

/// Text preview for documents: extracted text from the server (or the
/// local file when it is plain text and still on this phone).
class TextPreviewScreen extends StatefulWidget {
  const TextPreviewScreen({super.key, required this.file});

  final FileInfo file;

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen> {
  _TextState _state = _TextState.loading;
  List<String> _blocks = const [];
  bool _truncated = false;
  bool _searching = false;
  String _query = '';
  int _matches = 0;
  final _search = TextEditingController();

  bool get _mono =>
      AppFiles.monoExtensions.contains(extensionOf(widget.file.name));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> _split(String text) {
    final lines = text.split('\n');
    return [
      for (var i = 0; i < lines.length; i += AppFiles.textBlockLines)
        lines
            .sublist(i, (i + AppFiles.textBlockLines).clamp(0, lines.length))
            .join('\n'),
    ];
  }

  Future<void> _load() async {
    setState(() => _state = _TextState.loading);
    final f = widget.file;
    final ext = extensionOf(f.name);
    try {
      final local = f.localPath;
      String text;
      var truncated = false;
      if (local != null &&
          AppFiles.localTextExtensions.contains(ext) &&
          File(local).existsSync()) {
        text = await File(local).readAsString();
        if (text.length > AppFiles.textPreviewLimit) {
          text = text.substring(0, AppFiles.textPreviewLimit);
          truncated = true;
        }
      } else if (f.id.isEmpty) {
        if (mounted) setState(() => _state = _TextState.processing);
        return;
      } else {
        final r = await FilesApi.instance.text(f.id);
        text = r.text;
        truncated = r.truncated;
      }
      if (!mounted) return;
      setState(() {
        _blocks = _split(text);
        _truncated = truncated;
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
    return Scaffold(
      appBar: PreviewBar(
        file: widget.file,
        extra: [
          if (_state == _TextState.ready)
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
      body: switch (_state) {
        _TextState.loading => const Center(child: CircularProgressIndicator()),
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
      },
    );
  }

  Widget _content(AppPalette p) {
    final t = context.text;
    final style = (_mono ? t.code : t.body).copyWith(color: p.textPrimary);
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
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              itemCount: _blocks.length + (_truncated ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _blocks.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(AppStrings.previewTruncated, style: t.caption),
                  );
                }
                return Text.rich(
                  _highlight(
                    _blocks[i],
                    style,
                    p.accent.withValues(alpha: 0.35),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
