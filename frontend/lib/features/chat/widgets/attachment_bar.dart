import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/files_api.dart';
import '../attachments_controller.dart';
import '../../../core/constants/app_files.dart';
import '../preview/file_preview.dart';
import 'attachment_views.dart';
import 'image_strip.dart';

/// Horizontal row of files waiting to be sent.
class AttachmentBar extends StatelessWidget {
  const AttachmentBar({super.key, required this.controller});

  final AttachmentsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.items;
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${items.length} / ${AppFiles.maxPerMessage}',
                  textAlign: TextAlign.end,
                  style: context.text.caption,
                ),
              ),
              SizedBox(
                height: AppSizes.attachThumb + AppSpacing.xs,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSizes.attachGap),
                  itemBuilder: (context, i) => _AttachmentChip(
                    item: items[i],
                    onRetry: () => controller.retry(items[i]),
                    onRemove: () => controller.remove(items[i]),
                    onOpen: () => openFilePreview(context, [
                      for (final a in items) a.asFile,
                    ], items[i].asFile),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.item,
    required this.onRetry,
    required this.onRemove,
    required this.onOpen,
  });

  final PendingAttachment item;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  bool get _visual =>
      item.kind == FileKind.image || item.kind == FileKind.video;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final failed = item.failed;
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        failed ? onRetry() : onOpen();
      },
      onLongPress: () {
        Haptics.error();
        onRemove();
      },
      child: Container(
        width: _visual ? AppSizes.attachThumb : AppSizes.attachChipWidth,
        height: AppSizes.attachThumb,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: failed ? p.error : p.border,
            width: AppBorder.thin,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _visual ? _thumb(context) : _card(context),
            if (failed)
              Container(
                color: p.background.withValues(alpha: 0.6),
                child: Center(
                  child: AppIcon(
                    AppIcons.retry,
                    size: AppIconSize.md,
                    color: p.error,
                    semanticLabel: AppStrings.attachRetry,
                  ),
                ),
              ),
            if (!failed &&
                (item.state == PendingState.uploading || item.processing))
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: item.state == PendingState.uploading
                      ? item.progress
                      : null,
                  minHeight: AppSizes.attachProgress,
                  color: p.accent,
                  backgroundColor: p.border,
                ),
              ),
          ],
        ),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        body,
        Positioned(
          top: -AppSpacing.xs,
          right: -AppSpacing.xs,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tap();
              onRemove();
            },
            child: Container(
              width: AppSizes.attachRemove,
              height: AppSizes.attachRemove,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.textPrimary,
              ),
              child: AppIcon(
                AppIcons.close,
                size: AppIconSize.xs,
                color: p.textInverse,
                semanticLabel: AppStrings.attachRemove,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _thumb(BuildContext context) {
    final p = context.palette;
    final thumbUrl = item.info?.thumbUrl;
    if (thumbUrl != null) return NetImage(url: thumbUrl);
    if (item.kind == FileKind.image) {
      return Image.file(
        File(item.localPath),
        fit: BoxFit.cover,
        cacheWidth: AppSizes.attachCacheWidth,
        errorBuilder: (context, _, _) =>
            Center(child: AppIcon(AppIcons.image, color: p.textTertiary)),
      );
    }
    return Center(
      child: AppIcon(
        AppIcons.video,
        size: AppIconSize.lg,
        color: p.textSecondary,
      ),
    );
  }

  Widget _card(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final status = item.failed
        ? AppStrings.attachFailed
        : item.processing
        ? AppStrings.attachProcessing
        : (item.info != null
              ? fileSubtitle(item.info!)
              : formatBytes(item.size));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          AppIcon(
            fileIcon(item.kind),
            size: AppIconSize.md,
            color: p.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
                Text(
                  status,
                  maxLines: 1,
                  style: t.caption.copyWith(
                    color: item.failed ? p.error : p.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
