import 'package:flutter/material.dart';

import '../../data/files_api.dart';
import '../../data/kb_source.dart';
import '../chat/preview/file_preview.dart';

/// The stored file behind an uploaded-document source (`uri` is
/// `file:<id>`), or null for every other source type.
FileInfo? knowledgeFileOf(KbSource source) {
  if (source.type != 'file') return null;
  const prefix = 'file:';
  if (!source.uri.startsWith(prefix)) return null;
  final id = source.uri.substring(prefix.length);
  if (id.isEmpty) return null;
  final name = (source.title ?? '').trim();
  final fallback = name.isEmpty ? id : name;
  return FileInfo(
    id: id,
    name: fallback,
    mime: mimeFor(fallback),
    kind: guessKind(fallback),
    status: FileStatus.ready,
  );
}

/// Taps on an uploaded document in the knowledge base open its preview.
Future<void> openKnowledgeFile(BuildContext context, KbSource source) async {
  final stub = knowledgeFileOf(source);
  if (stub == null) return;
  // The real name, type and size come from the file record.
  var file = stub;
  try {
    file = stub.withFresh(await FilesApi.instance.get(stub.id));
  } catch (_) {
    /* the title-based guess still previews */
  }
  if (!context.mounted) return;
  await openFilePreview(context, [file], file);
}
