import 'dart:convert';

import 'chat_event.dart';

// Models for DOC mode (docs/DOCS_MODE.md §3–4). Every parser is defensive:
// unknown fields are ignored and missing ones get a default, so the client
// keeps working while the server contract evolves.

List<String> _strings(Object? raw) => [
  for (final s in raw is List ? raw : const [])
    if (s is String) s,
];

List<Map<String, dynamic>> _maps(Object? raw) => [
  for (final m in raw is List ? raw : const [])
    if (m is Map<String, dynamic>) m,
];

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Doc lifecycle (server `status`).
abstract final class DocStatus {
  static const planning = 'planning';
  static const outlineReady = 'outline_ready';
  static const researching = 'researching';
  static const writing = 'writing';
  static const done = 'done';
  static const partial = 'partial';
  static const failed = 'failed';
  static const interrupted = 'interrupted';

  /// The pipeline is still working on the doc.
  static bool isRunning(String s) =>
      s == planning || s == researching || s == writing;

  /// Nothing more will arrive without RESUME / START.
  static bool isTerminal(String s) => !isRunning(s);

  /// RESUME rewrites the sections that are not done.
  static bool canResume(String s) =>
      s == partial || s == failed || s == interrupted;
}

/// Section lifecycle.
abstract final class DocSectionStatus {
  static const pending = 'pending';
  static const writing = 'writing';
  static const done = 'done';
  static const failed = 'failed';
}

/// A term the outline defines once for the whole doc.
class DocGlossaryTerm {
  const DocGlossaryTerm({required this.term, required this.definition});

  final String term;
  final String definition;

  factory DocGlossaryTerm.fromJson(Map<String, dynamic> j) =>
      DocGlossaryTerm(term: _str(j['term']), definition: _str(j['definition']));

  Map<String, dynamic> toJson() => {'term': term, 'definition': definition};
}

/// A picture the server resolved for a section's `{{image:QUERY}}`.
class DocImage {
  const DocImage({required this.query, required this.image});

  final String query;
  final ImageRef image;

  static DocImage? fromJson(Map<String, dynamic> j) {
    final nested = j['image'];
    final ref = nested is Map<String, dynamic>
        ? ImageRef.fromJson(nested)
        : ImageRef.fromJson(j);
    if (ref.url.isEmpty) return null;
    return DocImage(query: _str(j['query']), image: ref);
  }

  Map<String, dynamic> toJson() => {'query': query, ...image.toJson()};
}

/// One section: the outline entry plus what has been written for it.
/// Mutable so live events update it in place.
class DocSection {
  DocSection({
    required this.id,
    this.heading = '',
    this.goal = '',
    this.keyPoints = const [],
    this.visual = 'none',
    this.targetWords = 0,
    this.level = 2,
    this.markdown = '',
    this.summary = '',
    this.status = DocSectionStatus.pending,
    this.sourceIds = const [],
    this.usedIds = const [],
    this.evidence = const [],
    this.images = const [],
    this.model,
    this.words = 0,
  });

  final String id;
  String heading;
  String goal;
  List<String> keyPoints;
  String visual;

  /// Words the outline planned for this section.
  int targetWords;
  int level;
  String markdown;
  String summary;
  String status;
  List<String> sourceIds;
  List<String> usedIds;
  List<Evidence> evidence;
  List<DocImage> images;
  String? model;

  /// Words actually written.
  int words;

  /// Why the section failed (doc_section_failed), if it did.
  String? error;
  bool retryable = true;

  bool get isPending => status == DocSectionStatus.pending;
  bool get isWriting => status == DocSectionStatus.writing;
  bool get isDone => status == DocSectionStatus.done;
  bool get isFailed => status == DocSectionStatus.failed;

  /// Built by the client from the sources, never rendered from markdown.
  bool get isReferences =>
      id.toLowerCase() == 'references' ||
      heading.trim().toLowerCase() == 'references';

  /// From an outline entry (`id`, `goal`, `words` = target) or a stored
  /// row (`sectionId`, `markdown`, `words` = written).
  factory DocSection.fromJson(Map<String, dynamic> j) {
    final row = j.containsKey('sectionId') || j.containsKey('markdown');
    final s = DocSection(id: _str(j['id'] ?? j['sectionId']));
    s.mergeJson(j, row: row);
    return s;
  }

