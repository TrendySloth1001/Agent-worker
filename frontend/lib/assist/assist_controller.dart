import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/constants/app_sizes.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/assist.dart';
import '../core/constants/docs.dart';
import '../core/constants/smart_toggles.dart';
import '../core/constants/suggest.dart';
import '../core/haptics.dart';
import '../data/ai_model.dart';
import '../data/chat_api.dart';
import '../data/chat_event.dart';
import '../data/chat_message.dart';
import '../data/conversations_api.dart';
import '../data/doc_models.dart';
import '../data/docs_api.dart';
import '../features/auth/auth_controller.dart';
import '../features/chat/attachments_controller.dart';
import '../features/chat/chat_turn.dart';
import '../features/docs/doc_registry.dart';
import '../features/settings/settings_controller.dart';
import 'assist_bridge.dart';
import 'screen_text.dart';

/// "Share screen with sparky": nothing yet, reading, shared, or nothing to read.
enum ScreenShare { none, loading, shared, empty }

/// The overlay's state: one short conversation, the shared screen, and the
/// hand-off to the app. Nothing is saved unless the user opens it in sparky.
///
/// Asks like the app's chat: the same request ([ChatTurn]) with the same
/// toggles (WEB / KB / TABLE / DOC), smart suggestions, model and reply
/// style, so web search, the knowledge base, memory, connected apps and
/// Round Table all work here too.
class AssistController extends ChangeNotifier {
  AssistController({
    required this.bridge,
    required this.api,
    required this.conversations,
    required SettingsController settings,
    AttachmentsController? attachments,
    AuthController? auth,
    DocsApi? docs,
  }) : _settings = settings,
       _auth = auth ?? AuthController.instance,
       _docsOverride = docs,
       attachments = attachments ?? AttachmentsController() {
    _resetToggles();
  }

  final DocsApi? _docsOverride;
  DocsApi get _docs => _docsOverride ?? DocRegistry.instance.api;

  final AuthController _auth;

  /// Bumped on every new opening (the UI clears its field).
  int generation = 0;

  final AssistBridge bridge;
  final ChatApi api;
  final ConversationsApi conversations;
  final AttachmentsController attachments;
  SettingsController _settings;

  SettingsController get settings => _settings;

  /// The app's settings changed while the overlay engine kept running.
  set settings(SettingsController next) {
    _settings = next;
    // Nothing asked yet: start from the (possibly changed) defaults.
    if (!hasThread) _resetToggles();
    notifyListeners();
  }

  // ---- toggles (same as the app's composer) --------------------------------

  /// WEB chip: auto (the server decides), on or off.
  WebMode webMode = WebMode.auto;
  bool knowledge = false;

  /// Round Table: several models draft and cross-check, a chair answers.
  bool roundTable = false;

  /// DOC: the next question is written as a long-form document.
  bool doc = false;
  String docLength = DocConfig.defaultLength;

  /// What the server suggested for the latest reply (Use KB? / Write as Doc?).
  SuggestToggleEvent? suggestion;

  /// Kinds already suggested in this opening: never asked twice.
  final Set<SuggestKind> _suppressed = {};

  /// Offered models, to send the Settings model only while it exists.
  List<AiModel> models = [];

  void _resetToggles() {
    webMode = ChatTurn.defaultWeb(_settings);
    knowledge = _settings.defaultKnowledge;
    roundTable = _settings.defaultRoundTable;
    doc = false;
    docLength = DocConfig.defaultLength;
    suggestion = null;
    _suppressed.clear();
  }

  void cycleWebMode() {
    webMode = webMode.next;
    notifyListeners();
  }

  void toggleKnowledge() {
    knowledge = !knowledge;
    notifyListeners();
  }

  void toggleRoundTable() {
    roundTable = !roundTable;
    notifyListeners();
  }

  void toggleDoc() {
    doc = !doc;
    notifyListeners();
  }

  Future<void> loadModels() async {
    if (models.isNotEmpty) return;
    try {
      models = await api.fetchModels();
    } catch (_) {
      // Auto until the server is reachable (the app does the same).
    }
  }

  /// "Not now": the prompt goes away for this opening.
  void dismissSuggestion() {
    final s = suggestion;
    if (s == null) return;
    suggestion = null;
    unawaited(
      api.reportSuggestion(s.kind, 'dismissed', conversationId: conversationId),
    );
    notifyListeners();
  }

