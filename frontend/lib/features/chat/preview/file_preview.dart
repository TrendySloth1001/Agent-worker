import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../data/chat_event.dart';
import '../../../data/files_api.dart';
import '../widgets/attachment_views.dart';
import '../widgets/image_strip.dart';
import 'media_preview.dart';
import 'pdf_preview.dart';
import 'text_preview.dart';

bool _isPdf(FileInfo f) =>
    extensionOf(f.name) == 'pdf' || f.mime == 'application/pdf';

/// Opens the right in-app viewer for [file]. [siblings] are the other files
/// of the same message or composer, so images can be swiped together.
Future<void> openFilePreview(
  BuildContext context,
  List<FileInfo> siblings,
  FileInfo file,
) async {
  Haptics.tap();
  final nav = Navigator.of(context);
  switch (file.kind) {
    case FileKind.image:
      final images = siblings.where((f) => f.kind == FileKind.image).toList();
      // Fresh signed URLs for images that only have an id (cached usually).
      final fresh = await Future.wait([
        for (final i in images)
          if (i.url == null && i.localPath == null && i.id.isNotEmpty)
            FilesApi.instance
                .get(i.id)
                .then<FileInfo>(i.withFresh)
                .catchError((Object _) => i)
          else
            Future.value(i),
      ]);
      final shown = fresh
          .where((i) => i.url != null || i.localPath != null)
          .toList();
      final index = shown.indexWhere(
        (i) => i.id == file.id && i.name == file.name,
      );
      if (index < 0) {
        if (context.mounted) _failed(context);
        return;
      }
      if (!context.mounted) return;
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewer(
            images: [
              for (final i in shown)
                ImageRef(
                  url: i.url ?? '',
                  sourceUrl: '',
                  title: i.name,
                  site: formatBytes(i.size),
                ),
            ],
            localPaths: [for (final i in shown) i.localPath],
            initial: index,
            fileActions: true,
          ),
        ),
      );
    case FileKind.video:
    case FileKind.audio:
      await nav.push(
        MaterialPageRoute<void>(builder: (_) => MediaPreviewScreen(file: file)),
      );
    case FileKind.document:
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => _isPdf(file)
              ? PdfPreviewScreen(file: file)
              : TextPreviewScreen(file: file),
        ),
      );
  }
}

void _failed(BuildContext context) {
  Haptics.error();
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppStrings.attachOpenFailed)));
}