  /// From an outline entry only: `words` is the target.
  factory DocSection.fromOutline(Map<String, dynamic> j) =>
      DocSection(id: _str(j['id'] ?? j['sectionId']))..mergeJson(j, row: false);

  /// Copies fields present in [j]. [row] marks a stored section, whose
  /// `words` is the written count rather than the outline target.
  void mergeJson(Map<String, dynamic> j, {required bool row}) {
    if (j['heading'] is String) heading = j['heading'] as String;
    if (j['goal'] is String) goal = j['goal'] as String;
    if (j['keyPoints'] is List) keyPoints = _strings(j['keyPoints']);
    if (j['visual'] is String) visual = j['visual'] as String;
    if (_int(j['level']) != null) level = _int(j['level'])!;
    if (j['markdown'] is String) markdown = j['markdown'] as String;
    if (j['summary'] is String) summary = j['summary'] as String;
    if (j['status'] is String) status = j['status'] as String;
    if (j['sourceIds'] is List) sourceIds = _strings(j['sourceIds']);
    if (j['usedIds'] is List) usedIds = _strings(j['usedIds']);
    if (j['used'] is List) usedIds = _strings(j['used']);
    if (j['evidence'] is List) {
      evidence = [for (final e in _maps(j['evidence'])) Evidence.fromJson(e)];
    }
    if (j['images'] is List) {
      images = [for (final i in _maps(j['images'])) ?DocImage.fromJson(i)];
    }
    if (j['model'] is String) model = j['model'] as String;
    final w = _int(j['words']);
    if (w != null) {
      if (row) {
        words = w;
      } else {
        targetWords = w;
      }
    }
    if (_int(j['targetWords']) != null) targetWords = _int(j['targetWords'])!;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'heading': heading,
    'goal': goal,
    'keyPoints': keyPoints,
    'visual': visual,
    'targetWords': targetWords,
    'level': level,
    'markdown': markdown,
    'summary': summary,
    'status': status,
    'sourceIds': sourceIds,
    'usedIds': usedIds,
    'evidence': [for (final e in evidence) e.toJson()],
    'images': [for (final i in images) i.toJson()],
    'model': ?model,
    'words': words,
  };

  /// Outline entry for POST /docs/:id/start.
  Map<String, dynamic> toOutlineJson() => {
    'id': id,
    'heading': heading,
    'goal': goal,
    'keyPoints': keyPoints,
    'visual': visual,
    'words': targetWords,
  };
}

/// A whole document: outline, sections, sources and live progress.
class Doc {
  Doc({
    required this.id,
    this.title = '',
    this.subtitle = '',
    this.prompt = '',
    this.status = DocStatus.planning,
    this.conversationId,
    List<DocSection>? sections,
    this.glossary = const [],
    this.sources = const [],
    this.summary = '',
    this.takeaways = const [],
    this.words = 0,
    this.version = 0,
    this.used = const [],
    this.options = const {},
    this.createdAt,
    this.updatedAt,
  }) : sections = sections ?? [];

  final String id;
  String title;
  String subtitle;
  String prompt;
  String status;
  String? conversationId;
  List<DocSection> sections;
  List<DocGlossaryTerm> glossary;
  List<Citation> sources;

  /// One-paragraph abstract, written last.
  String summary;
  List<String> takeaways;
  int words;
  int version;

  /// Cited source ids in first-use order (doc_done), when known.
  List<String> used;
  Map<String, dynamic> options;
  DateTime? createdAt, updatedAt;

  // Live progress (doc_status), not persisted.
  String phase = '';
  int done = 0;
  int total = 0;
  int elapsedMs = 0;
  int? etaMs;

  /// When the last doc_status arrived, to count the ETA down locally.
  DateTime? statusAt;
  int latencyMs = 0;

  /// Latest non-fatal notice, and the fatal error if the job broke.
  String? notice;
  String? error;

  bool get isRunning => DocStatus.isRunning(status);

