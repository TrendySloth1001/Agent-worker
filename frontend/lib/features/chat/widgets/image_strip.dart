import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/chat_event.dart';
import '../preview/preview_actions.dart';
import 'open_url.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/app_icon.dart';

/// Swipeable row of explanatory images; tap one to view it full screen.
class ImageStrip extends StatelessWidget {
  const ImageStrip({super.key, required this.images});

  final List<ImageRef> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.imageStripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () {
            Haptics.tap();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImageViewer(images: images, initial: i),
              ),
            );
          },
          child: _Thumb(image: images[i]),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image});

  final ImageRef image;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: AppSizes.imageThumbWidth,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Diagrams are often transparent line art; white keeps them legible.
        color: p.imageBackdrop,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetImage(url: image.url, fit: BoxFit.contain),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              color: p.surface.withValues(alpha: 0.85),
              child: Text(
                image.site.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.caption,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Network image with a quiet placeholder and failure state.
class NetImage extends StatelessWidget {
  const NetImage({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Image.network(
      url,
      fit: fit,
      headers: AppConfig.imageHeaders,
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: AppDurations.imageFade,
              child: child,
            ),
      errorBuilder: (context, _, _) => Center(
        child: AppIcon(
          AppIcons.imageMissing,
          size: AppIconSize.md,
          color: p.textTertiary,
          semanticLabel: AppStrings.imageFailed,
        ),
      ),
    );
  }
}

/// Full-screen pager with pinch zoom and a link to the image's page.
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.images,
    required this.initial,
    this.localPaths,
    this.fileActions = false,
  });

  final List<ImageRef> images;
  final int initial;

  /// Picked files on this phone, parallel to [images]; shown instead of the
  /// network image when present.
  final List<String?>? localPaths;

  /// Adds OPEN and COPY LINK for the current image's URL (attachments).
  final bool fileActions;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _page(int i) {
    final local = widget.localPaths?[i];
    final url = widget.images[i].url;
    if (local != null && File(local).existsSync()) {
      return Image.file(
        File(local),
        fit: BoxFit.contain,
        errorBuilder: (context, _, _) => url.isEmpty
            ? const SizedBox.shrink()
            : NetImage(url: url, fit: BoxFit.contain),
      );
    }
    return NetImage(url: url, fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final image = widget.images[_index];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const AppIcon(AppIcons.close, size: AppIconSize.md),
          tooltip: AppStrings.back,
          onPressed: () {
            Haptics.tap();
            Navigator.pop(context);
          },
        ),
        title: Text('${_index + 1} / ${widget.images.length}'),
        actions: [
          if (widget.fileActions)
            PreviewActions(url: image.url.isEmpty ? null : image.url),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.images.length,
              onPageChanged: (i) {
                Haptics.tick();
                setState(() => _index = i);
              },
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: AppSizes.imageMaxZoom,
                child: Container(
                  margin: const EdgeInsets.all(AppSpacing.screenPadding),
                  color: p.imageBackdrop,
                  child: _page(i),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                0,
                AppSpacing.screenPadding,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          image.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(image.site.toUpperCase(), style: t.caption),
                      ],
                    ),
                  ),
                  if (image.sourceUrl.isNotEmpty)
                    TextButton(
                      onPressed: () => openUrl(context, image.sourceUrl),
                      child: const Text(AppStrings.openSource),
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
