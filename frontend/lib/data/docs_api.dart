import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/docs.dart';
import 'api_client.dart';
import 'chat_api.dart';
import 'doc_models.dart';

/// Makes the HTTP client for one request or stream. Closing it ends that
/// request. Tests pass a fake (e.g. `MockClient.streaming`).
typedef DocsTransport = http.Client Function();

/// Options for POST /docs.
class DocRequest {
  const DocRequest({
    required this.prompt,
    this.conversationId,
    this.length = DocConfig.defaultLength,
    this.webSearch = true,
    this.knowledge = false,
    this.sourceIds = const [],
    this.attachments = const [],
    this.model,
    this.profile = const {},
    this.reviewOutline = false,
  });

  final String prompt;
  final String? conversationId;
  final String length;
  final bool webSearch;
  final bool knowledge;
  final List<String> sourceIds;

  /// Uploaded file ids.
  final List<String> attachments;
  final String? model;
  final Map<String, String> profile;
  final bool reviewOutline;

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'conversationId': ?conversationId,
    'length': length,
    'webSearch': webSearch,
    'knowledge': knowledge,
    if (sourceIds.isNotEmpty) 'sourceIds': sourceIds,
    if (attachments.isNotEmpty) 'attachments': attachments,
    'model': ?model,
    if (profile.isNotEmpty) 'profile': profile,
    if (reviewOutline) 'reviewOutline': true,
  };
}

/// One raw server-sent event.
typedef SseFrame = ({String event, String data});

/// Splits a `text/event-stream` body into frames. Comment lines are
/// skipped; multi-line data is joined with newlines.
Stream<SseFrame> sseFrames(Stream<List<int>> bytes) async* {
  final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
  var event = 'message';
  final data = StringBuffer();
  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield (event: event, data: data.toString());
      event = 'message';
      data.clear();
    } else if (line.startsWith(':')) {
      continue;
    } else if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
  }
  if (data.isNotEmpty) yield (event: event, data: data.toString());
}

/// `/docs` endpoints (docs/DOCS_MODE.md §4).
class DocsApi {
  DocsApi({DocsTransport? transport, String? baseUrl})
    : _transport = transport ?? (() => AuthClient()),
      _base = '${baseUrl ?? AppConfig.apiBaseUrl}/docs';

  final DocsTransport _transport;
  final String _base;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_base$path').replace(queryParameters: query);

  static const _json = {'Content-Type': 'application/json'};