  DocSection? section(String id) =>
      sections.where((s) => s.id == id).firstOrNull;

  /// Sections the reader shows (References is drawn from [sources]).
  List<DocSection> get body => [
    for (final s in sections)
      if (!s.isReferences) s,
  ];

  /// Words written so far: the server total, else the sum of sections.
  int get wordCount {
    if (words > 0) return words;
    var n = 0;
    for (final s in sections) {
      n += s.words > 0 ? s.words : _countWords(s.markdown);
    }
    return n;
  }

  /// Ids cited anywhere, in first-use order.
  List<String> get citedIds {
    if (used.isNotEmpty) return used;
    final seen = <String>{};
    for (final s in body) {
      final ids = s.usedIds.isNotEmpty ? s.usedIds : _tagsIn(s.markdown);
      seen.addAll(ids);
    }
    return seen.toList();
  }

  /// The bibliography: cited sources in first-use order.
  List<Citation> get references {
    final byId = {for (final c in sources) c.id: c};
    return [
      for (final id in citedIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// How often each source is cited in the body, by id.
  Map<String, int> get citeCounts {
    final counts = <String, int>{};
    for (final s in body) {
      for (final id in _tagsIn(s.markdown)) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Every evidence passage, for citation chips anywhere in the doc.
  List<Evidence> get evidence => [for (final s in sections) ...s.evidence];

  /// Parses GET /docs/:id and the `doc` of doc_snapshot. The outline (its
  /// sections give order, goals and targets) and the stored section rows
  /// are merged by id.
  factory Doc.fromJson(Map<String, dynamic> j) {
    final outline = j['outline'];
    final outlineMap = outline is Map<String, dynamic> ? outline : null;
    final outlineList = outline is List
        ? _maps(outline)
        : _maps(outlineMap?['sections']);
    final sections = <DocSection>[];
    for (final o in outlineList) {
      final s = DocSection.fromOutline(o);
      if (s.id.isNotEmpty) sections.add(s);
    }
    final rows = _maps(j['sections']);
    rows.sort((a, b) => (_int(a['ord']) ?? 0).compareTo(_int(b['ord']) ?? 0));
    for (final r in rows) {
      final id = _str(r['sectionId'] ?? r['id']);
      if (id.isEmpty) continue;
      final existing = sections.where((s) => s.id == id).firstOrNull;
      final isRow = r.containsKey('sectionId') || r.containsKey('markdown');
      if (existing != null) {
        existing.mergeJson(r, row: isRow);
      } else {
        sections.add(DocSection.fromJson(r));
      }
    }
    final glossary = j['glossary'] ?? outlineMap?['glossary'];
    final summary = j['summary'] ?? j['abstract'];
    return Doc(
      id: _str(j['id']),
      title: _str(j['title'], _str(outlineMap?['title'])),
      subtitle: _str(j['subtitle'], _str(outlineMap?['subtitle'])),
      prompt: _str(j['prompt']),
      status: _str(j['status'], DocStatus.planning),
      conversationId: j['conversationId'] as String?,
      sections: sections,
      glossary: [for (final g in _maps(glossary)) DocGlossaryTerm.fromJson(g)],
      sources: [for (final c in _maps(j['sources'])) Citation.fromJson(c)],
      summary: summary is String ? summary : '',
      takeaways: _strings(j['takeaways']),
      words: _int(j['words']) ?? 0,
      version: _int(j['version']) ?? 0,
      used: _strings(j['used']),
      options: j['options'] is Map<String, dynamic>
          ? j['options'] as Map<String, dynamic>
          : const {},
      createdAt: _date(j['createdAt']),
      updatedAt: _date(j['updatedAt']),
    )..applyProgress(j);
  }

  /// Copies progress fields (`phase`, `done`, `total`, `elapsedMs`, `etaMs`).
  void applyProgress(Map<String, dynamic> j) {
    if (j['phase'] is String) phase = j['phase'] as String;
    if (_int(j['done']) != null) done = _int(j['done'])!;
    if (_int(j['total']) != null) total = _int(j['total'])!;
    if (_int(j['elapsedMs']) != null) elapsedMs = _int(j['elapsedMs'])!;
    if (j.containsKey('etaMs')) etaMs = _int(j['etaMs']);
    statusAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'prompt': prompt,
    'status': status,
    'conversationId': ?conversationId,
    'outline': {
      'title': title,
      'subtitle': subtitle,
      'sections': [for (final s in sections) s.toOutlineJson()],
      'glossary': [for (final g in glossary) g.toJson()],
    },
    'sections': [
      for (final (i, s) in sections.indexed) {...s.toJson(), 'ord': i},
    ],
    'sources': [for (final c in sources) c.toJson()],
    'summary': summary,
    'takeaways': takeaways,
    'words': words,
    'version': version,
    'used': used,
  };

  /// The chat-card link saved in the assistant message's `meta.doc`.
  Map<String, dynamic> toMeta() => {
    'id': id,
    'title': title,
    'status': status,
    'words': wordCount,
    'sections': [for (final s in body) s.status],
  };
}

/// What `meta.doc` on a chat message says about its document.
class DocLink {
  const DocLink({
    required this.id,
    this.title = '',
    this.status = DocStatus.planning,
    this.words = 0,
    this.sections = const [],
    this.sectionCount = 0,
  });

  final String id;
  final String title;
  final String status;
  final int words;

  /// Per-section status, when stored as a list.
  final List<String> sections;

  /// Section count (a bare number in meta, or the list length).
  final int sectionCount;

  static DocLink? fromMeta(Map<String, dynamic> meta) {
    final d = meta['doc'];
    if (d is! Map<String, dynamic>) return null;
    final id = _str(d['id']);
    if (id.isEmpty) return null;
    final raw = d['sections'];
    final statuses = raw is List
        ? [
            for (final s in raw)
              if (s is String)
                s
              else if (s is Map<String, dynamic>)
                _str(s['status'], DocSectionStatus.pending),
          ]
        : const <String>[];
    return DocLink(
      id: id,
      title: _str(d['title']),
      status: _str(d['status'], DocStatus.planning),
      words: _int(d['words']) ?? 0,
      sections: statuses,
      sectionCount: raw is num ? raw.toInt() : statuses.length,
    );
  }

  factory DocLink.of(Doc doc) {
    final meta = doc.toMeta();
    return DocLink.fromMeta({'doc': meta})!;
  }
}

/// One saved version of a section (GET /docs/:id/versions/:sid).
class DocRevision {
  const DocRevision({
    required this.version,
    required this.markdown,
    required this.reason,
    this.createdAt,
  });

  final int version;
  final String markdown;

  /// generate, regenerate, expand, shorten, simplify, edit or custom.
  final String reason;
  final DateTime? createdAt;

  factory DocRevision.fromJson(Map<String, dynamic> j) => DocRevision(
    version: _int(j['version']) ?? 0,
    markdown: _str(j['markdown']),
    reason: _str(j['reason'], 'generate'),
    createdAt: _date(j['createdAt']),
  );
}

/// One question about a highlighted passage and the model's answer.
class DocQa {
  const DocQa({
    required this.id,
    required this.question,
    required this.answer,
    this.at,
  });

  final String id;
  final String question;
  final String answer;
  final DateTime? at;

  factory DocQa.fromJson(Map<String, dynamic> j) => DocQa(
    id: _str(j['id']),
    question: _str(j['q']),
    answer: _str(j['a']),
    at: _date(j['at']),
  );
}

/// Edits the reader can ask for on a selected passage.
enum DocSelectionOp { explain, simplify, expand, cite, rewrite }

/// A previewed change to one passage: nothing is saved until accepted.
class DocSelectionEdit {
  const DocSelectionEdit({
    required this.op,
    required this.original,
    required this.replacement,
    required this.markdown,
  });

  final DocSelectionOp op;

  /// The passage as Markdown; empty when the edit only inserts.
  final String original;
  final String replacement;

  /// The whole section after the change.
  final String markdown;

  bool get isInsert => original.isEmpty;

  factory DocSelectionEdit.fromJson(Map<String, dynamic> j) => DocSelectionEdit(
    op: DocSelectionOp.values.firstWhere(
      (o) => o.name == j['op'],
      orElse: () => DocSelectionOp.rewrite,
    ),
    original: _str(j['original']),
    replacement: _str(j['replacement']),
    markdown: _str(j['markdown']),
  );
}

/// A highlighted passage, anchored by W3C text quote (prefix/quote/suffix).
class DocHighlight {
  const DocHighlight({
    required this.id,
    required this.sectionId,
    required this.quote,
    this.prefix = '',
    this.suffix = '',
    this.color = 'accent',
    this.note,
    this.thread = const [],
    this.createdAt,
  });

  final String id;
  final String sectionId;
  final String quote;
  final String prefix;
  final String suffix;
  final String color;
  final String? note;

  /// Questions asked about this passage with their answers, oldest first.
  final List<DocQa> thread;
  final DateTime? createdAt;

  bool get hasNote => note != null && note!.trim().isNotEmpty;
  bool get hasThread => thread.isNotEmpty;

  /// Same passage with a different Q&A thread (the server's copy wins).
  DocHighlight withThread(List<DocQa> next) => DocHighlight(
    id: id,
    sectionId: sectionId,
    quote: quote,
    prefix: prefix,
    suffix: suffix,
    color: color,
    note: note,
    thread: next,
    createdAt: createdAt,
  );

  factory DocHighlight.fromJson(Map<String, dynamic> j) => DocHighlight(
    id: _str(j['id']),
    sectionId: _str(j['sectionId']),
    quote: _str(j['quote']),
    prefix: _str(j['prefix']),
    suffix: _str(j['suffix']),
    color: _str(j['color'], 'accent'),
    note: j['note'] as String?,
    thread: [
      for (final q in j['thread'] as List? ?? const [])
        if (q is Map<String, dynamic>) DocQa.fromJson(q),
    ],
    createdAt: _date(j['createdAt']),
  );

  Map<String, dynamic> toJson() => {
    'sectionId': sectionId,
    'quote': quote,
    'prefix': prefix,
    'suffix': suffix,
    'color': color,
    'note': ?note,
  };
}

/// Rewrite operations on one section.
enum DocRewriteOp { regenerate, expand, shorten, simplify, custom }

/// Server-sent events from GET /docs/:id/events and section rewrites.
sealed class DocEvent {
  const DocEvent();

  /// Null for unknown events or bad JSON, so new server events are ignored.
  static DocEvent? parse(String name, String data) {
    final Object? json;
    try {
      json = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    final sid = _str(json['sectionId']);
    switch (name) {
      case 'doc_snapshot':
        final d = json['doc'];
        return DocSnapshotEvent(
          Doc.fromJson(d is Map<String, dynamic> ? d : json),
        );
      case 'doc_status':
        return DocStatusEvent(
          phase: _str(json['phase']),
          done: _int(json['done']),
          total: _int(json['total']),
          elapsedMs: _int(json['elapsedMs']),
          etaMs: _int(json['etaMs']),
          status: json['status'] as String?,
        );
      case 'doc_outline':
        return DocOutlineEvent(
          title: _str(json['title']),
          subtitle: _str(json['subtitle']),
          sections: [
            for (final s in _maps(json['sections'])) DocSection.fromOutline(s),
          ].where((s) => s.id.isNotEmpty).toList(),
          glossary: [
            for (final g in _maps(json['glossary']))
              DocGlossaryTerm.fromJson(g),
          ],
        );
      case 'doc_sources':
        return DocSourcesEvent([
          for (final c in _maps(json['citations'])) Citation.fromJson(c),
        ]);
      case 'doc_section_start':
        return DocSectionStartEvent(
          sid,
          model: json['model'] as String?,
          sourceIds: _strings(json['sourceIds']),
        );
      case 'doc_section_delta':
        return DocSectionDeltaEvent(sid, _str(json['text']));
      case 'doc_section_reset':
        return DocSectionResetEvent(sid);
      case 'doc_section_done':
        return DocSectionDoneEvent(
          sid,
          markdown: _str(json['markdown']),
          words: _int(json['words']) ?? 0,
          used: _strings(json['used']),
          evidence: [
            for (final e in _maps(json['evidence'])) Evidence.fromJson(e),
          ],
          images: [
            for (final i in _maps(json['images'])) ?DocImage.fromJson(i),
          ],
        );
      case 'doc_section_failed':
        return DocSectionFailedEvent(
          sid,
          message: _str(json['message']),
          retryable: json['retryable'] != false,
        );
      case 'doc_notice':
        return DocNoticeEvent(_str(json['code']), _str(json['message']));
      case 'doc_done':
        return DocDoneEvent(
          status: _str(json['status'], DocStatus.done),
          words: _int(json['words']),
          used: _strings(json['used']),
          latencyMs: _int(json['latencyMs']),
        );
      case 'doc_error':
        final e = json['error'];
        return DocErrorEvent(
          _str(
            json['message'],
            e is Map<String, dynamic> ? _str(e['message']) : '',
          ),
        );
    }
    return null;
  }
}

class DocSnapshotEvent extends DocEvent {
  const DocSnapshotEvent(this.doc);
  final Doc doc;
}

class DocStatusEvent extends DocEvent {
  const DocStatusEvent({
    required this.phase,
    this.done,
    this.total,
    this.elapsedMs,
    this.etaMs,
    this.status,
  });
  final String phase;
  final int? done, total, elapsedMs, etaMs;

  /// Doc status, when the server sends it along.
  final String? status;
}

class DocOutlineEvent extends DocEvent {
  const DocOutlineEvent({
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.glossary,
  });
  final String title, subtitle;
  final List<DocSection> sections;
  final List<DocGlossaryTerm> glossary;
}

class DocSourcesEvent extends DocEvent {
  const DocSourcesEvent(this.citations);
  final List<Citation> citations;
}

/// Events about one section.
sealed class DocSectionEvent extends DocEvent {
  const DocSectionEvent(this.sectionId);
  final String sectionId;
}

class DocSectionStartEvent extends DocSectionEvent {
  const DocSectionStartEvent(
    super.sectionId, {
    this.model,
    this.sourceIds = const [],
  });
  final String? model;
  final List<String> sourceIds;
}

class DocSectionDeltaEvent extends DocSectionEvent {
  const DocSectionDeltaEvent(super.sectionId, this.text);
  final String text;
}

class DocSectionResetEvent extends DocSectionEvent {
  const DocSectionResetEvent(super.sectionId);
}

class DocSectionDoneEvent extends DocSectionEvent {
  const DocSectionDoneEvent(
    super.sectionId, {
    required this.markdown,
    this.words = 0,
    this.used = const [],
    this.evidence = const [],
    this.images = const [],
  });
  final String markdown;
  final int words;
  final List<String> used;
  final List<Evidence> evidence;
  final List<DocImage> images;
}

class DocSectionFailedEvent extends DocSectionEvent {
  const DocSectionFailedEvent(
    super.sectionId, {
    required this.message,
    this.retryable = true,
  });
  final String message;
  final bool retryable;
}

class DocNoticeEvent extends DocEvent {
  const DocNoticeEvent(this.code, this.message);
  final String code, message;
}

class DocDoneEvent extends DocEvent {
  const DocDoneEvent({
    required this.status,
    this.words,
    this.used = const [],
    this.latencyMs,
  });
  final String status;
  final int? words;
  final List<String> used;
  final int? latencyMs;
}

class DocErrorEvent extends DocEvent {
  const DocErrorEvent(this.message);
  final String message;
}

int _countWords(String md) =>
    RegExp(r"[A-Za-z0-9À-ɏЀ-ӿ]+(?:['’][A-Za-z]+)?").allMatches(md).length;

final _tagRe = RegExp(r'\[([KWDGC]\d{1,3})\](?!\()');

List<String> _tagsIn(String md) => [
  for (final m in _tagRe.allMatches(md)) m[1]!,
];

/// [text] without citation tags, for places that show plain text (the
/// abstract) and their leading space.
String withoutCitations(String text) =>
    text.replaceAll(RegExp(r'[ \t]*\[[KWDGC]\d{1,3}\](?!\()'), '');

/// Words in [markdown] (for live counts before the server reports them).
int countWords(String markdown) => _countWords(markdown);
