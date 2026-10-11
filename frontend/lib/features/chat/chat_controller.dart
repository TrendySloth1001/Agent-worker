import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/haptics.dart';
import '../../core/notifications.dart';
import '../../data/ai_model.dart';
import '../../data/chat_api.dart';
import '../../data/chat_event.dart';
import '../../data/chat_message.dart';
import '../../data/conversation.dart';
import '../../data/conversations_api.dart';
import '../../data/files_api.dart';
import '../settings/settings_controller.dart';

class ChatController extends ChangeNotifier {
  ChatController(this._api, this._settings, this._conversations)
    : webSearch = _settings.defaultWebSearch,
      knowledge = _settings.defaultKnowledge,
      roundTable = _settings.defaultRoundTable {
    _lastDefaults = (_settings.defaultWebSearch, _settings.defaultKnowledge);
    _lastRoundTableDefault = _settings.defaultRoundTable;
    _settings.addListener(_onSettings);
    _notify.background.addListener(_onBackground);
  }

  final _notify = AppNotifications.instance;

  /// An ongoing progress notification is showing.
  bool _progressPosted = false;

  final ChatApi _api;
  final SettingsController _settings;
  final ConversationsApi _conversations;

  /// Saved chat id; null until the first reply is saved.
  String? conversationId;

  /// Name the server gave this chat, once it has one.
  String? title;

  /// 'fork' or 'merge' when this chat was derived from others.
  String? origin;

  /// The chat this one was forked from, if it still exists.
  String? parentId;
  String? parentTitle;

  bool get isFork => origin == ConversationSummary.originFork;

  /// Text to put in the composer (set by FORK FROM HERE).
  final draft = ValueNotifier<String?>(null);

  /// Saves run one after another so an older save never wins.
  Future<void> _saving = Future.value();

  final List<ChatMessage> messages = [];

  /// Used only to name the model under each reply; the server picks it.
  List<AiModel> models = [];
  bool webSearch;
  bool knowledge;

  /// Round Table: several models draft and cross-check, a chair answers.
  bool roundTable;

  /// True from send until the stream ends or is stopped.
  bool isSending = false;

  /// Bumped on new chat so late events from the old chat are dropped.
  int _session = 0;
  http.Client? _client;
  StreamSubscription<ChatEvent>? _sub;
  Timer? _throttle;
  bool _pending = false;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  late (bool, bool) _lastDefaults;
  late bool _lastRoundTableDefault;

  String modelName(String? id) =>
      models.where((m) => m.id == id).firstOrNull?.name ?? AppStrings.assistant;

  /// Changing a default in settings carries over to the chips.
  void _onSettings() {
    final now = (_settings.defaultWebSearch, _settings.defaultKnowledge);
    if (now.$1 != _lastDefaults.$1) webSearch = now.$1;
    if (now.$2 != _lastDefaults.$2) knowledge = now.$2;
    _lastDefaults = now;
    if (_settings.defaultRoundTable != _lastRoundTableDefault) {
      _lastRoundTableDefault = _settings.defaultRoundTable;
      roundTable = _lastRoundTableDefault;
    }
    notifyListeners();
  }

  Future<void> loadModels() async {
    try {
      models = await _api.fetchModels();
      notifyListeners();
    } catch (_) {
      // Replies fall back to a generic label until the server is reachable.
    }
  }

  void toggleWebSearch() {
    webSearch = !webSearch;
    notifyListeners();
  }

  void toggleRoundTable() {
    roundTable = !roundTable;
    notifyListeners();
  }

  void toggleKnowledge() {
    knowledge = !knowledge;
    notifyListeners();
  }

  void newChat() {
    _session++;
    _teardown();
    messages.clear();
    conversationId = null;
    title = null;
    origin = null;
    parentId = null;
    parentTitle = null;
    isSending = false;
    notifyListeners();
  }

