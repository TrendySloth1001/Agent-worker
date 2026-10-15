import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../data/files_api.dart';
import 'image_preview.dart';
import 'info_preview.dart';
import 'media_preview.dart';
import 'pdf_preview.dart';
import 'preview_type.dart';
import 'text_preview.dart';

/// Opens the right in-app viewer for [file]. [siblings] are the other files
/// of the same message or composer, so images can be swiped together.
/// [heroScope] matches the tile's [Hero] (see [fileHeroTag]).
Future<void> openFilePreview(
  BuildContext context,
  List<FileInfo> siblings,
  FileInfo file, {
  String? heroScope,
}) async {
  Haptics.tap();
  if (file.deleted) {
    _notice(context, AppStrings.attachDeleted);
    return;
  }
  final nav = Navigator.of(context);
  final Widget screen;
  switch (previewTypeOf(file)) {
    case PreviewType.image:
      final images = siblings
          .where(
            (f) =>
                f.kind == FileKind.image &&
                !f.deleted &&
                (f.id.isNotEmpty || f.localPath != null),
          )
          .toList();
      final index = images.indexWhere(
        (i) => i.id == file.id && i.name == file.name,
      );
      if (index < 0) {
        _failed(context);
        return;
      }
      screen = FileImageViewer(
        files: images,
        initial: index,
        heroScope: heroScope,
      );
    case PreviewType.video:
    case PreviewType.audio:
      screen = MediaPreviewScreen(file: file);
    case PreviewType.pdf:
      screen = PdfPreviewScreen(file: file);
    case PreviewType.markdown:
    case PreviewType.code:
    case PreviewType.csv:
    case PreviewType.json:
    case PreviewType.text:
    case PreviewType.office:
      screen = TextPreviewScreen(file: file);
    case PreviewType.unknown:
      screen = InfoPreviewScreen(file: file);
  }
  await nav.push(MaterialPageRoute<void>(builder: (_) => screen));
}

void _failed(BuildContext context) =>
    _notice(context, AppStrings.attachOpenFailed);

void _notice(BuildContext context, String text) {
  Haptics.error();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
