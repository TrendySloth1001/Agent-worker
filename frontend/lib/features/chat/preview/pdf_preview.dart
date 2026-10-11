import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/files_api.dart';
import 'preview_actions.dart';

/// In-app PDF viewer: vertical pages, pinch zoom, page indicator.
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({super.key, required this.file});

  final FileInfo file;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  final _controller = PdfViewerController();
  String? _url;
  bool _failed = false;
  int _page = 1;
  int _pages = 0;

  bool get _local {
    final l = widget.file.localPath;
    return l != null && File(l).existsSync();
  }

  @override
  void initState() {
    super.initState();
    if (!_local) _resolve();
  }

  Future<void> _resolve({bool force = false}) async {
    final url = await resolveFileUrl(widget.file, force: force);
    if (!mounted) return;
    setState(() {
      _url = url;
      _failed = url == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final params = PdfViewerParams(
      backgroundColor: p.background,
      maxScale: AppSizes.previewPdfMaxScale,
      onViewerReady: (doc, _) {
        if (mounted) setState(() => _pages = doc.pages.length);
      },
      onPageChanged: (n) {
        if (n != null && mounted && n != _page) setState(() => _page = n);
      },
      errorBannerBuilder: (context, error, stackTrace, ref) => _Failed(
        onRetry: () {
          Haptics.tap();
          setState(() => _url = null);
          _resolve(force: true);
        },
      ),
    );
    Widget body;
    if (_local) {
      body = PdfViewer.file(
        widget.file.localPath!,
        controller: _controller,
        params: params,
      );
    } else if (_url != null) {
      body = PdfViewer.uri(
        Uri.parse(_url!),
        controller: _controller,
        params: params,
      );
    } else if (_failed) {
      body = _Failed(
        onRetry: () {
          Haptics.tap();
          setState(() => _failed = false);
          _resolve(force: true);
        },
      );
    } else {
      body = const SizedBox.shrink();
    }
    return Scaffold(
      appBar: PreviewBar(file: widget.file),
      body: Stack(
        children: [
          Positioned.fill(child: body),
          if (_pages > 0)
            Positioned(
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border.all(color: p.border, width: AppBorder.thin),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    AppStrings.previewPage(_page, _pages),
                    style: t.caption,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.previewLoadFailed,
            style: context.text.label.copyWith(color: p.error),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onRetry,
            child: Text(
              AppStrings.retry,
              style: context.text.label.copyWith(color: p.accent),
            ),
          ),
        ],
      ),
    );
  }
}
