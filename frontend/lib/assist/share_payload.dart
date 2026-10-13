import '../core/constants/assist.dart';

/// One file shared to "Ask sparky", already copied into the app's cache.
class SharedFile {
  const SharedFile({required this.path, required this.name, this.size = 0});

  final String path;
  final String name;
  final int size;
}

/// What another app shared to "Ask sparky" (ACTION_SEND / SEND_MULTIPLE),
/// as ShareIntake.kt hands it over.
class SharedPayload {
  const SharedPayload({
    this.text = '',
    this.subject,
    this.files = const [],
    this.skipped = 0,
  });

  /// Shared text or link (EXTRA_TEXT).
  final String text;

  /// EXTRA_SUBJECT (a page title from a browser, an email subject).
  final String? subject;
  final List<SharedFile> files;

  /// Items that could not be read or were too big.
  final int skipped;

  bool get isEmpty => text.isEmpty && files.isEmpty;

  /// What goes into the field: the subject above the text, unless the text
  /// already starts with it (browsers send the title and the link).
  String get draft {
    final s = subject?.trim() ?? '';
    if (s.isEmpty || text.startsWith(s)) return text;
    if (text.isEmpty) return s;
    return '$s\n$text';
  }

  static SharedPayload? parse(Object? raw) {
    if (raw is! Map) return null;
    String? str(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    final files = <SharedFile>[
      for (final f
          in raw[AssistChannel.sharedFiles] is List
              ? raw[AssistChannel.sharedFiles] as List
              : const [])
        if (f is Map &&
            str(f[AssistChannel.filePath]) != null &&
            str(f[AssistChannel.fileName]) != null)
          SharedFile(
            path: str(f[AssistChannel.filePath])!,
            name: str(f[AssistChannel.fileName])!,
            size: (f[AssistChannel.fileSize] as num?)?.toInt() ?? 0,
          ),
    ];
    final skipped = raw[AssistChannel.sharedSkipped];
    return SharedPayload(
      text: str(raw[AssistChannel.sharedText]) ?? '',
      subject: str(raw[AssistChannel.sharedSubject]),
      files: files,
      skipped: skipped is num ? skipped.toInt() : 0,
    );
  }
}
