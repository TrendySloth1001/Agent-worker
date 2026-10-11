import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/storage.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/files_api.dart';
import '../../chat/widgets/attachment_views.dart';
import '../../chat/widgets/image_strip.dart';
import '../../settings/format.dart';
import '../storage_actions.dart';

/// Filter pill: filled when active.
class StorageChip extends StatelessWidget {
  const StorageChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            color: active ? p.textPrimary : Colors.transparent,
            border: Border.all(
              color: active ? p.textPrimary : p.borderStrong,
              width: AppBorder.thin,
            ),
          ),
          child: Text(
            label,
            style: context.text.caption.copyWith(
              color: active ? p.textInverse : p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class StorageSpinner extends StatelessWidget {
  const StorageSpinner({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AppIconSize.md,
    height: AppIconSize.md,
    child: CircularProgressIndicator(
      strokeWidth: AppSizes.attachProgress,
      color: context.palette.accent,
    ),
  );
}

/// Check circle shown on selectable items.
class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: StorageSizes.selectMark,
      height: StorageSizes.selectMark,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? p.accent
            : p.background.withValues(alpha: StorageSizes.badgeAlpha),
        border: Border.all(
          color: selected ? p.accent : p.borderStrong,
          width: AppBorder.thin,
        ),
      ),
      child: selected
          ? AppIcon(AppIcons.check, size: AppIconSize.xs, color: p.textInverse)
          : null,
    );
  }
}

/// Small caption on a translucent backdrop (duration, status).
class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      color: p.background.withValues(alpha: StorageSizes.badgeAlpha),
      child: Text(
        text,
        style: context.text.caption.copyWith(color: color ?? p.textPrimary),
      ),
    );
  }
}

/// Square thumbnail of an image or video, with duration and selection.
class StorageGridTile extends StatelessWidget {
  const StorageGridTile({
    super.key,
    required this.file,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final FileInfo file;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final thumb = file.thumbUrl;
    final status = switch (file.status) {
      FileStatus.processing => StorageStrings.processing,
      FileStatus.failed => StorageStrings.failed,
      FileStatus.ready => null,
    };
    return Semantics(
      label: file.name,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? p.accent : p.border,
              width: selected ? AppBorder.thick : AppBorder.thin,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null)
                NetImage(url: thumb)
              else
                Center(
                  child: AppIcon(
                    fileIcon(file.kind),
                    size: AppIconSize.lg,
                    color: p.textTertiary,
                  ),
                ),
              if (file.kind == FileKind.video)
                Center(
                  child: AppIcon(
                    AppIcons.play,
                    size: AppIconSize.lg,
                    color: p.textPrimary,
                  ),
                ),
              if (file.kind == FileKind.video && file.durationS != null)
                Positioned(
                  right: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: _Badge(formatDuration(file.durationS!)),
                ),
              if (status != null)
                Positioned(
                  left: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: _Badge(
                    status,
                    color: file.status == FileStatus.failed ? p.error : null,
                  ),
                ),
              if (selected)
                ColoredBox(
                  color: p.background.withValues(
                    alpha: StorageSizes.scrimAlpha,
                  ),
                ),
              if (selecting)
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: _SelectMark(selected: selected),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row for a document or audio file: icon, name, details, chat, actions.
class StorageListRow extends StatelessWidget {
  const StorageListRow({
    super.key,
    required this.file,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  final FileInfo file;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final created = file.createdAt;
    final sub = [
      storageSubtitle(file),
      if (created != null) agoLabel(created),
    ].where((s) => s.isNotEmpty).join(StorageStrings.separator);
    final chat = file.conversationId == null
        ? StorageStrings.notInChat
        : (file.conversationTitle?.trim().isNotEmpty ?? false)
        ? file.conversationTitle!.trim()
        : StorageStrings.untitledChat;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: StorageSizes.rowHeight,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            children: [
              if (selecting) ...[
                _SelectMark(selected: selected),
                const SizedBox(width: AppSpacing.md),
              ],
              Container(
                width: StorageSizes.rowThumb,
                height: StorageSizes.rowThumb,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: p.border, width: AppBorder.thin),
                ),
                child: AppIcon(
                  fileIcon(file.kind),
                  size: AppIconSize.md,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall.copyWith(color: p.textPrimary),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(
                        color: file.status == FileStatus.failed
                            ? p.error
                            : p.textTertiary,
                      ),
                    ),
                    Text(
                      chat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption,
                    ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  icon: AppIcon(
                    StorageIcons.more,
                    size: AppIconSize.md,
                    color: p.textTertiary,
                  ),
                  tooltip: StorageStrings.actionOpen,
                  onPressed: onMore,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
