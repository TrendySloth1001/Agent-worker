import '../core/constants/app_files.dart';
import 'chat_event.dart';
import 'files_api.dart';

/// [context] is a merged-chat briefing: shown as a card and sent as
/// background, never as a turn.
enum Role { user, assistant, context }

class ChatMessage {
  ChatMessage({
    required this.role,
    this.content = '',
    this.modelId,
    this.isError = false,
    this.isStreaming = false,
    this.attachments = const [],
  });

  final Role role;

  /// Files the user attached (user messages only).
  List<FileInfo> attachments;

  /// Grows while an assistant reply streams in.
  String content;

  /// Which model wrote this reply.
  String? modelId;
  bool isError;
  bool isStreaming;

  /// Sources sent before the first token, shown under the reply.
  List<Citation> citations = const [];

  /// Pictures that help explain the reply.
  List<ImageRef> images = const [];

  /// Passages that back individual sentences of the reply.
  List<Evidence> evidence = const [];

  /// Tags the final text actually cites, e.g. `W1`.
  Set<String> usedIds = const {};

  /// Backend phase while waiting: queued, searching, retrieving, generating.
  String? status;

  /// Latest non-fatal notice from the server.
  String? notice;

  /// Failure after some text arrived; the partial text is kept.
  String? error;

  /// The stream broke and the automatic retries were spent: the answer shows
  /// "Answer interrupted · Retry" (calm, never an error line). Not saved.
  bool interrupted = false;

  /// Extra saved data, e.g. a merge briefing's sources.
  Map<String, dynamic> meta = const {};

  /// Round Table record for a reply the table wrote; saved with it.
  TableTranscript? table;

  /// Live Round Table seats while the table works (not saved).
  List<TableSeat> liveSeats = const [];

  /// Live Round Table phase (not saved).
  String? tablePhase;

  /// Live Round Table timing (not saved): elapsed and estimated time left
  /// as of [tableStamp], when the last table event arrived.
  int tableElapsedMs = 0;
  int? tableEtaMs;
  DateTime? tableStamp;

  /// Live planned searches per seat letter (not saved).
  Map<String, List<String>> tableResearch = const {};

  /// Phases this table went through, for the progress meter (not saved).
  Set<String> tableSeen = {};

  /// Long-term memory ops this turn caused: ADD, UPDATE, DELETE (not saved).
  List<String> memoryOps = const [];

  /// The user asked to be notified when this reply is ready (not saved).
  bool notifyWhenDone = false;

  Map<String, dynamic> toJson() {
    final live = [
      for (final a in attachments)
        if (!a.deleted) a.id,
    ];
    // Only deleted files and no text: the server needs some content.
    final gone = content.isEmpty && attachments.isNotEmpty && live.isEmpty;
    return {
      'role': role.name,
      'content': gone ? AppFiles.deletedHistoryText : content,
      if (role == Role.user && live.isNotEmpty) 'attachments': live,
    };
  }

  /// Everything needed to restore the message from saved history.
  Map<String, dynamic> toStorageJson() => {
    'role': role.name,
    'content': content.isEmpty && error != null ? error : content,
    'model': modelId,
    'citations': [for (final c in citations) c.toJson()],
    'usedIds': usedIds.toList(),
    'isError': isError,
    'images': [for (final i in images) i.toJson()],
    'evidence': [for (final e in evidence) e.toJson()],
    if (attachments.isNotEmpty)
      'attachments': [for (final a in attachments) a.toStorageJson()],
    if (meta.isNotEmpty) 'meta': meta,
    if (table != null) 'table': table!.toJson(),
  };

  factory ChatMessage.fromStorageJson(Map<String, dynamic> j) =>
      ChatMessage(
          role: Role.values.asNameMap()[j['role']] ?? Role.assistant,
          content: j['content'] as String? ?? '',
          modelId: j['model'] as String?,
          isError: j['isError'] as bool? ?? false,
        )
        ..attachments = [
          for (final a in j['attachments'] as List? ?? const [])
            if (a is Map<String, dynamic>) FileInfo.fromJson(a),
        ]
        ..citations = [
          for (final c in j['citations'] as List? ?? const [])
            Citation.fromJson(c as Map<String, dynamic>),
        ]
        ..images = [
          for (final i in j['images'] as List? ?? const [])
            ImageRef.fromJson(i as Map<String, dynamic>),
        ]
        ..evidence = [
          for (final e in j['evidence'] as List? ?? const [])
            Evidence.fromJson(e as Map<String, dynamic>),
        ]
        ..usedIds = {
          for (final id in j['usedIds'] as List? ?? const []) id as String,
        }
        ..meta = j['meta'] is Map<String, dynamic>
            ? j['meta'] as Map<String, dynamic>
            : const {}
        ..table = j['table'] is Map<String, dynamic>
            ? TableTranscript.fromJson(j['table'] as Map<String, dynamic>)
            : null;
}
