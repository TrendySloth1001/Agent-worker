import 'dart:convert';

/// Where a cited source comes from: the knowledge base (`K<n>`), the web
/// (`W<n>`), an attached file (`D<n>`) or a generated document.
enum CitationKind {
  web,
  kb,
  file,
  doc;

  /// Stored JSON values are the enum names; anything unknown reads as web.
  static CitationKind parse(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return web;
  }
}

/// A source cited by a reply: `K<n>` from the knowledge base, `W<n>` from web.
class Citation {
  /// [kind] wins; the older [isKb] flag stays for callers that only know
  /// knowledge base vs web.
  const Citation({
    required this.id,
    bool isKb = false,
    CitationKind? kind,
    required this.title,
    required this.url,
    required this.site,
    this.snippet = '',
    this.sourceType,
  }) : kind = kind ?? (isKb ? CitationKind.kb : CitationKind.web);

  final String id;
  final CitationKind kind;
  final String title;
  final String url;
  final String site;
  final String snippet;
  final String? sourceType;

  bool get isKb => kind == CitationKind.kb;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'url': url,
    'site': site,
    'snippet': snippet,
    'sourceType': ?sourceType,
  };

  factory Citation.fromJson(Map<String, dynamic> j) => Citation(
    id: j['id'] as String? ?? '',
    kind: CitationKind.parse(j['kind']),
    title: j['title'] as String? ?? '',
    url: j['url'] as String? ?? '',
    site: j['site'] as String? ?? '',
    snippet: j['snippet'] as String? ?? '',
    sourceType: j['sourceType'] as String?,
  );
}

/// An image that helps explain a reply, with the page it comes from.
class ImageRef {
  const ImageRef({
    required this.url,
    required this.sourceUrl,
    required this.title,
    required this.site,
  });

  final String url;
  final String sourceUrl;
  final String title;
  final String site;

  Map<String, dynamic> toJson() => {
    'url': url,
    'sourceUrl': sourceUrl,
    'title': title,
    'site': site,
  };

  factory ImageRef.fromJson(Map<String, dynamic> j) => ImageRef(
    url: j['url'] as String? ?? '',
    sourceUrl: j['sourceUrl'] as String? ?? '',
    title: j['title'] as String? ?? '',
    site: j['site'] as String? ?? '',
  );
}

/// The passage of a source that supports one sentence of a reply.
class Evidence {
  const Evidence({
    required this.tag,
    required this.claim,
    required this.quote,
    required this.score,
  });

  final String tag;
  final String claim;
  final String quote;
  final double score;

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'claim': claim,
    'quote': quote,
    'score': score,
  };

  factory Evidence.fromJson(Map<String, dynamic> j) => Evidence(
    tag: j['tag'] as String? ?? '',
    claim: j['claim'] as String? ?? '',
    quote: j['quote'] as String? ?? '',
    score: (j['score'] as num?)?.toDouble() ?? 0,
  );
}

/// Server-sent events from POST /chat, mirrored from the API contract.
sealed class ChatEvent {
  const ChatEvent();

