/// Where a tapped notification leads. Travels as the notification payload:
/// `chat:<id>`, `doc:<id>`, `file:<id>`, `table:<id>`, `memory[:<id>]` or
/// `settings:<page>`.
sealed class NotifyTarget {
  const NotifyTarget();

  String get payload;

  /// Parses a payload. A bare string is a conversation id (the payload old
  /// versions used). Anything unknown or empty gives null.
  static NotifyTarget? parse(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    final i = s.indexOf(':');
    if (i < 0) return s == 'memory' ? const MemoryTarget() : ChatTarget(s);
    final scheme = s.substring(0, i);
    final rest = s.substring(i + 1);
    switch (scheme) {
      case 'memory':
        return MemoryTarget(rest.isEmpty ? null : rest);
      case 'chat' || 'doc' || 'file' || 'table' || 'settings':
        if (rest.isEmpty) return null;
        return switch (scheme) {
          'chat' => ChatTarget(rest),
          'doc' => DocTarget(rest),
          'file' => FileTarget(rest),
          'table' => TableTarget(rest),
          _ => SettingsTarget(rest),
        };
      default:
        return null;
    }
  }
}

/// A saved chat.
final class ChatTarget extends NotifyTarget {
  const ChatTarget(this.id);
  final String id;

  @override
  String get payload => 'chat:$id';

  @override
  bool operator ==(Object other) => other is ChatTarget && other.id == id;

  @override
  int get hashCode => Object.hash('chat', id);
}

/// A generated document (opens the reader).
final class DocTarget extends NotifyTarget {
  const DocTarget(this.id);
  final String id;

  @override
  String get payload => 'doc:$id';

  @override
  bool operator ==(Object other) => other is DocTarget && other.id == id;

  @override
  int get hashCode => Object.hash('doc', id);
}

/// An uploaded file (opens the preview).
final class FileTarget extends NotifyTarget {
  const FileTarget(this.id);
  final String id;

  @override
  String get payload => 'file:$id';

  @override
  bool operator ==(Object other) => other is FileTarget && other.id == id;

  @override
  int get hashCode => Object.hash('file', id);
}

/// A round table; its answer lives in the chat of the same id.
final class TableTarget extends NotifyTarget {
  const TableTarget(this.id);
  final String id;

  @override
  String get payload => 'table:$id';

  @override
  bool operator ==(Object other) => other is TableTarget && other.id == id;

  @override
  int get hashCode => Object.hash('table', id);
}

/// The memory screen. [id] is the memory a notification just saved, so its
/// Undo button knows what to delete.
final class MemoryTarget extends NotifyTarget {
  const MemoryTarget([this.id]);
  final String? id;

  @override
  String get payload => id == null ? 'memory' : 'memory:$id';

  @override
  bool operator ==(Object other) => other is MemoryTarget && other.id == id;

  @override
  int get hashCode => Object.hash('memory', id);
}

/// A settings sub-page by its name (`apps`, `notifications`, ...).
final class SettingsTarget extends NotifyTarget {
  const SettingsTarget(this.page);
  final String page;

  @override
  String get payload => 'settings:$page';

  @override
  bool operator ==(Object other) =>
      other is SettingsTarget && other.page == page;

  @override
  int get hashCode => Object.hash('settings', page);
}
