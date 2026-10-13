/// A saved chat as listed in history.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.messageCount,
    required this.updatedAt,
    this.pinned = false,
    this.archived = false,
    this.origin,
    this.forkedFrom,
    this.parentTitle,
    this.snippet,
  });

  final String id;

  /// Null until the server has named it.
  final String? title;
  final String preview;
  final int messageCount;
  final DateTime updatedAt;
  final bool pinned;
  final bool archived;

  /// 'fork' or 'merge' for derived chats, else null.
  final String? origin;

  /// Chat this one was forked from; null if not a fork or it was deleted.
  final String? forkedFrom;
  final String? parentTitle;

  /// Excerpt of the message that matched a search (only in search results).
  final String? snippet;

  bool get isFork => origin == originFork;
  bool get isMerge => origin == originMerge;

  /// Saved from the assistant overlay.
  bool get isAssistant => origin == originAssistant;

  static const originFork = 'fork';
  static const originMerge = 'merge';
  static const originAssistant = 'assistant';

  factory ConversationSummary.fromJson(Map<String, dynamic> j) =>
      ConversationSummary(
        id: j['id'] as String,
        title: j['title'] as String?,
        preview: j['preview'] as String? ?? '',
        messageCount: j['messageCount'] as int? ?? 0,
        updatedAt:
            DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        pinned: j['pinned'] as bool? ?? false,
        archived: j['archived'] as bool? ?? false,
        origin: j['origin'] as String?,
        forkedFrom: j['forkedFrom'] as String?,
        parentTitle:
            (j['parent'] as Map<String, dynamic>?)?['title'] as String?,
        snippet: j['snippet'] as String?,
      );
}
