import 'dart:async';
import 'dart:convert';

import 'package:app/data/chat_event.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/doc_models.dart';
import 'package:app/data/docs_api.dart';
import 'package:app/features/chat/share/chat_export.dart';
import 'package:app/features/chat/share/chat_pdf.dart';
import 'package:app/features/docs/doc_controller.dart';
import 'package:app/features/docs/doc_diff.dart';
import 'package:app/features/docs/doc_export.dart';
import 'package:app/features/docs/doc_highlights.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/doc_fake.dart';

DocEvent? parse(String name, Object data) =>
    DocEvent.parse(name, jsonEncode(data));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DocEvent.parse', () {
    test('every event of the contract', () {
      final status =
          parse('doc_status', {
                'phase': 'sections',
                'done': 2,
                'total': 8,
                'elapsedMs': 1200,
                'etaMs': 30000,
              })!
              as DocStatusEvent;
      expect(
        [status.phase, status.done, status.total, status.etaMs],
        ['sections', 2, 8, 30000],
      );

      final outline =
          parse('doc_outline', {
                'title': 'T',
                'subtitle': 'S',
                'sections': [
                  {'id': 's1', 'heading': 'H1', 'goal': 'G', 'words': 450},
                  {'heading': 'no id is dropped'},
                ],
                'glossary': [
                  {'term': 'a', 'definition': 'b'},
                ],
              })!
              as DocOutlineEvent;
      expect(outline.sections.single.targetWords, 450);
      expect(outline.sections.single.words, 0);
      expect(outline.glossary.single.term, 'a');

      final sources =
          parse('doc_sources', {
                'citations': [
                  {
                    'id': 'W1',
                    'kind': 'web',
                    'title': 'x',
                    'url': 'u',
                    'site': 's',
                  },
                  'junk',
                ],
              })!
              as DocSourcesEvent;
      expect(sources.citations.single.id, 'W1');

      final start =
          parse('doc_section_start', {
                'sectionId': 's1',
                'model': 'm',
                'sourceIds': ['W1'],
              })!
              as DocSectionStartEvent;
      expect(
        [start.sectionId, start.model, start.sourceIds],
        [
          's1',
          'm',
          ['W1'],
        ],
      );

      final delta =
          parse('doc_section_delta', {'sectionId': 's1', 'text': 'hi'})!
              as DocSectionDeltaEvent;
      expect(delta.text, 'hi');
      expect(
        parse('doc_section_reset', {'sectionId': 's1'}),
        isA<DocSectionResetEvent>(),
      );

      final done =
          parse('doc_section_done', {
                'sectionId': 's1',
                'markdown': 'Body [W1].',
                'words': 2,
                'used': ['W1'],
                'evidence': [
                  {'tag': 'W1', 'claim': 'c', 'quote': 'q', 'score': 0.9},
                ],
                'images': [
                  {
                    'query': 'salt',
                    'url': 'https://img/salt.jpg',
                    'sourceUrl': 'https://wiki',
                    'title': 'Salt',
                    'site': 'wikimedia',
                  },
                  {'query': 'no url'},
                ],
              })!
              as DocSectionDoneEvent;
      expect(done.used, ['W1']);
      expect(done.evidence.single.score, 0.9);
      expect(done.images.single.query, 'salt');

      final failed =
          parse('doc_section_failed', {
                'sectionId': 's2',
                'message': 'boom',
                'retryable': false,
              })!
              as DocSectionFailedEvent;
      expect(failed.retryable, isFalse);

      final notice =
          parse('doc_notice', {'code': 'fallback', 'message': 'm'})!
              as DocNoticeEvent;
      expect(notice.code, 'fallback');

      final end =
          parse('doc_done', {
                'status': 'partial',
                'words': 3420,
                'used': ['W2', 'W1'],
                'latencyMs': 5,
              })!
              as DocDoneEvent;
      expect(
        [end.status, end.words, end.used],
        [
          'partial',
          3420,
          ['W2', 'W1'],
        ],
      );

      expect(
        (parse('doc_error', {'message': 'x'})! as DocErrorEvent).message,
        'x',
      );
      expect(
        (parse('doc_error', {
                  'error': {'message': 'nested'},
                })!
                as DocErrorEvent)
            .message,
        'nested',
      );
    });

    test('unknown events, bad JSON and missing fields', () {
      expect(parse('doc_future_thing', {'a': 1}), isNull);
      expect(DocEvent.parse('doc_status', 'not json'), isNull);
      expect(DocEvent.parse('doc_status', '[1,2]'), isNull);
      final s = parse('doc_status', {'extra': true})! as DocStatusEvent;
      expect(s.phase, '');
      expect(s.done, isNull);
      final d = parse('doc_done', {})! as DocDoneEvent;
      expect(d.status, DocStatus.done);
    });

    test('snapshot merges the outline and stored sections by id', () {
      final snap =
          parse('doc_snapshot', {
                'doc': {
                  'id': 'd1',
                  'title': 'Doc',
                  'status': 'writing',
                  'unknownField': {'x': 1},
                  'outline': {
                    'title': 'ignored, top-level wins',
                    'subtitle': 'Sub',
                    'sections': [
                      {
                        'id': 's1',
                        'heading': 'One',
                        'goal': 'g1',
                        'words': 300,
                      },
                      {
                        'id': 's2',
                        'heading': 'Two',
                        'goal': 'g2',
                        'words': 500,
                      },
                    ],
                    'glossary': [
                      {'term': 't', 'definition': 'd'},
                    ],
                  },
                  'sections': [
                    {
                      'sectionId': 's2',
                      'ord': 1,
                      'markdown': 'Two body',
                      'status': 'writing',
                      'words': 2,
                    },
                    {
                      'sectionId': 's1',
                      'ord': 0,
                      'markdown': 'One body [W1]',
                      'status': 'done',
                      'words': 3,
                      'usedIds': ['W1'],
                    },
                  ],
                  'sources': [
                    {
                      'id': 'W1',
                      'kind': 'web',
                      'title': 'w',
                      'url': 'u',
                      'site': 's',
                    },
                  ],
                },
              })!
              as DocSnapshotEvent;
      final doc = snap.doc;
      expect(doc.title, 'Doc');
      expect(doc.subtitle, 'Sub');
      expect(doc.sections.map((s) => s.id), ['s1', 's2']);
      expect(doc.sections[0].targetWords, 300);
      expect(doc.sections[0].words, 3);
      expect(doc.sections[0].isDone, isTrue);
      expect(doc.sections[1].isWriting, isTrue);
      expect(doc.references.single.id, 'W1');
      expect(doc.glossary.single.term, 't');
    });

    test('a References section from the server is not a body section', () {
      final doc = Doc.fromJson({
        'id': 'd',
        'sections': [
          {'sectionId': 's1', 'markdown': 'a'},
          {'sectionId': 'references', 'heading': 'References', 'markdown': 'x'},
        ],
      });
      expect(doc.body.map((s) => s.id), ['s1']);
    });

    test('meta link: list of statuses or a bare count', () {
      final a = DocLink.fromMeta({
        'doc': {
          'id': 'd',
          'title': 'T',
          'status': 'writing',
          'words': 10,
          'sections': ['done', 'writing', 'pending'],
        },
      })!;
      expect(a.sectionCount, 3);
      expect(a.sections[1], 'writing');
      final b = DocLink.fromMeta({
        'doc': {'id': 'd', 'sections': 6},
      })!;
      expect(b.sectionCount, 6);
      expect(b.sections, isEmpty);
      expect(DocLink.fromMeta({'doc': 'nope'}), isNull);
      expect(DocLink.fromMeta({}), isNull);
    });
  });

  test('sseFrames: comments, multi-line data, trailing frame', () async {
    final frames = await sseFrames(
      Stream.value(
        utf8.encode(
          ': keep-alive\n'
          'event: doc_status\ndata: {"a":\ndata: 1}\n\n'
          'data: {"b":2}\n\n'
          'event: doc_done\ndata: {}',
        ),
      ),
    ).toList();
    expect(frames.map((f) => f.event), ['doc_status', 'message', 'doc_done']);
    expect(frames.first.data, '{"a":\n1}');
  });

  group('DocController', () {
    test(
      'applies a scripted stream; deltas repaint only their section',
      () async {
        final server = FakeDocsServer()
          ..onConnect = [for (final (e, d) in scriptedRun()) sse(e, d)];
        final c = DocController('d1', api: server.api());
        var docNotifies = 0;
        c.addListener(() => docNotifies++);
        // Every section repaint, by id (ticks exist once someone listens).
        final ticks = <String, int>{};
        for (final id in ['s1', 's2', 's3']) {
          c
              .sectionListenable(id)
              .addListener(() => ticks[id] = (ticks[id] ?? 0) + 1);
        }
        c.attach();
        await pumpEventQueue();
        final doc = c.doc;
        expect(doc.title, 'Sodium and health');
        expect(doc.status, DocStatus.done);
        expect(doc.body.every((s) => s.isDone), isTrue);
        expect(doc.section('s2')!.markdown, contains('2 g a day [W2]'));
        expect(doc.section('s2')!.usedIds, ['W2', 'W1']);
        expect(doc.references.map((c) => c.id), ['W1', 'W2']);
        expect(doc.words, 26);
        // The second delta of each section only schedules a tick: no
        // controller notification per token.
        final events = scriptedRun().length;
        final deltas = scriptedRun().where((e) => e.$1 == 'doc_section_delta');
        expect(docNotifies, events - deltas.length);
        expect(ticks['s1'], greaterThan(0));
        expect(server.requests.first.url.path, '/docs/d1/events');
        await server.closeEvents();
        c.dispose();
      },
    );

    test('snapshot first, reconnect replaces state', () async {
      final server = FakeDocsServer()
        ..onConnect = [
          sse('doc_snapshot', {
            'doc': {
              'id': 'd1',
              'title': 'Snap',
              'status': 'writing',
              'outline': {
                'sections': [
                  {'id': 's1', 'heading': 'One'},
                ],
              },
              'sections': [
                {'sectionId': 's1', 'markdown': 'part', 'status': 'writing'},
              ],
            },
          }),
        ];
      final c = DocController('d1', api: server.api());
      c.attach();
      await pumpEventQueue();
      expect(c.loaded, isTrue);
      expect(c.doc.section('s1')!.markdown, 'part');
      server.emit('doc_section_delta', {'sectionId': 's1', 'text': ' more'});
      await pumpEventQueue();
      expect(c.doc.section('s1')!.markdown, 'part more');
      await server.closeEvents();
      await pumpEventQueue();
      expect(c.reconnecting, isTrue);
      c.dispose();
    });

    test('a section rewrite streams over the old text', () async {
      final server = FakeDocsServer()
        ..rewriteFrames = [
          sse('doc_section_start', {'sectionId': 's1'}),
          sse('doc_section_delta', {'sectionId': 's1', 'text': 'Shorter.'}),
          sse('doc_section_done', {
            'sectionId': 's1',
            'markdown': 'Shorter.',
            'words': 1,
          }),
        ];
      final c = DocController(
        'd1',
        api: server.api(),
        seed: Doc(
          id: 'd1',
          status: DocStatus.done,
          sections: [
            DocSection(id: 's1', markdown: 'Long text.', status: 'done'),
          ],
        ),
      );
      final ok = await c.rewrite('s1', DocRewriteOp.shorten);
      expect(ok, isTrue);
      expect(c.doc.section('s1')!.markdown, 'Shorter.');
      expect(c.doc.version, 1);
      final body = jsonDecode(server.bodies.last) as Map<String, dynamic>;
      expect(body['op'], 'shorten');
      expect(server.requests.last.url.path, '/docs/d1/sections/s1/rewrite');
      c.dispose();
    });
  });

  group('highlights', () {
    test('plain quote is wrapped', () {
      expect(
        applyHighlights('Salt raises blood pressure in most adults.', [
          'blood pressure',
        ]),
        'Salt raises ==blood pressure== in most adults.',
      );
    });

    test('quote across bold, citation tags stay outside the mark', () {
      const md = 'Adults should eat **under 2 g** a day [W2] at most.';
      final out = applyHighlights(md, ['eat under 2 g a day at most']);
      expect(out, 'Adults should ==eat under 2 g a day== [W2] ==at most==.');
    });

    test('chips leave object characters in the selection', () {
      expect(normalizeQuote('a day ￼  at\nmost'), 'a day at most');
    });

    test('unbalanced marks, code fences and missing quotes are left alone', () {
      const md = 'Some **bold text** here.\n```\ncode line\n```';
      expect(applyHighlights(md, ['Some bold']), md);
      expect(applyHighlights(md, ['code line']), md);
      expect(applyHighlights(md, ['not there']), md);
    });

    test('long quotes are split into marks the syntax accepts', () {
      final words = List.generate(60, (i) => 'word$i').join(' ');
      final out = applyHighlights(words, [words]);
      final marks = RegExp(r'==([^=]+)==').allMatches(out).toList();
      expect(marks.length, greaterThan(1));
      for (final m in marks) {
        expect(m[1]!.length, lessThanOrEqualTo(160));
      }
    });

    test('anchor keeps context around the quote', () {
      final h = anchorHighlight(
        DocSection(id: 's1', markdown: 'Alpha **beta** gamma delta [W1].'),
        'gamma',
        note: 'n',
      );
      expect(h.quote, 'gamma');
      expect(h.prefix, endsWith('beta '));
      expect(h.suffix, startsWith(' delta'));
      expect(h.toJson()['note'], 'n');
    });
  });

  Doc sampleDoc() => Doc(
    id: 'd1',
    title: 'Sodium and health',
    subtitle: 'What the evidence says',
    status: DocStatus.done,
    summary: 'Salt matters.',
    sources: const [
      Citation(
        id: 'W1',
        isKb: false,
        title: 'WHO',
        url: 'https://who.int',
        site: 'who.int',
      ),
      Citation(
        id: 'W2',
        isKb: false,
        title: 'AHA',
        url: 'https://heart.org',
        site: 'heart.org',
      ),
      Citation(
        id: 'W3',
        isKb: false,
        title: 'Unused',
        url: 'https://x.y',
        site: 'x.y',
      ),
      Citation(id: 'K1', isKb: true, title: 'My notes', url: '', site: ''),
    ],
    sections: [
      DocSection(
        id: 's1',
        heading: 'Why it matters',
        markdown: '## Why it matters\n\nFluids [W2]. Nerves [W1]. Notes [K1].',
        status: 'done',
        usedIds: ['W2', 'W1', 'K1'],
      ),
      DocSection(
        id: 's2',
        heading: 'Limits',
        markdown: 'Under 2 g {{icon:mdi:salt}} a day [W1].',
        status: 'done',
        usedIds: ['W1'],
      ),
      DocSection(id: 'references', heading: 'References', markdown: 'x'),
    ],
    glossary: const [DocGlossaryTerm(term: 'Na', definition: 'Sodium.')],
  );

  test('export: Markdown document', () {
    final md = docMarkdown(sampleDoc(), now: DateTime(2026, 10, 11, 14, 3));
    expect(md, startsWith('# Sodium and health\n\n*What the evidence says*'));
    expect(md, contains('## Abstract\n\nSalt matters.'));
    // The server's own heading line is not repeated.
    expect('## Why it matters'.allMatches(md).length, 1);
    // Tags become numbered superscript links; the numbers follow first use.
    expect(
      md,
      contains(
        'Fluids<sup>[1](#ref-1)</sup>. Nerves<sup>[2](#ref-2)</sup>. '
        'Notes<sup>[3](#ref-3)</sup>.',
      ),
    );
    expect(md, isNot(contains('[W')));
    expect(md, isNot(contains('{{icon')));
    // References: cited only, first-use order, named by site, KB marked.
    final refs = md.substring(md.indexOf('## References'));
    expect(refs.indexOf('heart'), lessThan(refs.indexOf('who')));
    expect(
      refs,
      contains('1. <a id="ref-1"></a>**heart** · AHA <https://heart.org>'),
    );
    expect(refs, contains('3. <a id="ref-3"></a>'));
    expect(refs, contains('My notes. Knowledge base.'));
    expect(refs, isNot(contains('Unused')));
    expect('## References'.allMatches(md).length, 1);
    expect(md, contains('## Glossary\n\n- **Na**: Sodium.'));
    expect(docFileName(sampleDoc(), 'md'), 'sodium-and-health.md');
  });

  test('export: document PDF and chat PDF (shared MarkdownPdfWriter)', () async {
    final pdf = await buildDocPdf(sampleDoc());
    expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    final chat = await buildChatPdf(
      ExportChat(
        title: 'Chat',
        modelName: (_) => 'Model',
        messages: [
          ChatMessage(role: Role.user, content: 'Hi **there**'),
          ChatMessage(
              role: Role.assistant,
              content:
                  '# H\n\n- a\n- b\n\n| x | y |\n|---|---|\n| 1 | 2 |\n\n```dart\nx\n```',
            )
            ..citations = const [
              Citation(
                id: 'W1',
                isKb: false,
                title: 't',
                url: 'https://u',
                site: 'u',
              ),
            ],
        ],
      ),
    );
    expect(ascii.decode(chat.sublist(0, 5)), '%PDF-');
    expect(chat.length, greaterThan(1000));
  });

  test('POST /docs sends the contract fields', () async {
    final server = FakeDocsServer();
    final id = await server.api().create(
      const DocRequest(
        prompt: 'Write a report on salt',
        conversationId: 'c1',
        length: 'long',
        webSearch: true,
        knowledge: false,
        attachments: ['f1'],
      ),
    );
    expect(id, 'd1');
    final body = jsonDecode(server.bodies.single) as Map<String, dynamic>;
    expect(body, {
      'prompt': 'Write a report on salt',
      'conversationId': 'c1',
      'length': 'long',
      'webSearch': true,
      'knowledge': false,
      'attachments': ['f1'],
    });
    expect(server.requests.single.method, 'POST');
    unawaited(Future<void>.value());
  });

  group('ask AI and passage edits', () {
    test('an answer lands on a persistent highlight thread', () async {
      final server = FakeDocsServer();
      final c = DocController('d1', api: server.api());
      final section = DocSection(
        id: 's1',
        heading: 'One',
        markdown: 'TLS 1.3 removed RSA key exchange.',
        status: DocSectionStatus.done,
      );
      c.doc.sections = [section];
      final pending = c.ask(section, 'RSA key exchange', 'Why?');
      // THINKING: the passage is already highlighted with the question.
      expect(c.highlights.single.color, 'ask');
      expect(c.pendingQuestion(c.highlights.single), 'Why?');
      final saved = await pending;
      expect(saved!.id, 'ask1');
      expect(c.highlights.single.thread.single.question, 'Why?');
      expect(c.highlights.single.thread.single.answer, 'Because [W1].');
      expect(c.pendingQuestion(c.highlights.single), isNull);
      // The section text was not rewritten.
      expect(section.markdown, 'TLS 1.3 removed RSA key exchange.');
      expect(server.requests.last.url.path, endsWith('/ask'));
    });

    test('a failed ask leaves no stray highlight', () async {
      final server = FakeDocsServer()..askStatus = 502;
      final c = DocController('d1', api: server.api());
      final section = DocSection(id: 's1', markdown: 'Some text here.');
      c.doc.sections = [section];
      expect(await c.ask(section, 'text here', 'Why?'), isNull);
      expect(c.highlights, isEmpty);
      expect(c.lastError, isNotNull);
    });

    test('word diff marks removed and added words', () {
      final d = docWordDiff('the quick brown fox', 'the slow brown fox')!;
      expect(d.where((p) => p.$1 == DocDiffKind.removed).single.$2, 'quick ');
      expect(d.where((p) => p.$1 == DocDiffKind.added).single.$2, 'slow ');
      expect(d.first, (DocDiffKind.same, 'the '));
      expect(docWordDiff('a ' * 500, 'b'), isNull);
    });
  });
}
