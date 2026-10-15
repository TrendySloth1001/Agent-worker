import 'package:flutter/material.dart';

import '../../../core/constants/preview.dart';
import '../../../data/files_api.dart';
import 'file_info.dart';
import 'preview_actions.dart';

/// A file nothing here can draw (unknown type): name, type, size, date and
/// the SHARE / OPEN WITH… / DOWNLOAD buttons.
class InfoPreviewScreen extends StatelessWidget {
  const InfoPreviewScreen({super.key, required this.file, this.title, this.hint});

  final FileInfo file;
  final String? title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreviewBar(file: file),
      body: FileInfoCard(
        file: file,
        title: title ?? PreviewStrings.unknownTitle,
        hint: hint ?? PreviewStrings.unknownHint,
        children: [FileActionButtons(file: file)],
      ),
    );
  }
}