  /// "Use KB" asks again with the KB on; "Write as Doc" turns the question
  /// into a document. The reply is replaced, like in the app.
  void acceptSuggestion() {
    final s = suggestion;
    if (s == null) return;
    suggestion = null;
    unawaited(
      api.reportSuggestion(s.kind, 'accepted', conversationId: conversationId),
    );
    if (sending) _cancelStream();
    if (messages.lastOrNull?.role == Role.assistant) messages.removeLast();
    final last = messages.lastOrNull;
    if (last == null || last.role != Role.user) {
      notifyListeners();
      return;
    }
    switch (s.kind) {
      case SuggestKind.kb:
        knowledge = true;
        _run();
      case SuggestKind.doc:
        _sendDoc(last);
    }
  }

  /// Round Table taking too long: one model answers instead.
  void answerFast() {
    final reply = messages.lastOrNull;
    if (!sending || reply == null || reply.role != Role.assistant) return;
    _cancelStream();
    messages.remove(reply);
    if (messages.lastOrNull?.role != Role.user) {
      notifyListeners();
      return;
    }
    _run(roundTableOverride: false);
  }

  /// A short message above the pill (attachment problems and the like).
  void say(String text) => _setNotice(text);

  AssistShow show = const AssistShow(source: AssistSource.assist);

  /// Questions and answers of this opening, oldest first.
  final List<ChatMessage> messages = [];

  bool sending = false;

  /// Waiting for a photo to finish uploading before the question goes out.
  bool waitingUploads = false;

  ScreenShare share = ScreenShare.none;
  ScreenContext? screen;

  /// One line under the pill (e.g. how to allow screenshots).
  String? notice;

  /// The notice can open the system's assistant settings.
  bool noticeOpensSettings = false;

  /// Saving the chat for "Open in sparky".
  bool opening = false;

  /// The id this chat gets when it is opened in the app.
  String? conversationId;

  PendingAttachment? _screenshot;
  int _session = 0;
  http.Client? _client;
  StreamSubscription<ChatEvent>? _sub;
  Timer? _throttle;
  bool _dirty = false;

  bool get hasThread => messages.isNotEmpty;

  /// The screen can be shared in this opening (the session saw one).
  bool get canShare => show.source == AssistSource.session && show.screen;

  /// The latest answer, once it has text.
  ChatMessage? get lastAnswer {
    final m = messages.lastOrNull;
    return m != null && m.role == Role.assistant && m.content.isNotEmpty
        ? m
        : null;
  }

  bool get streaming => messages.lastOrNull?.isStreaming ?? false;

  /// A fresh opening: drop the previous conversation and screen.
  void reset(AssistShow next) {
    _cancelStream();
    generation++;
    show = next;
    messages.clear();
    sending = false;
    waitingUploads = false;
    share = ScreenShare.none;
    screen = null;
    notice = null;
    noticeOpensSettings = false;
    opening = false;
    conversationId = null;
    _screenshot = null;
    for (final a in List.of(attachments.items)) {
      attachments.remove(a);
    }
    _resetToggles();
    notifyListeners();
    unawaited(loadModels());
  }

  // ---- screen --------------------------------------------------------------

  /// Reads the screen the session saw. Only ever called from the chip.
  Future<void> shareScreen() async {
    if (!canShare || share == ScreenShare.loading) return;
    Haptics.tap();
    final session = _session;
    share = ScreenShare.loading;
    notice = null;
    notifyListeners();
    final ctx = await bridge.screenContext();
    if (session != _session || share != ScreenShare.loading) return;
    if (ctx == null || ctx.isEmpty) {
      share = ScreenShare.empty;
      screen = null;
      _setNotice(AssistStrings.screenNothing, settings: true);
      Haptics.error();
      return;
    }
    screen = ctx;
    share = ScreenShare.shared;
    if (ctx.hasScreenshot) {
      _attachScreenshot(ctx.screenshotPath!);
      notice = null;
    } else {
      _setNotice(AssistStrings.screenTextOnly, settings: true);
    }
    Haptics.received();
    notifyListeners();
  }

  void unshare() {
    Haptics.tap();
    final shot = _screenshot;
    if (shot != null && attachments.items.contains(shot)) {
      attachments.remove(shot);
    }
    _screenshot = null;
    screen = null;
    share = ScreenShare.none;
    notice = null;
    notifyListeners();
  }

  void _attachScreenshot(String path) {
    try {
      attachments.add([pickedFile(path, AssistConfig.screenshotName)]);
      _screenshot = attachments.items.lastOrNull;
    } catch (_) {
      // Text still goes; the picture is a bonus.
    }
  }

