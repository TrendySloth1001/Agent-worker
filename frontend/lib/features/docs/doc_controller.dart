import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/docs.dart';
import '../../core/haptics.dart';
import '../../data/chat_api.dart';
import '../../data/doc_models.dart';
import '../../data/docs_api.dart';
import '../chat/widgets/markdown/inline_image.dart';

/// Repaints one section only (the streaming one), never the whole reader.
class _Tick extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Live state of one document: attaches to its event stream (reconnecting
/// with a fresh snapshot when it drops), applies events, and runs the
/// section actions. Structural changes notify this controller; streamed
/// text only notifies the section's [sectionListenable].
class DocController extends ChangeNotifier {
  DocController(this.id, {DocsApi? api, Doc? seed})
    : _api = api ?? DocsApi(),
      doc = seed ?? Doc(id: id);

  final String id;
  final DocsApi _api;
  Doc doc;

  /// A snapshot (or GET) has arrived.
  bool loaded = false;

  /// The event stream is open.
  bool get attached => _sub != null;

  /// Waiting to reconnect after the stream dropped.
  bool reconnecting = false;

  /// Could not load the doc at all.
  String? loadError;

  List<DocHighlight> highlights = const [];

  final _ticks = <String, _Tick>{};
  final _rewriting = <String>{};
  final _dirty = <String>{};
  StreamSubscription<DocEvent>? _sub;
  Timer? _retry;
  Timer? _flush;
  int _attempt = 0;
  bool _disposed = false;
  bool _wantAttached = false;

  /// Notifies when [sectionId]'s text or status changes.
  Listenable sectionListenable(String sectionId) =>
      _ticks.putIfAbsent(sectionId, _Tick.new);

  bool isRewriting(String sectionId) => _rewriting.contains(sectionId);

  // ---- connection -----------------------------------------------------------

  /// Opens the event stream (idempotent).
  void attach() {
    _wantAttached = true;
    if (_sub != null || _retry != null || _disposed) return;
    _connect();
  }

  /// Closes the event stream; state stays.
  void detach() {
    _wantAttached = false;
    _retry?.cancel();
    _retry = null;
    reconnecting = false;
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel().catchError((Object _) {}));
  }

  void _connect() {
    _retry = null;
    _sub = _api
        .events(id)
        .listen(
          (e) {
            _attempt = 0;
            if (reconnecting) {
              reconnecting = false;
              _notify();
            }
            apply(e);
          },
          onError: (Object e) => _dropped(e),
          onDone: () => _dropped(null),
          cancelOnError: true,
        );
  }

  void _dropped(Object? error) {
    _sub = null;
    if (_disposed || !_wantAttached) return;
    if (loaded && !doc.isRunning) {
      _wantAttached = false;
      return;
    }
    // A 4xx (gone, not allowed) will not get better by retrying.
    final fatal = error is ApiException && (error.status ?? 0) < 500;
    if (!fatal && _attempt < DocConfig.reconnectDelays.length) {
      reconnecting = true;
      _retry = Timer(DocConfig.reconnectDelays[_attempt++], _connect);
      _notify();
      return;
    }
    reconnecting = false;
    if (!loaded) unawaited(refresh(error: error));
    _notify();
  }

  /// Loads the doc with GET (no stream).
  Future<void> refresh({Object? error}) async {
    try {
      _replace(await _api.get(id));
      loadError = null;
    } catch (e) {
      if (!loaded) {
        loadError = e is ApiException ? e.message : DocStrings.loadFailed;
      }
    }
    _notify();
  }

  // ---- events ----------------------------------------------------------------

  /// Applies one server event. Public for tests and for rewrite streams.
  void apply(DocEvent e, {bool fromRewrite = false}) {
    if (_disposed) return;
    if (e is DocSectionEvent &&
        !fromRewrite &&
        _rewriting.contains(e.sectionId)) {
      // The rewrite's own stream carries this section.
      return;
    }
    switch (e) {
      case DocSnapshotEvent(doc: final snap):
        _replace(snap);
        if (!snap.isRunning) {
          // Nothing more will come: keep the state, drop the connection.
          final sub = _sub;
          _sub = null;
          _wantAttached = false;
          if (sub != null) unawaited(sub.cancel().catchError((Object _) {}));
        }
      case DocStatusEvent():
        doc.applyProgress({
          'phase': e.phase,
          'done': ?e.done,
          'total': ?e.total,
          'elapsedMs': ?e.elapsedMs,
          'etaMs': e.etaMs,
        });
        final status = e.status ?? _statusFor(e.phase);
        if (status != null && (doc.isRunning || e.status != null)) {
          doc.status = status;
        }
      case DocOutlineEvent():
        _outline(e);
      case DocSourcesEvent(:final citations):
        final known = {for (final c in doc.sources) c.id};
        doc.sources = [
          ...doc.sources,
          for (final c in citations)
            if (known.add(c.id)) c,
        ];
        _bumpAll();
      case DocSectionStartEvent():
        final s = _section(e.sectionId);
        s.status = DocSectionStatus.writing;
        s.markdown = '';
        s.error = null;
        if (e.model != null) s.model = e.model;
        if (e.sourceIds.isNotEmpty) s.sourceIds = e.sourceIds;
        if (doc.status == DocStatus.planning ||
            doc.status == DocStatus.researching) {
          doc.status = DocStatus.writing;
        }
        _bump(s.id);
      case DocSectionDeltaEvent():
        final s = _section(e.sectionId);
        final wasWriting = s.isWriting;
        s.status = DocSectionStatus.writing;
        s.markdown += e.text;
        if (!wasWriting) {
          _bump(s.id);
        } else {
          _schedule(s.id);
          return; // Only the section repaints.
        }
      case DocSectionResetEvent():
        final s = _section(e.sectionId);
        s.markdown = '';
        _bump(s.id);
      case DocSectionDoneEvent():
        final s = _section(e.sectionId);
        if (e.markdown.isNotEmpty) s.markdown = e.markdown;
        s.status = DocSectionStatus.done;
        s.words = e.words > 0 ? e.words : countWords(s.markdown);
        s.usedIds = e.used;
        s.evidence = e.evidence;
        s.images = e.images;
        s.error = null;
        for (final i in e.images) {
          ImageQueryCache.seed(i.query, [i.image]);
        }
        doc.done = doc.body.where((x) => x.isDone).length;
        _bump(s.id);
      case DocSectionFailedEvent():
        final s = _section(e.sectionId);
        s.status = DocSectionStatus.failed;
        s.error = e.message;
        s.retryable = e.retryable;
        _bump(s.id);
      case DocNoticeEvent(:final message):
        doc.notice = message.isEmpty ? null : message;
      case DocDoneEvent():
        doc.status = e.status;
        if (e.words != null) doc.words = e.words!;
        if (e.used.isNotEmpty) doc.used = e.used;
        if (e.latencyMs != null) doc.latencyMs = e.latencyMs!;
        doc.etaMs = null;
        doc.phase = '';
        Haptics.received();
        _bumpAll();
      case DocErrorEvent(:final message):
        doc.error = message.isEmpty ? DocStrings.loadFailed : message;
        if (doc.isRunning) doc.status = DocStatus.failed;
        Haptics.error();
    }
    _notify();
  }

  static String? _statusFor(String phase) => switch (phase) {
    'outline' || 'planning' || 'context' => DocStatus.planning,
    'research' || 'researching' => DocStatus.researching,
    'sections' || 'writing' || 'finish' || 'finishing' => DocStatus.writing,
    // The server reports the final status as the last phase.
    DocStatus.outlineReady ||
    DocStatus.done ||
    DocStatus.partial ||
    DocStatus.failed ||
    DocStatus.interrupted => phase,
    _ => null,
  };

  void _replace(Doc next) {
    // Sections mid-rewrite keep their live text.
    for (final sid in _rewriting) {
      final live = doc.section(sid);
      final i = next.sections.indexWhere((s) => s.id == sid);
      if (live != null && i >= 0) next.sections[i] = live;
    }
    doc = next;
    loaded = true;
    loadError = null;
    for (final s in doc.sections) {
      for (final i in s.images) {
        ImageQueryCache.seed(i.query, [i.image]);
      }
    }
    _bumpAll();
  }

  void _outline(DocOutlineEvent e) {
    if (e.title.isNotEmpty) doc.title = e.title;
    if (e.subtitle.isNotEmpty) doc.subtitle = e.subtitle;
    if (e.glossary.isNotEmpty) doc.glossary = e.glossary;
    final old = {for (final s in doc.sections) s.id: s};
    doc.sections = [
      for (final s in e.sections)
        if (old[s.id] case final existing?)
          existing
            ..heading = s.heading
            ..goal = s.goal
            ..keyPoints = s.keyPoints
            ..visual = s.visual
            ..targetWords = s.targetWords
        else
          s,
    ];
    if (doc.total == 0) doc.total = doc.body.length;
    _bumpAll();
  }

  DocSection _section(String sid) {
    final found = doc.section(sid);
    if (found != null) return found;
    // A section the outline did not announce: show it anyway.
    final s = DocSection(id: sid);
    doc.sections = [...doc.sections, s];
    return s;
  }

  void _bump(String sid) {
    _dirty.remove(sid);
    _ticks[sid]?.bump();
  }

  void _bumpAll() {
    _dirty.clear();
    for (final t in _ticks.values) {
      t.bump();
    }
  }

  /// Coalesces streamed text into one repaint per throttle window.
  void _schedule(String sid) {
    _dirty.add(sid);
    _flush ??= Timer(DocSizes.streamThrottle, () {
      _flush = null;
      final ids = _dirty.toList();
      _dirty.clear();
      for (final id in ids) {
        _ticks[id]?.bump();
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- actions ---------------------------------------------------------------

  /// STOP: the server aborts the job and reports `partial`.
  Future<bool> stop() async {
    try {
      await _api.cancel(id);
      if (!attached && doc.isRunning) {
        doc.status = DocStatus.partial;
        _notify();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// RESUME: rewrites sections that are not done.
  Future<bool> resume() async {
    try {
      await _api.resume(id);
    } catch (_) {
      return false;
    }
    doc.status = DocStatus.writing;
    doc.error = null;
    for (final s in doc.body) {
      if (!s.isDone) {
        s.status = DocSectionStatus.pending;
        s.error = null;
      }
    }
    _attempt = 0;
    _bumpAll();
    _notify();
    attach();
    return true;
  }

  /// START after outline review, with the outline as shown.
  Future<bool> startWriting() async {
    try {
      await _api.start(
        id,
        outline: {
          'title': doc.title,
          'subtitle': doc.subtitle,
          'sections': [for (final s in doc.body) s.toOutlineJson()],
          'glossary': [for (final g in doc.glossary) g.toJson()],
        },
      );
    } catch (_) {
      return false;
    }
    doc.status = DocStatus.researching;
    _attempt = 0;
    _notify();
    attach();
    return true;
  }

  /// Streams a rewrite of one section. False when it could not start.
  Future<bool> rewrite(
    String sectionId,
    DocRewriteOp op, {
    String? instruction,
    String? selection,
  }) async {
    final s = doc.section(sectionId);
    if (s == null || s.isWriting || _rewriting.contains(sectionId)) {
      return false;
    }
    final before = (s.markdown, s.status, s.usedIds, s.evidence, s.words);
    _rewriting.add(sectionId);
    s.status = DocSectionStatus.writing;
    s.error = null;
    _bump(sectionId);
    _notify();
    final finished = Completer<bool>();
    var got = false;
    void restore(String? error) {
      s
        ..markdown = before.$1
        ..status = before.$2
        ..usedIds = before.$3
        ..evidence = before.$4
        ..words = before.$5;
      if (error != null) s.error = error;
    }

    _api
        .rewrite(
          id,
          sectionId,
          op: op,
          instruction: instruction,
          selection: selection,
        )
        .listen(
          (e) {
            if (e is DocSectionEvent && e.sectionId != sectionId) return;
            if (e is DocSectionDeltaEvent && !got) {
              got = true;
              s.markdown = '';
            }
            if (e is DocSectionStartEvent) got = true;
            apply(e, fromRewrite: true);
          },
          onError: (Object e) {
            _rewriting.remove(sectionId);
            restore(null);
            Haptics.error();
            _bump(sectionId);
            _notify();
            if (!finished.isCompleted) finished.complete(false);
          },
          onDone: () {
            _rewriting.remove(sectionId);
            if (s.isWriting) {
              // Closed without done: keep what arrived, else the old text.
              if (s.markdown.trim().isEmpty) {
                restore(null);
              } else {
                s.status = DocSectionStatus.done;
              }
            }
            if (s.isDone) doc.version++;
            _bump(sectionId);
            _notify();
            if (!finished.isCompleted) finished.complete(s.isDone);
          },
          cancelOnError: true,
        );
    return finished.future;
  }

  /// Saves a manual edit (or a restored version).
  Future<bool> saveSection(String sectionId, String markdown) async {
    final s = doc.section(sectionId);
    if (s == null || s.isWriting) return false;
    try {
      await _api.saveSection(id, sectionId, markdown);
    } catch (_) {
      return false;
    }
    s
      ..markdown = markdown
      ..status = DocSectionStatus.done
      ..words = countWords(markdown);
    doc.version++;
    _bump(sectionId);
    _notify();
    return true;
  }

  Future<List<DocRevision>> versions(String sectionId) =>
      _api.versions(id, sectionId);

  Future<bool> rename(String title) async {
    try {
      await _api.rename(id, title);
      doc.title = title;
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- highlights ------------------------------------------------------------

  Future<void> loadHighlights() async {
    try {
      highlights = await _api.highlights(id);
      _bumpAll();
      _notify();
    } catch (_) {
      // Highlights are extras; the doc reads fine without them.
    }
  }

  List<DocHighlight> highlightsFor(String sectionId) => [
    for (final h in highlights)
      if (h.sectionId == sectionId) h,
  ];

  /// Saves a highlight; it shows at once and is dropped if saving fails.
  Future<bool> addHighlight(DocHighlight h) async {
    highlights = [...highlights, h];
    _bump(h.sectionId);
    _notify();
    try {
      final saved = await _api.addHighlight(id, h);
      highlights = [for (final x in highlights) identical(x, h) ? saved : x];
      return true;
    } catch (_) {
      highlights = [
        for (final x in highlights)
          if (!identical(x, h)) x,
      ];
      _bump(h.sectionId);
      _notify();
      return false;
    }
  }

  Future<void> removeHighlight(DocHighlight h) async {
    highlights = [
      for (final x in highlights)
        if (!identical(x, h)) x,
    ];
    _bump(h.sectionId);
    _notify();
    if (h.id.isEmpty) return;
    try {
      await _api.deleteHighlight(id, h.id);
    } catch (_) {
      // Shows again on the next load.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    detach();
    _flush?.cancel();
    for (final t in _ticks.values) {
      t.dispose();
    }
    super.dispose();
  }
}
