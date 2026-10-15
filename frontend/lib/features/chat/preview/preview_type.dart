import '../../../core/constants/preview.dart';
import '../../../data/files_api.dart';

/// Which viewer shows a file.
enum PreviewType {
  image,
  video,
  audio,
  pdf,
  markdown,
  code,
  csv,
  json,
  text,

  /// Word, Excel, PowerPoint and friends: the server's extracted text.
  office,

  /// Nothing to render: an info card with the actions.
  unknown,
}

/// Picks the viewer from the kind, extension and MIME type.
PreviewType previewTypeOf(FileInfo f) {
  switch (f.kind) {
    case FileKind.image:
      return PreviewType.image;
    case FileKind.video:
      return PreviewType.video;
    case FileKind.audio:
      return PreviewType.audio;
    case FileKind.document:
      break;
  }
  final ext = extensionOf(f.name);
  final mime = f.mime.toLowerCase();
  if (ext == 'pdf' || mime == 'application/pdf') return PreviewType.pdf;
  if (PreviewConfig.markdownExtensions.contains(ext) ||
      mime == 'text/markdown') {
    return PreviewType.markdown;
  }
  if (PreviewConfig.csvExtensions.contains(ext) || mime == 'text/csv') {
    return PreviewType.csv;
  }
  if (PreviewConfig.jsonExtensions.contains(ext) ||
      mime == 'application/json') {
    return PreviewType.json;
  }
  if (PreviewConfig.officeExtensions.contains(ext) ||
      mime.contains('officedocument') ||
      mime.contains('msword') ||
      mime.contains('ms-excel') ||
      mime.contains('ms-powerpoint')) {
    return PreviewType.office;
  }
  if (PreviewConfig.codeLanguages.containsKey(ext)) return PreviewType.code;
  if (PreviewConfig.plainTextExtensions.contains(ext) ||
      mime.startsWith('text/')) {
    return PreviewType.text;
  }
  return PreviewType.unknown;
}

/// highlight.js language for a code file, or null.
String? codeLanguageOf(FileInfo f) =>
    PreviewConfig.codeLanguages[extensionOf(f.name)];

/// Types read as raw bytes from the cached file (not server text).
bool isRawText(PreviewType t) => const {
  PreviewType.markdown,
  PreviewType.code,
  PreviewType.csv,
  PreviewType.json,
  PreviewType.text,
}.contains(t);

/// Short upper-case label for the type ("PDF", "CSV").
String typeLabelOf(FileInfo f) {
  final ext = extensionOf(f.name);
  if (ext.isNotEmpty) return ext.toUpperCase();
  return f.kind.name.toUpperCase();
}
