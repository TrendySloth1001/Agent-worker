import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/preview.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/file_cache.dart';
import '../../../data/files_api.dart';
import 'preview_actions.dart';
import 'preview_view.dart';

/// In-app PDF viewer: vertical pages, pinch zoom, page indicator. The file
/// is cached on disk, so reopening is instant and nothing is held in memory
/// beyond the pages on screen.
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({super.key, required this.file});

  final FileInfo file;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen>
    with PreviewViewMixin {
  @override
  FileInfo get viewFile => widget.file;

  final _controller = PdfViewerController();
  String? _path;
  bool _failed = false;
  double? _progress;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    loadSavedView();
    _resolve();
  }

  Future<void> _retry() async {
    if (widget.file.id.isNotEmpty) {
      await FileCache.instance.evict(widget.file.id);
    }
    if (mounted) setState(() => _path = null);
    await _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _failed = false;
      _progress = null;
    });
    try {
      final f = await FileCache.instance.fetch(
        widget.file,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _path = f.path);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final path = _path;
    Widget body;
    if (path != null) {
      body = PdfViewer.file(
        path,
        controller: _controller,
        params: PdfViewerParams(
          backgroundColor: p.background,
          maxScale: AppSizes.previewPdfMaxScale,
          onViewerReady: (doc, _) {
            if (mounted) setState(() => _pages = doc.pages.length);
          },
          onPageChanged: (n) {
            if (n != null && mounted && n != _page) setState(() => _page = n);
          },
          errorBannerBuilder: (context, error, stackTrace, ref) =>
              PreviewMessage(
                title: AppStrings.previewLoadFailed,
                error: true,
                onRetry: _retry,
              ),
        ),
      );
    } else if (_failed) {
      body = PreviewMessage(
        title: AppStrings.previewLoadFailed,
        error: true,
        onRetry: _retry,
      );
    } else {
      body = Center(
        child: Semantics(
          label: PreviewStrings.loadingFile,
          child: CircularProgressIndicator(value: _progress),
        ),
      );
    }
    return Scaffold(
      appBar: PreviewBar(
        file: widget.file,
        view: canSwitchView ? view : null,
        onView: pickView,
      ),
      body: DualBody(
        ready: viewReady,
        view: view,
        file: widget.file,
        original: Stack(
          children: [
            Positioned.fill(child: body),
            if (_pages > 0)
              Positioned(
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: SafeArea(
                  child: Semantics(
                    label: AppStrings.previewPage(_page, _pages),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        AppStrings.previewPage(_page, _pages),
                        style: t.caption,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
