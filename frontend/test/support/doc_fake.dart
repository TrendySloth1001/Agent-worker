import 'dart:async';
import 'dart:convert';

import 'package:app/data/docs_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One SSE frame as the server writes it.
String sse(String event, Map<String, dynamic> data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

/// A scripted `/docs` backend. Event streams stay open until [closeEvents];
/// [emit] writes frames to the latest one.
class FakeDocsServer {
  FakeDocsServer({this.docId = 'd1'});

  final String docId;
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];
  final eventStreams = <StreamController<List<int>>>[];

  /// Frames sent as soon as an event stream opens (e.g. a snapshot).
  List<String> onConnect = const [];

  /// JSON for GET /docs/:id, PUT, etc.
  Map<String, dynamic> getBody = const {};
  List<Map<String, dynamic>> highlights = const [];
  int createStatus = 202;
  int askStatus = 201;

  /// Frames streamed back by a section rewrite.
  List<String> rewriteFrames = const [];

  DocsApi api() => DocsApi(transport: client, baseUrl: 'http://fake');

  http.Client client() => MockClient.streaming((req, body) async {
    requests.add(req);
    bodies.add(await body.bytesToString());
    final path = req.url.path;
    http.StreamedResponse json(Object o, [int status = 200]) =>
        http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(o))),
          status,
          headers: const {'content-type': 'application/json'},
        );
    if (path.endsWith('/events')) {
      final c = StreamController<List<int>>();
      eventStreams.add(c);
      for (final f in onConnect) {
        c.add(utf8.encode(f));
      }
      return http.StreamedResponse(
        c.stream,
        200,
        headers: const {'content-type': 'text/event-stream'},
      );
    }
    if (path.endsWith('/rewrite')) {
      return http.StreamedResponse(
        Stream.fromIterable([for (final f in rewriteFrames) utf8.encode(f)]),
        200,
      );
    }
    if (path.endsWith('/ask')) {
      if (askStatus != 201) {
        return json({'error': {'message': 'down'}}, askStatus);
      }
      final q = jsonDecode(bodies.last) as Map<String, dynamic>;
      return json({
        'highlight': {
          'id': 'ask1',
          'sectionId': q['sectionId'],
          'quote': q['quote'],
          'color': 'ask',
          'thread': [
            {'id': 'q1', 'q': q['question'], 'a': 'Because [W1].', 'at': ''},
          ],
        },
      }, 201);
    }
    if (path.endsWith('/highlights')) {
      if (req.method == 'POST') {
        return json({'id': 'h${requests.length}'});
      }
      return json({'highlights': highlights});
    }
    if (req.method == 'POST' && path == '/docs') {
      return json({'id': docId}, createStatus);
    }
    return json(getBody);
  });

  void emit(String event, Map<String, dynamic> data) =>
      eventStreams.last.add(utf8.encode(sse(event, data)));

  /// Not awaited: a stream nobody listens to any more never reports done.
  Future<void> closeEvents() async {
    for (final c in eventStreams) {
      unawaited(c.close());
    }
  }
}

/// A scripted run: outline → sources → N × (start, deltas, done) → done.
List<(String, Map<String, dynamic>)> scriptedRun() => [
  ('doc_status', {'phase': 'outline', 'done': 0, 'total': 3, 'elapsedMs': 100}),
  (
    'doc_outline',
    {
      'title': 'Sodium and health',
      'subtitle': 'What the evidence says',
      'glossary': [
        {'term': 'mmHg', 'definition': 'Millimetres of mercury.'},
      ],
      'sections': [
        {
          'id': 's1',
          'heading': 'Why sodium matters',
          'goal': 'Explain the role of sodium.',
          'words': 300,
          'visual': 'none',
        },
        {
          'id': 's2',
          'heading': 'How much is too much',
          'goal': 'Give the limits.',
          'words': 400,
        },
        {
          'id': 's3',
          'heading': 'Key takeaways',
          'goal': 'Summarise.',
          'words': 150,
        },
      ],
    },
  ),
  (
    'doc_sources',
    {
      'citations': [
        {
          'id': 'W1',
          'kind': 'web',
          'title': 'WHO sodium fact sheet',
          'url': 'https://who.int/sodium',
          'site': 'who.int',
        },
        {
          'id': 'W2',
          'kind': 'web',
          'title': 'AHA guidance',
          'url': 'https://heart.org/salt',
          'site': 'heart.org',
        },
      ],
    },
  ),
  ('doc_status', {'phase': 'sections', 'done': 0, 'total': 3, 'etaMs': 60000}),
  for (final (sid, text, used) in [
    (
      's1',
      'Sodium keeps fluids in balance [W1]. It also drives nerves.',
      ['W1'],
    ),
    (
      's2',
      'Adults should eat under 2 g a day [W2]. Most eat double [W1].',
      ['W2', 'W1'],
    ),
    ('s3', '- Eat less salt.\n- Read labels.', <String>[]),
  ]) ...[
    ('doc_section_start', {'sectionId': sid, 'model': 'm', 'sourceIds': used}),
    for (final part in _split(text))
      ('doc_section_delta', {'sectionId': sid, 'text': part}),
    (
      'doc_section_done',
      {
        'sectionId': sid,
        'markdown': text,
        'words': text.split(' ').length,
        'used': used,
        'evidence': [
          for (final u in used)
            {'tag': u, 'claim': 'c', 'quote': 'q', 'score': 0.8},
        ],
        'images': <Object>[],
      },
    ),
  ],
  (
    'doc_done',
    {
      'status': 'done',
      'words': 26,
      'used': ['W1', 'W2'],
      'latencyMs': 900,
    },
  ),
];

List<String> _split(String text) {
  final mid = text.length ~/ 2;
  return [text.substring(0, mid), text.substring(mid)];
}