  /// Replaces the screen with a saved chat. Returns false if it failed.
  Future<bool> open(String id) async {
    try {
      final (summary, saved) = await _conversations.get(id);
      adopt(summary, saved);
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Shows a chat the server just returned (opened, forked or merged).
  void adopt(ConversationSummary summary, List<ChatMessage> saved) {
    _session++;
    _teardown();
    isSending = false;
    messages
      ..clear()
      ..addAll(saved);
    conversationId = summary.id;
    title = summary.title;
    origin = summary.origin;
    parentId = summary.forkedFrom;
    parentTitle = summary.parentTitle;
    notifyListeners();
  }

  /// Forks the open chat up to and including [at], or up to just before it
  /// when [before], and opens the fork. Returns false on failure; null when
  /// nothing happened (busy, or nothing to fork).
  Future<bool?> fork(ChatMessage at, {bool before = false}) async {
    if (isSending) return null;
    final index = _persistable().indexOf(at);
    if (index < 0) return null;
    final keep = before ? index : index + 1;
    if (keep == 0) {
      // Nothing comes before the first message: start over with its text.
      newChat();
      draft.value = at.content;
      return true;
    }
    if (!await _flushSave()) return false;
    final id = conversationId!;
    try {
      final (summary, saved) = await _forkOrResave(id, keep);
      adopt(summary, saved);
      if (before) draft.value = at.content;
      return true;
    } on ApiException {
      return false;
    }
  }

  /// The first save may still be missing messages; save again and retry.
  Future<(ConversationSummary, List<ChatMessage>)> _forkOrResave(
    String id,
    int keep,
  ) async {
    try {
      return await _conversations.fork(id, keep);
    } on ApiException catch (e) {
      if (e.status != 404 && e.status != 400) rethrow;
      _save();
      await _saving;
      return _conversations.fork(id, keep);
    }
  }

  /// Duplicates a whole saved chat and opens the copy.
  Future<bool> forkConversation(String id, int messageCount) async {
    if (id == conversationId) {
      final last = _persistable().lastOrNull;
      if (last == null) return false;
      return await fork(last) ?? false;
    }
    if (messageCount < 1) return false;
    try {
      final (summary, saved) = await _conversations.fork(id, messageCount);
      adopt(summary, saved);
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Merges the open chat (or [baseId]) with [otherId] into a new chat and
  /// opens it.
  Future<bool> mergeWith(String otherId, {String? baseId}) async {
    final base = baseId ?? conversationId;
    if (base == null || base == otherId) return false;
    final involvesOpen = base == conversationId || otherId == conversationId;
    if (involvesOpen && !await _flushSave()) return false;
    try {
      final (summary, saved) = await _conversations.merge(base, otherId);
      adopt(summary, saved);
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Waits for pending saves and makes sure the open chat is saved.
  Future<bool> _flushSave() async {
    if (isSending) return false;
    await _saving;
    if (conversationId == null) {
      _save();
      await _saving;
    }
    return conversationId != null;
  }

  /// Called when history renames or deletes the open chat.
  void onConversationChanged(String id, {String? title, bool deleted = false}) {
    if (id != conversationId) return;
    if (deleted) {
      newChat();
    } else {
      this.title = title;
      notifyListeners();
    }
  }

  /// Messages worth saving, in order; fork points count in this list.
  List<ChatMessage> _persistable() => messages
      .where(
        (m) =>
            !m.isStreaming &&
            (m.content.trim().isNotEmpty || m.attachments.isNotEmpty),
      )
      .toList();

  /// The merge briefing, sent as background with every request.
  String? get _contextText =>
      messages.where((m) => m.role == Role.context).firstOrNull?.content;

  void _save() {
    final snapshot = _persistable();
    if (!snapshot.any((m) => m.role == Role.assistant)) return;
    final id = conversationId ??= ConversationsApi.newId();
    _saving = _saving.then((_) async {
      try {
        final summary = await _conversations.save(id, snapshot);
        if (id == conversationId && summary.title != title) {
          title = summary.title;
          notifyListeners();
        }
      } on ApiException {
        // Chat keeps working without history; the next reply retries.
      }
    });
  }

  /// Ends the stream and keeps whatever text has arrived.
  void stop() {
    if (!isSending) return;
    Haptics.tap();
    final message = messages.lastOrNull;
    _session++;
    _teardown();
    isSending = false;
    if (message != null && message.role == Role.assistant) {
      message.isStreaming = false;
      message.status = null;
      if (message.content.isEmpty) messages.remove(message);
    }
    notifyListeners();
    _save();
  }

  /// Drops the last reply and asks again.
  void regenerate() {
    if (isSending || messages.isEmpty) return;
    if (messages.last.role != Role.assistant) return;
    messages.removeLast();
    if (messages.isEmpty || messages.last.role != Role.user) {
      notifyListeners();
      return;
    }
    _run();
  }

  void send(String text, {List<FileInfo> attachments = const []}) {
    final content = text.trim();
    if ((content.isEmpty && attachments.isEmpty) || isSending) return;
    messages.add(
      ChatMessage(
        role: Role.user,
        content: content,
        attachments: List.of(attachments),
      ),
    );
    _run();
  }

  void _run({bool? roundTableOverride}) {
    final message = ChatMessage(role: Role.assistant, isStreaming: true);
    final history = _history();
    messages.add(message);
    isSending = true;
    notifyListeners();

    final session = ++_session;
    final client = http.Client();
    _client = client;

    bool alive() => session == _session;

    void finish() {
      if (!alive()) return;
      message.isStreaming = false;
      message.status = null;
      isSending = false;
      _throttle?.cancel();
      _throttle = null;
      _pending = false;
      _closeStream();
      notifyListeners();
      _save();
      _tableFinished(message);
    }

    void fail(String text) {
      if (!alive()) return;
      Haptics.error();
      if (message.content.isEmpty) {
        message.isError = true;
        message.content = text;
      } else {
        message.error = text;
      }
      finish();
    }

    void onEvent(ChatEvent event) {
      if (!alive()) return;
      switch (event) {
        case StatusEvent(:final phase):
          message.status = phase;
          notifyListeners();
        case NoticeEvent(message: final text):
          message.notice = text;
          notifyListeners();
        case SourcesEvent(:final citations):
          message.citations = citations;
          notifyListeners();
        case ImagesEvent(:final images):
          message.images = images;
        case EvidenceEvent(:final items):
          message.evidence = items;
          notifyListeners();
        case ModelEvent(:final model):
          message.modelId = model;
          notifyListeners();
        case DeltaEvent(:final text):
          message.content += text;
          _scheduleNotify();
          _tick();
        case ResetEvent():
          message.content = '';
          message.notice = null;
          notifyListeners();
        case DoneEvent(:final model, :final used):
          message.modelId = model ?? message.modelId;
          message.usedIds = used.toSet();
          Haptics.received();
          if (message.content.isEmpty) {
            fail(AppStrings.errorGeneric);
          } else {
            finish();
          }
        case ErrorEvent(message: final text):
          fail(text.isEmpty ? AppStrings.errorGeneric : text);
        case TableEvent():
          _onTable(message, event);
          notifyListeners();
        case StartEvent() || UsageEvent():
          break;
      }
    }

    _sub = _api
        .streamChat(
          client,
          history,
          webSearch: webSearch,
          knowledge: knowledge,
          mode: _settings.mode,
          profile: _settings.profileJson(),
          context: _contextText,
          roundTable: roundTableOverride ?? roundTable,
        )
        .listen(
          onEvent,
          onError: (Object error) => fail(_errorText(error)),
          onDone: () {
            if (!alive() || !isSending) return;
            // The stream closed without a done event.
            if (message.content.isEmpty) {
              fail(AppStrings.errorInterrupted);
            } else {
              message.error = AppStrings.errorInterrupted;
              finish();
            }
          },
          cancelOnError: true,
        );

    if (models.isEmpty) loadModels();
  }

  /// Cancels a running round table and asks the same question again with
  /// one model. The user message stays; the pending reply is replaced.
  void answerFast() {
    final message = messages.lastOrNull;
    if (!isSending || message == null || message.role != Role.assistant) {
      return;
    }
    _session++;
    _teardown();
    isSending = false;
    messages.remove(message);
    if (messages.isEmpty || messages.last.role != Role.user) {
      notifyListeners();
      return;
    }
    _run(roundTableOverride: false);
  }

  /// Marks [message] to raise a system notification when it is ready.
  /// Returns false when notifications are blocked.
  Future<bool> notifyWhenDone(ChatMessage message) async {
    message.notifyWhenDone = true;
    notifyListeners();
    final allowed = await _notify.ensurePermission();
    if (!allowed) {
      message.notifyWhenDone = false;
      notifyListeners();
    }
    return allowed;
  }

  /// The running round table reply, if the table is still working.
  ChatMessage? get _runningTable {
    final m = messages.lastOrNull;
    if (!isSending || m == null || m.role != Role.assistant) return null;
    final phase = m.tablePhase;
    return phase == null || phase == 'done' ? null : m;
  }

  /// Leaving the app posts a silent progress notification; coming back
  /// removes it.
  void _onBackground() {
    if (!_notify.background.value) {
      // A running table keeps its service (and notification) until done.
      if (_runningTable == null) _clearProgress();
      return;
    }
    final m = _runningTable;
    if (m != null && (_settings.notifyRoundTable || m.notifyWhenDone)) {
      _postProgress(m);
    }
  }

  void _postProgress(ChatMessage m) {
    final eta = m.tableEtaMs;
    final body = eta == null || eta <= 0
        ? TableWaitStrings.phase(m.tablePhase)
        : '${TableWaitStrings.phase(m.tablePhase)}${TableStrings.separator}'
              '${TableWaitStrings.leftLower((eta / 1000).ceil())}';
    _progressPosted = true;
    unawaited(_notify.showProgress(body, payload: conversationId));
  }

  void _clearProgress() {
    if (!_progressPosted) return;
    _progressPosted = false;
    unawaited(_notify.cancelProgress());
  }

  /// After a round table reply ends: a system notification when the app is
  /// in the background or the user asked for one.
  void _tableFinished(ChatMessage message) {
    final wasTable = message.tablePhase != null;
    _clearProgress();
    if (!wasTable) return;
    final wanted =
        message.notifyWhenDone ||
        (_settings.notifyRoundTable && _notify.background.value);
    if (!wanted) return;
    message.notifyWhenDone = false;
    final failed = message.isError || message.content.trim().isEmpty;
    final name = _notificationTitle(message);
    unawaited(
      _notify.showFinished(
        title: failed
            ? TableWaitStrings.failedTitle
            : TableWaitStrings.doneFor(name),
        body: _clip(
          failed ? (message.error ?? message.content) : _plain(message.content),
          TableMeterSizes.notifyBodyMax,
        ),
        payload: conversationId,
      ),
    );
  }

  /// The chat title, or the question while the server has not named it.
  String _notificationTitle(ChatMessage reply) {
    if (title != null && title!.trim().isNotEmpty) return title!;
    final i = messages.indexOf(reply);
    final question = i > 0 && messages[i - 1].role == Role.user
        ? messages[i - 1].content.trim()
        : '';
    return question.isEmpty
        ? TableWaitStrings.untitled
        : _clip(question, TableMeterSizes.titleMax);
  }

  /// Markdown, widget tags and citation tags stripped for a preview line.
  static String _plain(String md) => md
      .replaceAll(RegExp(r'\{\{[^}]*\}\}'), '')
      .replaceAll(RegExp(r'\[[KWDG]\d+\]'), '')
      .replaceAll(RegExp(r'[#*_`>|]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';

  /// Applies a Round Table progress event to the live panel state.
  void _onTable(ChatMessage message, TableEvent e) {
    final first = message.tablePhase == null;
    final changed = message.tablePhase != e.phase;
    message.tablePhase = e.phase;
    message.tableSeen = {...message.tableSeen, e.phase};
    if (e.elapsedMs != null) message.tableElapsedMs = e.elapsedMs!;
    if (e.etaMs != null || e.phase == 'done') message.tableEtaMs = e.etaMs;
    message.tableStamp = DateTime.now();
    if (first) {
      // The table takes a while: a nudge, and the permission prompt for the
      // finished notification comes now rather than mid-wait.
      Haptics.send();
      if (_settings.notifyRoundTable) unawaited(_notify.ensurePermission());
      // Keeps the stream alive if the user leaves the app mid-table.
      _progressPosted = true;
      unawaited(
        _notify.keepAlive(
          TableWaitStrings.phase(e.phase),
          payload: conversationId,
        ),
      );
    }
    // In the background the progress notification follows the phases.
    if (changed &&
        e.phase != 'done' &&
        _notify.background.value &&
        (_settings.notifyRoundTable || message.notifyWhenDone)) {
      _postProgress(message);
    }
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
              models.where((m) => m.id == e.model).firstOrNull?.name ??
              e.model!;
      }
      seat.status = e.status!;
      if (e.summary != null) seat.summary = e.summary!;
    } else if (e.phase == 'reviewing') {
      // The reviewer is busy, then back to its draft's state; the points
      // it raises count against the drafts they are about.
      seat.status = e.status == 'working' ? 'working' : 'done';
      for (final p in e.points) {
        final target = message.liveSeats.where((s) => s.seat == p.seat);
        for (final t in target) {
          t.objections++;
        }
      }
    }
  }

  /// Notifies at most once per throttle window while tokens arrive.
  void _scheduleNotify() {
    if (_throttle != null) {
      _pending = true;
      return;
    }
    notifyListeners();
    _throttle = Timer(AppDurations.streamThrottle, () {
      _throttle = null;
      if (_pending) {
        _pending = false;
        _scheduleNotify();
      }
    });
  }

  /// A soft pulse, rate limited so it never fires per token.
  void _tick() {
    final now = DateTime.now();
    if (now.difference(_lastTick) < AppDurations.streamTick) return;
    _lastTick = now;
    Haptics.tick();
  }

  void _teardown() {
    _clearProgress();
    _throttle?.cancel();
    _throttle = null;
    _pending = false;
    _closeStream();
  }

  /// Cancels the stream, then drops the connection. Errors raised by the
  /// closed connection are expected and ignored.
  void _closeStream() {
    final sub = _sub;
    final client = _client;
    _sub = null;
    _client = null;
    if (sub != null) unawaited(sub.cancel().catchError((Object _) {}));
    client?.close();
  }

  /// Last messages that fit the server limits, starting with a user turn.
  List<ChatMessage> _history() {
    final items = messages
        .where(
          (m) =>
              m.role != Role.context &&
              !m.isError &&
              (m.content.trim().isNotEmpty || m.attachments.isNotEmpty),
        )
        .toList();
    final budget = AppSizes.maxHistoryChars - (_contextText?.length ?? 0);
    var start = items.length > AppSizes.maxHistoryMessages
        ? items.length - AppSizes.maxHistoryMessages
        : 0;
    var chars = items.skip(start).fold<int>(0, (n, m) => n + m.content.length);
    while (start < items.length - 1 && chars > budget) {
      chars -= items[start].content.length;
      start++;
    }
    while (start < items.length - 1 && items[start].role != Role.user) {
      start++;
    }
    return items.sublist(start);
  }

  String _errorText(Object error) {
    if (error is ApiException) return error.message;
    if (error is TimeoutException) return AppStrings.errorTimeout;
    return AppStrings.errorNetwork;
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    _notify.background.removeListener(_onBackground);
    _teardown();
    draft.dispose();
    super.dispose();
  }
}