  /// Returns null for unknown events so new server events are ignored.
  static ChatEvent? parse(String name, String data) {
    final Object? json;
    try {
      json = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    switch (name) {
      case 'start':
        return StartEvent();
      case 'status':
        return StatusEvent(json['phase'] as String? ?? '');
      case 'notice':
        return NoticeEvent(
          json['code'] as String? ?? '',
          json['message'] as String? ?? '',
        );
      case 'sources':
        final list = json['citations'] as List? ?? const [];
        return SourcesEvent([
          for (final c in list)
            if (c is Map<String, dynamic>) Citation.fromJson(c),
        ]);
      case 'images':
        return ImagesEvent([
          for (final i in json['images'] as List? ?? const [])
            if (i is Map<String, dynamic>) ImageRef.fromJson(i),
        ]);
      case 'evidence':
        return EvidenceEvent([
          for (final e in json['items'] as List? ?? const [])
            if (e is Map<String, dynamic>) Evidence.fromJson(e),
        ]);
      case 'suggestions':
        return SuggestionsEvent([
          for (final s in json['items'] as List? ?? const [])
            if (s is String && s.trim().isNotEmpty) s.trim(),
        ]);
      case 'model':
        return ModelEvent(json['model'] as String? ?? '');
      case 'delta':
        return DeltaEvent(json['text'] as String? ?? '');
      case 'reset':
        return ResetEvent();
      case 'table':
        return TableEvent.fromJson(json);
      case 'memory':
        return MemoryEvent([
          for (final c in json['changes'] as List? ?? const [])
            if (c is Map<String, dynamic>) c['op'] as String? ?? '',
        ]);
      case 'usage':
        return UsageEvent(
          json['promptTokens'] as int?,
          json['completionTokens'] as int?,
        );
      case 'done':
        return DoneEvent(
          model: json['model'] as String?,
          used: [
            for (final u in json['used'] as List? ?? const [])
              if (u is String) u,
          ],
        );
      case 'error':
        final e = json['error'];
        return ErrorEvent(
          e is Map<String, dynamic> ? e['message'] as String? ?? '' : '',
          e is Map<String, dynamic> && e['retryable'] == true,
        );
    }
    return null;
  }
}

class StartEvent extends ChatEvent {}

class StatusEvent extends ChatEvent {
  const StatusEvent(this.phase);
  final String phase;
}

class NoticeEvent extends ChatEvent {
  const NoticeEvent(this.code, this.message);
  final String code, message;
}

class SourcesEvent extends ChatEvent {
  const SourcesEvent(this.citations);
  final List<Citation> citations;
}

class ImagesEvent extends ChatEvent {
  const ImagesEvent(this.images);
  final List<ImageRef> images;
}

class EvidenceEvent extends ChatEvent {
  const EvidenceEvent(this.items);
  final List<Evidence> items;
}

class SuggestionsEvent extends ChatEvent {
  const SuggestionsEvent(this.items);
  final List<String> items;
}

class ModelEvent extends ChatEvent {
  const ModelEvent(this.model);
  final String model;
}

class DeltaEvent extends ChatEvent {
  const DeltaEvent(this.text);
  final String text;
}

class ResetEvent extends ChatEvent {}

/// What the assistant just saved to long-term memory: ADD, UPDATE or DELETE.
class MemoryEvent extends ChatEvent {
  const MemoryEvent(this.ops);
  final List<String> ops;
}

class UsageEvent extends ChatEvent {
  const UsageEvent(this.promptTokens, this.completionTokens);
  final int? promptTokens, completionTokens;
}

class DoneEvent extends ChatEvent {
  const DoneEvent({this.model, this.used = const []});
  final String? model;
  final List<String> used;
}

class ErrorEvent extends ChatEvent {
  const ErrorEvent(this.message, this.retryable);
  final String message;
  final bool retryable;
}

// ---- Round Table ----------------------------------------------------------

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) => [
  for (final e in raw as List? ?? const [])
    if (e is Map<String, dynamic>) parse(e),
];

/// One review finding: a [claim] in seat [seat]'s draft.
class TablePoint {
  const TablePoint({
    required this.seat,
    required this.kind,
    required this.claim,
    this.detail = '',
    this.sources = const [],
  });

  final String seat;

  /// error, disagree or missing.
  final String kind;
  final String claim;
  final String detail;
  final List<String> sources;

  Map<String, dynamic> toJson() => {
    'seat': seat,
    'kind': kind,
    'claim': claim,
    'detail': detail,
    'sources': sources,
  };

  factory TablePoint.fromJson(Map<String, dynamic> j) => TablePoint(
    seat: j['seat'] as String? ?? '',
    kind: j['kind'] as String? ?? 'disagree',
    claim: j['claim'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    sources: [
      for (final s in j['sources'] as List? ?? const [])
        if (s is String) s,
    ],
  );
}

/// A seat at the table. Mutable so the live panel can update it in place.
class TableSeat {
  TableSeat({
    required this.seat,
    required this.model,
    required this.name,
    this.status = 'working',
    this.summary = '',
    this.draft = '',
    this.queries = const [],
    this.sources = const [],
  });

  final String seat;
  String model;
  String name;

  /// working, done or failed (live: also reviewing outcomes).
  String status;
  String summary;
  String draft;

  /// What this seat searched the web for.
  List<String> queries;

  /// Citation tags its draft cites, e.g. `W3`.
  List<String> sources;

  /// Live only: review points raised against this seat's draft.
  int objections = 0;

  bool get isChair => seat == 'A';

  Map<String, dynamic> toJson() => {
    'seat': seat,
    'model': model,
    'name': name,
    'status': status,
    'summary': summary,
    'draft': draft,
    if (queries.isNotEmpty) 'queries': queries,
    if (sources.isNotEmpty) 'sources': sources,
  };

  factory TableSeat.fromJson(Map<String, dynamic> j) => TableSeat(
    seat: j['seat'] as String? ?? '',
    model: j['model'] as String? ?? '',
    name: j['name'] as String? ?? '',
    status: j['status'] as String? ?? 'done',
    summary: j['summary'] as String? ?? '',
    draft: j['draft'] as String? ?? '',
    queries: _strings(j['queries']),
    sources: _strings(j['sources']),
  );
}

List<String> _strings(Object? raw) => [
  for (final s in raw as List? ?? const [])
    if (s is String) s,
];

/// What one seat found reviewing the other drafts.
class TableReview {
  const TableReview({
    required this.seat,
    required this.model,
    required this.verdict,
    this.points = const [],
  });

  final String seat;
  final String model;

  /// agree, minor, major or unknown (review failed).
  final String verdict;
  final List<TablePoint> points;

  Map<String, dynamic> toJson() => {
    'seat': seat,
    'model': model,
    'verdict': verdict,
    'points': [for (final p in points) p.toJson()],
  };

