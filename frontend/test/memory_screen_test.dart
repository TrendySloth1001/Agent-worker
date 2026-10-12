import 'package:app/core/constants/memory.dart';
import 'package:app/data/memory_api.dart';
import 'package:app/features/memory/memory_controller.dart';
import 'package:app/features/memory/memory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';

class _FakeMemoryApi implements MemoryApi {
  _FakeMemoryApi(this.items);

  final List<MemoryItem> items;
  final deleted = <String>[];

  @override
  Future<MemoryPage> list({String query = ''}) async =>
      MemoryPage(enabled: true, total: items.length, items: items);

  @override
  Future<void> delete(String id) async => deleted.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _items = [
  const MemoryItem(
    id: '1',
    text: 'Uses Neovim with a very long configuration that wraps lines',
    kind: 'preference',
    pinned: true,
  ),
  const MemoryItem(
    id: '2',
    text: 'Works on the sparky project',
    kind: 'project',
  ),
];

void main() {
  for (final (name, theme, scale) in renderCases) {
    testWidgets('memory renders at 360dp ($name)', (tester) async {
      final api = _FakeMemoryApi(_items);
      await pumpScreen(
        tester,
        MemoryScreen(controller: MemoryController(api: api)),
        height: 1600,
        theme: theme,
        textScale: scale,
      );
      expect(find.text(MemoryStrings.toggle), findsOneWidget);
      expect(find.text(_items[1].text), findsOneWidget);
      expect(find.text(MemoryStrings.pinned), findsOneWidget);
      await scrollThrough(tester, steps: 4);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('swiping a memory deletes it', (tester) async {
    final api = _FakeMemoryApi(_items);
    await pumpScreen(
      tester,
      MemoryScreen(controller: MemoryController(api: api)),
      height: 1600,
    );
    await tester.drag(find.text(_items[1].text), const Offset(-400, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.deleted, ['2']);
    expect(find.text(_items[1].text), findsNothing);
  });

  testWidgets('empty state shows when nothing is remembered', (tester) async {
    await pumpScreen(
      tester,
      MemoryScreen(controller: MemoryController(api: _FakeMemoryApi([]))),
      height: 1600,
    );
    expect(find.text(MemoryStrings.empty), findsOneWidget);
  });
}