  /// Runs one request on a fresh client and closes it afterwards.
  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration timeout = DocConfig.requestTimeout,
  }) async {
    final client = _transport();
    try {
      final request = http.Request(method, _uri(path, query))
        ..headers.addAll(_json);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(timeout);
      if (response.statusCode >= 400) throw _error(response);
      return response;
    } finally {
      client.close();
    }
  }

  static ApiException _error(http.Response r) {
    final message = errorMessage(r.body, r.statusCode);
    final code = errorCode(r.body);
    return ApiException(
      r.statusCode == 429 && code == 'daily_limit'
          ? dailyLimitMessage(message)
          : r.statusCode == 409 && code == 'doc_running'
          ? DocStrings.docRunning
          : message,
      status: r.statusCode,
    );
  }

  static Map<String, dynamic> _map(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map<String, dynamic> ? j : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Unwraps `{doc: {...}}` or a bare doc object.
  static Doc _doc(String body) {
    final j = _map(body);
    final d = j['doc'];
    return Doc.fromJson(d is Map<String, dynamic> ? d : j);
  }

  /// Starts a document; returns its id (202).
  Future<String> create(DocRequest request) async {
    final r = await _send('POST', '', body: request.toJson());
    final j = _map(r.body);
    final id = j['id'] ?? (j['doc'] is Map ? (j['doc'] as Map)['id'] : null);
    if (id is! String || id.isEmpty) {
      throw const ApiException(DocStrings.startFailed);
    }
    return id;
  }

  Future<Doc> get(String id) async => _doc((await _send('GET', '/$id')).body);

  Future<List<Doc>> list({String? conversationId}) async {
    final r = await _send(
      'GET',
      '',
      query: conversationId == null ? null : {'conversationId': conversationId},
    );
    final j = jsonDecode(r.body);
    final raw = j is List ? j : (j is Map ? j['docs'] : null);
    return [
      for (final d in raw as List? ?? const [])
        if (d is Map<String, dynamic>) Doc.fromJson(d),
    ];
  }

  Future<void> rename(String id, String title) =>
      _send('PATCH', '/$id', body: {'title': title});

  Future<void> delete(String id) => _send('DELETE', '/$id');

  /// Starts writing after outline review, with the (edited) outline.
  Future<void> start(String id, {Map<String, dynamic>? outline}) =>
      _send('POST', '/$id/start', body: {'outline': ?outline});

  Future<void> resume(String id) => _send('POST', '/$id/resume', body: {});

  Future<void> cancel(String id) => _send('POST', '/$id/cancel', body: {});

  /// Manual edit; the server saves a revision.
  Future<void> saveSection(String id, String sectionId, String markdown) =>
      _send('PUT', '/$id/sections/$sectionId', body: {'markdown': markdown});

  /// Adds a pending section after [after] (null: first); returns its id.
  Future<String> addSection(
    String id, {
    required String? after,
    required String heading,
    required String goal,
  }) async {
    final r = await _send(
      'POST',
      '/$id/sections',
      body: {'after': after, 'heading': heading, 'goal': goal},
    );
    final sec = _map(r.body)['section'];
    final sid = sec is Map ? sec['sectionId'] : null;
    if (sid is! String || sid.isEmpty) {
      throw const ApiException(DocStrings.actionFailed);
    }
    return sid;
  }

  /// ASK AI: answers [question] about [quote] without touching the text.
  /// With [highlightId] the answer joins that passage's thread; otherwise
  /// the server creates the highlight. Returns the saved highlight.
  Future<DocHighlight> ask(
    String id, {
    required String sectionId,
    required String quote,
    required String question,
    String? highlightId,
    String prefix = '',
    String suffix = '',
  }) async {
    final r = await _send(
      'POST',
      '/$id/ask',
      timeout: DocConfig.askTimeout,
      body: {
        'sectionId': sectionId,
        'quote': quote,
        'question': question,
        'highlightId': ?highlightId,
        'prefix': prefix,
        'suffix': suffix,
      },
    );
    final h = _map(r.body)['highlight'];
    if (h is! Map<String, dynamic>) {
      throw const ApiException(DocStrings.askFailed);
    }
    return DocHighlight.fromJson(h);
  }

  /// Previews an edit of one passage (nothing is saved).
  Future<DocSelectionEdit> previewSelection(
    String id,
    String sectionId, {
    required DocSelectionOp op,
    required String quote,
    String? instruction,
  }) async {
    final r = await _send(
      'POST',
      '/$id/sections/$sectionId/selection',
      timeout: DocConfig.askTimeout,
      body: {'op': op.name, 'quote': quote, 'instruction': ?instruction},
    );
    return DocSelectionEdit.fromJson(_map(r.body));
  }

  /// Plans and writes one more section; streams like a rewrite (the
  /// snapshot first already holds the new pending section).
  Stream<DocEvent> continueWriting(String id, {String? hint}) => _stream(
    () => http.Request('POST', _uri('/$id/continue'))
      ..headers.addAll(_json)
      ..body = jsonEncode({'hint': ?hint}),
  );

  Future<List<DocRevision>> versions(String id, String sectionId) async {
    final r = await _send('GET', '/$id/versions/$sectionId');
    final j = jsonDecode(r.body);
    final raw = j is List ? j : (j is Map ? j['versions'] : null);
    return [
      for (final v in raw as List? ?? const [])
        if (v is Map<String, dynamic>) DocRevision.fromJson(v),
    ];
  }

  Future<List<DocHighlight>> highlights(String id) async {
    final r = await _send('GET', '/$id/highlights');
    final j = jsonDecode(r.body);
    final raw = j is List ? j : (j is Map ? j['highlights'] : null);
    return [
      for (final h in raw as List? ?? const [])
        if (h is Map<String, dynamic>) DocHighlight.fromJson(h),
    ];
  }

  Future<DocHighlight> addHighlight(String id, DocHighlight h) async {
    final r = await _send('POST', '/$id/highlights', body: h.toJson());
    final j = _map(r.body);
    final saved = j['highlight'] is Map<String, dynamic>
        ? j['highlight'] as Map<String, dynamic>
        : j;
    return DocHighlight.fromJson({...h.toJson(), ...saved});
  }

  Future<void> deleteHighlight(String id, String highlightId) =>
      _send('DELETE', '/$id/highlights/$highlightId');

  /// The server's export (`md` or `docx`) as bytes.
  Future<Uint8List> export(String id, String format) async {
    final r = await _send(
      'GET',
      '/$id/export',
      query: {'format': format},
      timeout: DocConfig.exportTimeout,
    );
    return r.bodyBytes;
  }

  /// Live events: `doc_snapshot` first, then progress. Cancelling the
  /// subscription closes the connection.
  Stream<DocEvent> events(String id) =>
      _stream(() => http.Request('GET', _uri('/$id/events')));

  /// Rewrites one section; streams that section's events.
  Stream<DocEvent> rewrite(
    String id,
    String sectionId, {
    required DocRewriteOp op,
    String? instruction,
    String? selection,
  }) => _stream(
    () => http.Request('POST', _uri('/$id/sections/$sectionId/rewrite'))
      ..headers.addAll(_json)
      ..body = jsonEncode({
        'op': op.name,
        'instruction': ?instruction,
        'selection': ?selection,
      }),
  );

  Stream<DocEvent> _stream(http.Request Function() build) {
    late final StreamController<DocEvent> out;
    http.Client? client;
    StreamSubscription<SseFrame>? sub;

    Future<void> run() async {
      final c = client = _transport();
      try {
        final request = build()..headers['Accept'] = 'text/event-stream';
        final response = await c
            .send(request)
            .timeout(DocConfig.requestTimeout);
        if (response.statusCode != 200) {
          throw _error(await http.Response.fromStream(response));
        }
        final frames = sseFrames(
          response.stream.timeout(
            DocConfig.streamIdle,
            onTimeout: (sink) => sink.addError(TimeoutException('idle')),
          ),
        );
        sub = frames.listen(
          (f) {
            final e = DocEvent.parse(f.event, f.data);
            if (e != null && !out.isClosed) out.add(e);
          },
          onError: (Object e, StackTrace s) {
            if (!out.isClosed) out.addError(e, s);
          },
          onDone: () {
            if (!out.isClosed) out.close();
            c.close();
          },
          cancelOnError: true,
        );
      } catch (e, s) {
        if (!out.isClosed) {
          out.addError(e, s);
          await out.close();
        }
        c.close();
      }
    }

    out = StreamController<DocEvent>(
      onListen: run,
      onCancel: () async {
        final s = sub;
        sub = null;
        if (s != null) await s.cancel().catchError((Object _) {});
        client?.close();
      },
    );
    return out.stream;
  }
}
