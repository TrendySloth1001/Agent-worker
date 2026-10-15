import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_files.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_api.dart';
import '../../../data/files_api.dart';
import 'image_strip.dart';
import '../preview/file_preview.dart';
import '../preview/image_preview.dart';

AppIconData fileIcon(FileKind kind) => switch (kind) {
  FileKind.image => AppIcons.image,
  FileKind.video => AppIcons.video,
  FileKind.audio => AppIcons.audio,
  FileKind.document => AppIcons.file,
};

String formatBytes(int bytes) {
  if (bytes < AppFiles.kb) return '$bytes B';
  if (bytes < AppFiles.mb) return '${(bytes / AppFiles.kb).round()} KB';
  if (bytes < AppFiles.gb) {
    return '${(bytes / AppFiles.mb).toStringAsFixed(1)} MB';
  }
  return '${(bytes / AppFiles.gb).toStringAsFixed(2)} GB';
}

String formatDuration(double seconds) {
  final s = seconds.round();
  final m = s ~/ 60;
  final r = (s % 60).toString().padLeft(2, '0');
  return '$m:$r';
}

/// Second line of a file card: pages, duration or size.
String fileSubtitle(FileInfo f) {
  final parts = <String>[];
  final pages = f.pages;
  if (pages != null) {
    parts.add(
      '$pages ${pages == 1 ? AppStrings.attachPage : AppStrings.attachPages}',
    );
  }
  final d = f.durationS;
  if (d != null) parts.add(formatDuration(d));
  if (f.size > 0) parts.add(formatBytes(f.size));
  return parts.join(' · ');
}

/// Attachments of a sent message. Saved chats keep no signed URLs, so each
/// file is refreshed with GET /files/:id (cached for the session).
class MessageAttachments extends StatefulWidget {
  const MessageAttachments({super.key, required this.files});

  final List<FileInfo> files;

  @override
  State<MessageAttachments> createState() => _MessageAttachmentsState();
}

class _MessageAttachmentsState extends State<MessageAttachments> {
  late List<FileInfo> _files = widget.files;

  /// Keeps hero tags unique when a file shows in more than one message.
  late final String _scope = 'm${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    _refresh();
    FilesApi.instance.changes.addListener(_refresh);
  }

  @override
  void dispose() {
    FilesApi.instance.changes.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didUpdateWidget(MessageAttachments old) {
    super.didUpdateWidget(old);
    // The element can be reused for another message (chat switched).
    if (!_sameIds(old.files, widget.files)) {
      _files = widget.files;
      _refresh();
    }
  }

  static bool _sameIds(List<FileInfo> a, List<FileInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> _refresh() async {
    final files = widget.files;
    final fresh = await Future.wait([
      for (final f in files)
        if (f.deleted || f.id.isEmpty)
          Future.value(f)
        else
          FilesApi.instance.get(f.id).then<FileInfo>(f.withFresh).catchError((
            Object e,
          ) {
            // Gone from storage: show the placeholder, not an error.
            return e is ApiException && e.status == 404 ? f.asDeleted() : f;
          }),
    ]);
    if (mounted && identical(files, widget.files)) {
      setState(() => _files = fresh);
    }
  }

  Widget _heroed(BuildContext context, FileInfo f, Widget tile) => Semantics(
    button: true,
    label: f.name,
    child: f.kind == FileKind.image && !MediaQuery.disableAnimationsOf(context)
        ? Hero(tag: fileHeroTag(_scope, f), child: tile)
        : tile,
  );

  @override
  Widget build(BuildContext context) {
    final media = _files
        .where(
          (f) =>
              !f.deleted &&
              (f.kind == FileKind.image || f.kind == FileKind.video),
        )
        .toList();
    final cards = _files
        .where(
          (f) =>
              f.deleted ||
              f.kind == FileKind.document ||
              f.kind == FileKind.audio,
        )
        .toList();
    final cols = media.length.clamp(1, AppSizes.attachGridColumns);
    final width =
        MediaQuery.sizeOf(context).width * AppSizes.maxBubbleWidthFactor;
    final tile = ((width - AppSizes.attachGap * (cols - 1)) / cols).clamp(
      0.0,
      AppSizes.attachGridMax,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (media.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSizes.attachGap,
              runSpacing: AppSizes.attachGap,
              children: [
                for (final f in media)
                  GestureDetector(
                    onTap: () =>
                        openFilePreview(context, _files, f, heroScope: _scope),
                    child: _heroed(context, f, _MediaTile(file: f, size: tile)),
                  ),
              ],
            ),
          ),
        for (final f in cards) ...[
          const SizedBox(height: AppSizes.attachGap),
          if (f.deleted)
            DeletedFileTile(file: f)
          else
            GestureDetector(
              onTap: () => openFilePreview(context, _files, f),
              child: _FileCard(file: f),
            ),
        ],
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.file, required this.size});

  final FileInfo file;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final thumb =
        file.thumbUrl ?? (file.kind == FileKind.image ? file.url : null);
    final local = file.localPath;
    Widget content;
    if (thumb != null) {
      content = NetImage(url: thumb);
    } else if (local != null && file.kind == FileKind.image) {
      content = Image.file(
        File(local),
        fit: BoxFit.cover,
        cacheWidth: AppSizes.attachCacheWidth,
        errorBuilder: (context, _, _) => _icon(p),
      );
    } else {
      content = _icon(p);
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (file.kind == FileKind.video) ...[
            Center(
              child: Container(
                width: AppSizes.attachBadge + AppSpacing.sm,
                height: AppSizes.attachBadge + AppSpacing.sm,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.background.withValues(alpha: 0.7),
                ),
                child: AppIcon(
                  AppIcons.play,
                  size: AppIconSize.md,
                  color: p.textPrimary,
                ),
              ),
            ),
            if (file.durationS != null)
              Positioned(
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  color: p.background.withValues(alpha: 0.7),
                  child: Text(
                    formatDuration(file.durationS!),
                    style: context.text.caption.copyWith(color: p.textPrimary),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _icon(AppPalette p) => Center(
    child: AppIcon(
      fileIcon(file.kind),
      size: AppIconSize.lg,
      color: p.textTertiary,
    ),
  );
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file});

  final FileInfo file;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final sub = fileSubtitle(file);
    return Container(
      constraints: const BoxConstraints(maxWidth: AppSizes.attachCardWidth),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            fileIcon(file.kind),
            size: AppIconSize.md,
            color: p.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: p.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for an attachment whose file was deleted from storage.
class DeletedFileTile extends StatelessWidget {
  const DeletedFileTile({super.key, required this.file});

  final FileInfo file;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Semantics(
      label: '${AppStrings.attachDeleted} ${file.name}',
      child: Container(
        constraints: const BoxConstraints(maxWidth: AppSizes.attachCardWidth),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: p.border, width: AppBorder.thin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.fileDeleted,
              size: AppIconSize.md,
              color: p.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppStrings.attachDeleted,
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                  if (file.name.isNotEmpty)
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(
                        color: p.textTertiary,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: p.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
