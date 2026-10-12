import 'package:http/http.dart' as http;

import '../../core/constants/smart_toggles.dart';
import '../../data/ai_model.dart';
import '../../data/chat_api.dart';
import '../../data/chat_event.dart';
import '../../data/chat_message.dart';
import '../../data/docs_api.dart';
import '../../data/files_api.dart';
import '../settings/settings_controller.dart';

/// What one chat turn asks of the server besides the history. Built the same
/// way by the app's chat and the assistant overlay, so both send the same
/// flags (web, KB, Round Table, smart suggestions, model, reply style and
/// profile) for the same settings and toggles.
class ChatTurn {
  const ChatTurn({
    this.modelId,
    required this.webMode,
    required this.knowledge,
    required this.mode,
    this.profile = const {},
    this.context,
    this.roundTable = false,
    this.conversationId,
    this.smartSuggestions = true,
    this.suppressSuggest = const {},
    this.apps = const [],
  });

  /// The turn for [settings] with the composer's toggles.
  factory ChatTurn.of(
    SettingsController settings, {
    required List<AiModel> models,
    required WebMode webMode,
    required bool knowledge,
    required bool roundTable,
    String? context,
    String? conversationId,
    Set<SuggestKind> suppressSuggest = const {},
    List<Map<String, String>> apps = const [],
  }) => ChatTurn(
    modelId: requestedModel(settings, models),
    webMode: webMode,
    knowledge: knowledge,
    mode: settings.mode,
    profile: settings.profileJson(),
    context: context,
    roundTable: roundTable,
    conversationId: conversationId,
    smartSuggestions: settings.smartSuggestions,
    suppressSuggest: Set.of(suppressSuggest),
    apps: apps,
  );

  final String? modelId;
  final WebMode webMode;
  final bool knowledge;
  final String mode;
  final Map<String, String> profile;
  final String? context;
  final bool roundTable;
  final String? conversationId;
  final bool smartSuggestions;
  final Set<SuggestKind> suppressSuggest;
  final List<Map<String, String>> apps;

  /// The model picked in Settings, only if the server still offers it
  /// (else Auto: the server routes).
  static String? requestedModel(
    SettingsController settings,
    List<AiModel> models,
  ) {
    final id = settings.modelId;
    return id != null && models.any((m) => m.id == id) ? id : null;
  }

  /// The WEB chip a new chat starts with.
  static WebMode defaultWeb(SettingsController s) =>
      s.defaultWebSearch ? WebMode.auto : WebMode.off;

  /// Streams the reply. [screen] is the overlay's shared screen.
  Stream<ChatEvent> stream(
    ChatApi api,
    http.Client client,
    List<ChatMessage> history, {
    Map<String, Object>? screen,
  }) => api.streamChat(
    client,
    history,
    modelId: modelId,
    webMode: webMode,
    knowledge: knowledge,
    mode: mode,
    profile: profile,
    context: context,
    roundTable: roundTable,
    conversationId: conversationId,
    smartSuggestions: smartSuggestions,
    suppressSuggest: suppressSuggest,
    apps: apps,
    screen: screen,
  );

  /// DOC: the document request for [prompt] with the same toggles.
  static DocRequest docRequest(
    SettingsController settings, {
    required String prompt,
    required String conversationId,
    required String length,
    required WebMode webMode,
    required bool knowledge,
    List<FileInfo> attachments = const [],
  }) => DocRequest(
    prompt: prompt,
    conversationId: conversationId,
    length: length,
    webSearch: webMode != WebMode.off,
    knowledge: knowledge,
    attachments: [for (final a in attachments) a.id],
    profile: settings.profileJson(),
  );
}

/// Applies a Round Table progress event to [message] (phases, seats,
/// research, the final transcript). Shared by the chat and the overlay.
void applyTableEvent(ChatMessage message, TableEvent e, List<AiModel> models) {
  message.tablePhase = e.phase;
  message.tableSeen = {...message.tableSeen, e.phase};
  if (e.elapsedMs != null) message.tableElapsedMs = e.elapsedMs!;
  if (e.etaMs != null || e.phase == 'done') message.tableEtaMs = e.etaMs;
  message.tableStamp = DateTime.now();
  if (e.phase == 'researching') {
    if (e.research.isNotEmpty) message.tableResearch = e.research;
    return;
  }
  if (e.phase == 'seating') {
    // Seating carries the searches that succeeded; failed ones are dropped.
    message.liveSeats = [for (final s in e.seats) s..status = 'working'];
    return;
  }
  if (e.phase == 'done') {
    message.table = e.transcript;
    return;
  }
  final seat = message.liveSeats.where((s) => s.seat == e.seat).firstOrNull;
  if (seat == null || e.status == null) return;
  if (e.phase == 'drafting') {
    if (e.model != null && e.model != seat.model) {
      seat
        ..model = e.model!
        ..name =
            models.where((m) => m.id == e.model).firstOrNull?.name ?? e.model!;
    }
    seat.status = e.status!;
    if (e.summary != null) seat.summary = e.summary!;
  } else if (e.phase == 'reviewing') {
    // The reviewer is busy, then back to its draft's state; the points it
    // raises count against the drafts they are about.
    seat.status = e.status == 'working' ? 'working' : 'done';
    for (final p in e.points) {
      final target = message.liveSeats.where((s) => s.seat == p.seat);
      for (final t in target) {
        t.objections++;
      }
    }
  }
}
