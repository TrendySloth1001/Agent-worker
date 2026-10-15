import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/preview.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/file_cache.dart';
import '../../../data/files_api.dart';
import '../widgets/attachment_views.dart';
import '../widgets/image_strip.dart';
import 'preview_actions.dart';

/// Hero tag of a file's image tile; [scope] keeps tags unique when the same
/// file is shown in more than one message.
String fileHeroTag(String scope, FileInfo f) =>
    'preview-$scope-${f.id.isEmpty ? (f.localPath ?? f.name) : f.id}';

/// Full-screen, dark viewer for the images of one message or list: swipe
/// between them, pinch or double-tap to zoom, hero transition from the
/// tile, and the file actions in the top bar.
class FileImageViewer extends StatefulWidget {
  const FileImageViewer({
    super.key,
    required this.files,
    required this.initial,
    this.heroScope,
  });

  final List<FileInfo> files;
  final int initial;

  /// Set when the tapped tile is a [Hero] with [fileHeroTag].
  final String? heroScope;

  @override
  State<FileImageViewer> createState() => _FileImageViewerState();
}

class _FileImageViewerState extends State<FileImageViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final file = widget.files[_index];
    final hero =
        widget.heroScope != null && !MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const AppIcon(
            AppIcons.close,
            size: AppIconSize.md,
            color: AppColors.white,
          ),
          tooltip: AppStrings.back,
          onPressed: () {
            Haptics.tap();
            Navigator.pop(context);
          },
        ),
        title: Text('${_index + 1} / ${widget.files.length}'),
        actions: [PreviewMenu(file: file, color: AppColors.white)],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.files.length,
              onPageChanged: (i) {
                Haptics.tick();
                setState(() => _index = i);
              },
              itemBuilder: (context, i) => _ImagePage(
                key: ValueKey(widget.files[i].id + widget.files[i].name),
                file: widget.files[i],
                heroTag: hero
                    ? fileHeroTag(widget.heroScope!, widget.files[i])
                    : null,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.copyWith(color: AppColors.white),
                    ),
                  ),
                  if (file.size > 0)
                    Text(
                      formatBytes(file.size).toUpperCase(),
                      style: t.caption.copyWith(color: AppColors.white),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One zoomable image: the cached file (downloaded once), with the poster
/// showing while it loads.
class _ImagePage extends StatefulWidget {
  const _ImagePage({super.key, required this.file, this.heroTag});

  final FileInfo file;
  final String? heroTag;

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage> {
  final _zoom = TransformationController();
  File? _image;
  bool _failed = false;
  double? _progress;
  Offset _tap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      if (mounted) setState(() => _image = f);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _doubleTap() {
    Haptics.tick();
    if (_zoom.value.getMaxScaleOnAxis() > 1.01) {
      _zoom.value = Matrix4.identity();
    } else {
      final z = AppSizes.imageDoubleTapZoom;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-_tap.dx * (z - 1), -_tap.dy * (z - 1), 0, 1)
        ..scaleByDouble(z, z, 1, 1);
    }
  }

  Widget _content(AppPalette p) {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.imageMissing,
              size: AppIconSize.lg,
              color: AppColors.white,
              semanticLabel: AppStrings.imageFailed,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(onPressed: _load, child: const Text(AppStrings.retry)),
          ],
        ),
      );
    }
    final image = _image;
    if (image == null) {
      final thumb = widget.file.thumbUrl;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null) NetImage(url: thumb, fit: BoxFit.contain),
          Center(
            child: Semantics(
              label: PreviewStrings.loadingFile,
              child: CircularProgressIndicator(value: _progress),
            ),
          ),
        ],
      );
    }
    return Image.file(
      image,
      fit: BoxFit.contain,
      semanticLabel: widget.file.name,
      errorBuilder: (context, _, _) => Center(
        child: AppIcon(
          AppIcons.imageMissing,
          size: AppIconSize.lg,
          color: AppColors.white,
          semanticLabel: AppStrings.imageFailed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = _content(context.palette);
    final tag = widget.heroTag;
    if (tag != null) child = Hero(tag: tag, child: child);
    return GestureDetector(
      onDoubleTapDown: (d) => _tap = d.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _zoom,
        maxScale: AppSizes.imageMaxZoom,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}
