import 'package:app/features/chat/widgets/github/git_graph_layout.dart';
import 'package:flutter_test/flutter_test.dart';

GraphNode n(String sha, [List<String> parents = const []]) =>
    GraphNode(sha, parents);

/// `from>to:kind` strings of the lines below row [i].
List<String> down(GraphLayout g, int i) => [
  for (final l in g.rows[i].down) '$l',
];

void main() {
  test('linear history stays in lane 0 with straight lines', () {
    final g = layoutGraph([
      n('c', ['b']),
      n('b', ['a']),
      n('a'),
    ], defaultHead: 'c');
    expect([for (final r in g.rows) r.lane], [0, 0, 0]);
    expect(down(g, 0), ['0>0:straight']);
    expect(down(g, 1), ['0>0:straight']);
    expect(g.rows[2].down, isEmpty);
    expect(g.width, 1);
    // The default branch keeps the reserved color.
    expect({for (final r in g.rows) r.color}, {0});
    expect(g.rows.any((r) => r.merge), isFalse);
  });

  test('one feature branch merged back', () {
    // m merges f into main; f and main both start at base.
    final g = layoutGraph([
      n('m', ['b', 'f']),
      n('f', ['base']),
      n('b', ['base']),
      n('base'),
    ], defaultHead: 'm');
    expect([for (final r in g.rows) r.lane], [0, 1, 0, 0]);
    expect(g.rows[0].merge, isTrue);
    // Main continues straight, the merged branch forks off to the right.
    expect(down(g, 0), ['0>0:straight', '0>1:fork']);
    expect(down(g, 1), ['0>0:straight', '1>1:straight']);
    // At base the feature lane closes into main.
    expect(down(g, 2), ['0>0:straight', '1>0:merge']);
    expect(g.rows[1].color, isNot(0));
    expect(g.rows[2].color, 0);
    expect(g.width, 2);
  });

  test('two concurrent branches from one base get their own lanes', () {
    final g = layoutGraph([
      n('x', ['base']),
      n('y', ['base']),
      n('z', ['base']),
      n('base'),
    ], defaultHead: 'x');
    expect([for (final r in g.rows) r.lane], [0, 1, 2, 0]);
    expect(down(g, 2), ['0>0:straight', '1>0:merge', '2>0:merge']);
    final colors = [for (final r in g.rows.take(3)) r.color];
    expect(colors.toSet(), hasLength(3));
    expect(colors.first, 0);
  });

  test('octopus merge forks one lane per extra parent', () {
    final g = layoutGraph([
      n('o', ['a', 'b', 'c']),
      n('b', ['a']),
      n('c', ['a']),
      n('a'),
    ], defaultHead: 'o');
    expect(g.rows[0].merge, isTrue);
    expect(down(g, 0), ['0>0:straight', '0>1:fork', '0>2:fork']);
    expect([for (final r in g.rows) r.lane], [0, 1, 2, 0]);
    // b keeps its own lane down to the branch point.
    expect(down(g, 1), ['0>0:straight', '1>1:straight', '2>2:straight']);
    expect(down(g, 2), ['0>0:straight', '1>0:merge', '2>0:merge']);
  });

  test('parents outside the loaded history do not open lanes', () {
    final g = layoutGraph([
      n('x', ['y', 'gone']),
      n('y', ['older']),
    ], defaultHead: 'x');
    expect(g.rows[0].danglingExtra, 1);
    expect(g.rows[0].danglingFirst, isFalse);
    expect(g.rows[1].danglingFirst, isTrue);
    expect(g.rows[1].down, isEmpty);
    expect(g.width, 1);
  });

  test('lanes compact with a shift when a lane to the left closes', () {
    // p forks from m1, q from the older mx.
    final g = layoutGraph([
      n('m2', ['m1']),
      n('p', ['m1']),
      n('q', ['mx']),
      n('m1', ['m0']),
      n('m0', ['mx']),
      n('mx'),
    ], defaultHead: 'm2');
    expect([for (final r in g.rows) r.lane], [0, 1, 2, 0, 0, 0]);
    // At m1 the p lane closed; q's lane moves from column 2 to 1.
    expect(g.rows[3].up.map((l) => '$l'), [
      '0>0:straight',
      '1>0:merge',
      '2>2:straight',
    ]);
    expect(down(g, 3), ['0>0:straight', '2>1:shift']);
    expect(g.rows[5].up.map((l) => '$l'), ['0>0:straight', '1>0:merge']);
  });

  test('a merge into a lane already waiting for the parent joins it', () {
    final g = layoutGraph([
      n('a', ['base']),
      n('m', ['b', 'base']),
      n('b', ['base']),
      n('base'),
    ], defaultHead: 'm');
    // m's second parent is already awaited by a's lane: no new lane.
    expect(down(g, 1), ['0>0:straight', '1>1:straight', '1>0:join']);
    expect(g.width, 2);
  });
}
