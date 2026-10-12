import 'package:app/core/constants/m3_copy.dart';
import 'package:app/data/kb_source.dart';
import 'package:app/data/knowledge_api.dart';
import 'package:app/features/knowledge/knowledge_controller.dart';
import 'package:app/features/knowledge/knowledge_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';

class _FakeKb implements KnowledgeApi {
  _FakeKb(this.items);

  final List<KbSource> items;

  @override
  Future<List<KbSource>> list() async => items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KbSource _source(
  String id,
  String status, {
  String type = 'web',
  String? title,
  String? error,
  int? done,
  int? total,
}) => KbSource(
  id: id,
  type: type,
  uri: 'https://example.com/docs/$id/with/a/very/long/address/that/wraps',
  title: title,
  status: status,
  progressDone: done,
  progressTotal: total,
  docCount: 12,
  chunkCount: 340,
  error: error,
  lastIngestedAt: null,
);

void main() {
  for (final (name, theme, scale) in renderCases) {
    testWidgets('knowledge renders sources at 360dp ($name)', (tester) async {
      final c = KnowledgeController(
        _FakeKb([
          _source('a', 'ready', title: 'Flutter documentation'),
          _source('b', 'running', type: 'github', done: 3, total: 40),
          _source('c', 'failed', type: 'reddit', error: 'Rate limited'),
        ]),
      );
      await pumpScreen(
        tester,
        KnowledgeScreen(controller: c),
        theme: theme,
        textScale: scale,
        height: 1400,
      );
      expect(find.text('Flutter documentation'), findsOneWidget);
      expect(find.text('Running 3/40'), findsOneWidget);
      expect(find.text(KnowledgeCopy.failed), findsOneWidget);
      expect(find.text(KnowledgeCopy.addSource), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('knowledge empty state offers adding a source', (tester) async {
    final c = KnowledgeController(_FakeKb([]));
    await pumpScreen(tester, KnowledgeScreen(controller: c), height: 1000);
    expect(find.text(KnowledgeCopy.emptyTitle), findsOneWidget);
    await tester.tap(find.text(KnowledgeCopy.addSource));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(KnowledgeCopy.add), findsOneWidget);
    expect(find.text(KnowledgeCopy.limit), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
