import 'package:flutter/material.dart';

import '../../core/constants/connectors.dart';
import '../../data/connect_api.dart';
import 'widgets/connector_reader.dart';

/// One Drive file read through sparky: Docs as Markdown, Sheets as a CSV
/// block, PDFs and Office files as extracted text.
class DriveFileScreen extends StatelessWidget {
  const DriveFileScreen({super.key, required this.file, this.load});

  final DriveFile file;

  /// Test seam; defaults to the live API.
  final Future<DriveContent> Function()? load;

  static String markdownOf(DriveContent c) => switch (c.format) {
    'csv' => '```csv\n${c.text}\n```',
    'text' => c.text,
    _ => c.text,
  };

  @override
  Widget build(BuildContext context) => ConnectorReader(
    provider: ConnectorIds.drive,
    id: file.id,
    initialTitle: file.name,
    openLabel: DriveStrings.openInDrive,
    prompt: DriveStrings.prompt,
    load: () async {
      final c = await (load ?? () => ConnectApi.instance.driveRead(file.id))();
      final metadata = c.format == 'metadata';
      return ReaderContent(
        title: c.file.name.isEmpty ? file.name : c.file.name,
        markdown: markdownOf(c),
        url: c.file.webViewLink ?? file.webViewLink ?? '',
        truncated: c.truncated,
        canAddToKb: !metadata,
        note: metadata ? DriveStrings.unreadable : null,
      );
    },
  );
}