  factory TableReview.fromJson(Map<String, dynamic> j) => TableReview(
    seat: j['seat'] as String? ?? '',
    model: j['model'] as String? ?? '',
    verdict: j['verdict'] as String? ?? 'unknown',
    points: _list(j['points'], TablePoint.fromJson),
  );
}

/// Which seats' drafts back one sentence of the chair's answer.
class TableSupport {
  const TableSupport({
    required this.sentence,
    this.paragraph = 0,
    this.seats = const [],
    this.disputed = false,
    this.excerpts = const {},
  });

  final String sentence;
  final int paragraph;
  final List<String> seats;
  final bool disputed;

  /// Seat letter to the matching passage of its draft.
  final Map<String, String> excerpts;

  Map<String, dynamic> toJson() => {
    'sentence': sentence,
    'paragraph': paragraph,
    'seats': seats,
    if (disputed) 'disputed': true,
    'excerpts': excerpts,
  };

  factory TableSupport.fromJson(Map<String, dynamic> j) => TableSupport(
    sentence: j['sentence'] as String? ?? '',
    paragraph: (j['paragraph'] as num?)?.toInt() ?? 0,
    seats: _strings(j['seats']),
    disputed: j['disputed'] == true,
    excerpts: {
      if (j['excerpts'] is Map)
        for (final e in (j['excerpts'] as Map).entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
    },
  );
}

/// The record of a finished round table, saved with the reply.
class TableTranscript {
  const TableTranscript({
    this.seats = const [],
    this.reviews = const [],
    this.consensus = 'agreed',
    this.unresolved = const [],
    this.chair = '',
    this.calls = 0,
    this.ms = 0,
    this.support = const [],
  });

  final List<TableSeat> seats;
  final List<TableReview> reviews;

  /// agreed, resolved or disputed.
  final String consensus;
  final List<String> unresolved;
  final String chair;
  final int calls;
  final int ms;

  bool get disputed => consensus == 'disputed';

  /// Per answer sentence: the seats whose drafts back it.
  final List<TableSupport> support;

  Map<String, dynamic> toJson() => {
    'seats': [for (final s in seats) s.toJson()],
    'reviews': [for (final r in reviews) r.toJson()],
    'consensus': consensus,
    'unresolved': unresolved,
    'chair': chair,
    'calls': calls,
    'ms': ms,
    if (support.isNotEmpty) 'support': [for (final x in support) x.toJson()],
  };

  factory TableTranscript.fromJson(Map<String, dynamic> j) => TableTranscript(
    seats: _list(j['seats'], TableSeat.fromJson),
    reviews: _list(j['reviews'], TableReview.fromJson),
    consensus: j['consensus'] as String? ?? 'agreed',
    unresolved: [
      for (final u in j['unresolved'] as List? ?? const [])
        if (u is String) u,
    ],
    chair: j['chair'] as String? ?? '',
    calls: (j['calls'] as num?)?.toInt() ?? 0,
    ms: (j['ms'] as num?)?.toInt() ?? 0,
    support: _list(j['support'], TableSupport.fromJson),
  );
}

/// Progress of a round table: `phase` plus, for per-seat updates, the seat.
class TableEvent extends ChatEvent {
  const TableEvent({
    required this.phase,
    this.seats = const [],
    this.seat,
    this.model,
    this.status,
    this.summary,
    this.points = const [],
    this.transcript,
    this.elapsedMs,
    this.etaMs,
    this.research = const {},
  });

  /// researching, seating, drafting, checking, reviewing, synthesizing or
  /// done.
  final String phase;
  final List<TableSeat> seats;
  final String? seat;
  final String? model;
  final String? status;
  final String? summary;
  final List<TablePoint> points;
  final TableTranscript? transcript;

  /// Time since the request started, and the server's estimate of what is
  /// left until the answer is complete.
  final int? elapsedMs;
  final int? etaMs;

  /// Planned web searches per seat letter (researching phase).
  final Map<String, List<String>> research;

  factory TableEvent.fromJson(Map<String, dynamic> j) => TableEvent(
    phase: j['phase'] as String? ?? '',
    seats: _list(j['seats'], TableSeat.fromJson),
    seat: j['seat'] as String?,
    model: j['model'] as String?,
    status: j['status'] as String?,
    summary: j['summary'] as String?,
    points: _list(j['points'], TablePoint.fromJson),
    transcript: j['transcript'] is Map<String, dynamic>
        ? TableTranscript.fromJson(j['transcript'] as Map<String, dynamic>)
        : null,
    elapsedMs: (j['elapsedMs'] as num?)?.toInt(),
    etaMs: (j['etaMs'] as num?)?.toInt(),
    research: {
      for (final r in j['research'] as List? ?? const [])
        if (r is Map<String, dynamic> && r['seat'] is String)
          r['seat'] as String: _strings(r['queries']),
    },
  );
}