  void _setNotice(String text, {bool settings = false}) {
    notice = text;
    noticeOpensSettings = settings;
    notifyListeners();
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  // ---- asking --------------------------------------------------------------

  bool canSend(String text) =>
      !sending &&
      (text.trim().isNotEmpty ||
          attachments.hasUploaded ||
          attachments.uploading);

  /// Sends [text] with the photos in the pill (and the shared screen).
  Future<bool> send(String text) async {
    if (!canSend(text)) return false;
    final content = text.trim();
    final session = _session;
    sending = true;
    waitingUploads = attachments.uploading;
    notice = null;
    notifyListeners();
    // Opened right after the engine started: the session may still load.
    if (!await _signedIn() || session != _session) {
      sending = false;
      notifyListeners();
      return false;
    }
    final files = await attachments.settle();
    if (session != _session) return false;
    waitingUploads = false;
    if (files == null) {
      sending = false;
      Haptics.error();
      _setNotice(AssistStrings.attachFailed);
      return false;
    }
    if (content.isEmpty && files.isEmpty) {
      sending = false;
      notifyListeners();
      return false;
    }
    Haptics.send();
    attachments.clearSent();
    _screenshot = null;
    conversationId ??= ConversationsApi.newId();
    final question = ChatMessage(
      role: Role.user,
      content: content,
      attachments: files,
    );
    messages.add(question);
    if (doc) {
      _sendDoc(question);
    } else {
      _run();
    }
    return true;
  }

  /// DOC: [question] becomes a document (POST /docs) that keeps being written
  /// on the server; the reply is its card, opened in the app.
  Future<void> _sendDoc(ChatMessage question) async {
    final reply = ChatMessage(role: Role.assistant, isStreaming: true)
      ..status = 'queued';
    messages.add(reply);
    sending = true;
    notifyListeners();
    final session = ++_session;
    final chatId = conversationId ??= ConversationsApi.newId();
    try {
      final id = await _docs.create(
        ChatTurn.docRequest(
          settings,
          prompt: question.content,
          conversationId: chatId,
          length: docLength,
          webMode: webMode,
          knowledge: knowledge,
          attachments: question.attachments,
        ),
      );
      if (session != _session) return;
      final card = Doc(
        id: id,
        prompt: question.content,
        conversationId: chatId,
      );
      reply
        ..isStreaming = false
        ..status = null
        ..content = DocStrings.messageText(card.title)
        ..meta = {...reply.meta, 'doc': card.toMeta()};
      Haptics.send();
    } catch (e) {
      if (session != _session) return;
      Haptics.error();
      reply
        ..isStreaming = false
        ..status = null
        ..isError = true
        ..content = e is ApiException ? e.message : DocStrings.startFailed;
    }
    sending = false;
    notifyListeners();
  }

  void _run({bool? roundTableOverride}) {
    final reply = ChatMessage(role: Role.assistant, isStreaming: true);
    final history = [
      for (final m in messages)
        if (!m.isStreaming &&
            !m.isError &&
            (m.content.trim().isNotEmpty || m.attachments.isNotEmpty))
          m,
    ];
    messages.add(reply);
    sending = true;
    notifyListeners();

    final session = ++_session;
    final client = http.Client();
    _client = client;
    final s = settings;
    suggestion = null;

    void finish() {
      if (session != _session) return;
      reply.isStreaming = false;
      reply.status = null;
      sending = false;
      _throttle?.cancel();
      _throttle = null;
      _closeStream();
      notifyListeners();
    }

    void fail(String text) {
      if (session != _session) return;
      Haptics.error();
      if (reply.content.isEmpty) {
        reply.isError = true;
        reply.content = text;
      } else {
        reply.error = text;
      }
      finish();
    }

    void onEvent(ChatEvent event) {
      if (session != _session) return;
      switch (event) {
        case StatusEvent(:final phase):
          reply.status = phase;
          notifyListeners();
        case NoticeEvent(message: final text):
          reply.notice = text;
          notifyListeners();
        case SourcesEvent(:final citations):
          reply.citations = citations;
          notifyListeners();
        case ImagesEvent(:final images):
          reply.images = images;
        case EvidenceEvent(:final items):
          reply.evidence = items;
        case final SuggestToggleEvent e:
          if (s.smartSuggestions) {
            suggestion = e;
            _suppressed.add(e.kind);
            notifyListeners();
          }
        case ToolsEvent(:final web, :final auto):
          if (web && auto) {
            reply.meta = {...reply.meta, SmartConfig.searchedKey: true};
            notifyListeners();
          }
        case SuggestionsEvent(:final items):
          reply.meta = {...reply.meta, SuggestConfig.followUpKey: items};
        case MemoryEvent(:final ops):
          reply.memoryOps = ops;
          notifyListeners();
        case TableEvent():
          if (reply.tablePhase == null) Haptics.send();
          applyTableEvent(reply, event, models);
          notifyListeners();
        case ModelEvent(:final model):
          reply.modelId = model;
        case DeltaEvent(:final text):
          reply.content += text;
          _scheduleNotify();
        case ResetEvent():
          reply.content = '';
          reply.notice = null;
          notifyListeners();
        case DoneEvent(:final model, :final used):
          reply.modelId = model ?? reply.modelId;
          reply.usedIds = used.toSet();
          Haptics.received();
          if (reply.content.isEmpty) {
            fail(AssistStrings.answerFailed);
          } else {
            finish();
          }
        case ErrorEvent(message: final text):
          fail(text.isEmpty ? AssistStrings.answerFailed : text);
        default:
          break;
      }
    }

    _sub =
        ChatTurn.of(
              s,
              models: models,
              webMode: webMode,
              knowledge: knowledge,
              roundTable: roundTableOverride ?? roundTable,
              conversationId: conversationId,
              suppressSuggest: _suppressed,
            )
            .stream(api, client, history, screen: screen?.toJson())
            .listen(
              onEvent,
              onError: (Object error) {
                if (session != _session) return;
                fail(_errorText(error));
              },
              onDone: () {
                if (session != _session || !reply.isStreaming) return;
                if (reply.content.isEmpty) {
                  fail(AppStrings.errorInterrupted);
                } else {
                  reply.error = AppStrings.errorInterrupted;
                  finish();
                }
              },
              cancelOnError: true,
            );
  }

  Future<bool> _signedIn() async {
    if (_auth.status != AuthStatus.restoring) return _auth.signedIn;
    final done = Completer<void>();
    void check() {
      if (_auth.status != AuthStatus.restoring && !done.isCompleted) {
        done.complete();
      }
    }

    _auth.addListener(check);
    try {
      await done.future.timeout(AssistConfig.authWait, onTimeout: () {});
    } finally {
      _auth.removeListener(check);
    }
    return _auth.signedIn;
  }

  static String _errorText(Object error) {
    if (error is ApiException) return error.message;
    if (error is TimeoutException) return AppStrings.errorTimeout;
    return AppStrings.errorNetwork;
  }

  /// Text arrives in many small pieces; redraw at most every few frames.
  void _scheduleNotify() {
    if (_throttle != null) {
      _dirty = true;
      return;
    }
    notifyListeners();
    _throttle = Timer(AppDurations.streamThrottle, () {
      _throttle = null;
      if (_dirty) {
        _dirty = false;
        notifyListeners();
      }
    });
  }

  /// Stops the answer and keeps what arrived.
  void stop() {
    final reply = messages.lastOrNull;
    if (!sending || reply == null) return;
    Haptics.tap();
    _cancelStream();
    if (reply.role == Role.assistant) {
      reply.isStreaming = false;
      reply.status = null;
      if (reply.content.isEmpty) messages.remove(reply);
    }
    notifyListeners();
  }

  void _cancelStream() {
    _session++;
    _throttle?.cancel();
    _throttle = null;
    _dirty = false;
    _closeStream();
    sending = false;
  }

  void _closeStream() {
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }

  // ---- actions -------------------------------------------------------------

  Future<void> copyAnswer() async {
    final a = lastAnswer;
    if (a == null) return;
    Haptics.tap();
    await Clipboard.setData(ClipboardData(text: a.content));
  }

  /// Saves this chat like the app does and opens it there; with no chat,
  /// just opens the app.
  Future<bool> openInSparky() async {
    if (opening) return false;
    Haptics.tap();
    final saved = [
      for (final m in messages)
        if (!m.isStreaming &&
            (m.content.trim().isNotEmpty || m.attachments.isNotEmpty))
          m,
    ];
    if (!saved.any((m) => m.role == Role.assistant)) {
      return bridge.openApp();
    }
    if (streaming) stop();
    opening = true;
    notice = null;
    notifyListeners();
    final id = conversationId ??= ConversationsApi.newId();
    try {
      await conversations.save(id, saved);
    } catch (_) {
      opening = false;
      Haptics.error();
      _setNotice(AssistStrings.openFailed);
      return false;
    }
    final ok = await bridge.openApp('${AssistConfig.chatLinkPrefix}$id');
    opening = false;
    if (!ok) _setNotice(AssistStrings.openFailed);
    notifyListeners();
    return ok;
  }

  Future<void> close() async {
    Haptics.tap();
    _cancelStream();
    await bridge.close();
  }

  @override
  void dispose() {
    _cancelStream();
    attachments.dispose();
    super.dispose();
  }
}
