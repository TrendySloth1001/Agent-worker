import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import 'md_blocks.dart';

/// How a table is drawn.
enum MdTableLayout {
  /// Normal table, every column visible.
  fit,

  /// Wider than the screen: scrolls sideways, first column frozen.
  scroll,

  /// One card per row: row label as title, then "header: value" lines.
  cards;

  /// Test hook: the body of each layout carries this key.
  Key get key => ValueKey('mdTable.$name');
}

enum MdSort { none, asc, desc }

/// The measured layout of one table at one width.
class MdTablePlan {
  const MdTablePlan({
    required this.layout,
    required this.widths,
    required this.numeric,
    required this.labelWidth,
  });

  final MdTableLayout layout;

  /// Column widths, padding included (unused for cards).
  final List<double> widths;

  /// Columns whose body cells are all numbers.
  final List<bool> numeric;

  /// Width of the "header" label in a card line.
  final double labelWidth;

  double get total => widths.fold<double>(0, (a, b) => a + b);
}

final _markup = RegExp(r'[*_`~]|\{\{icon:[^}]*\}\}|\[([^\]]*)\]\([^)]*\)');
final _mathRe = RegExp(r'\$[^$]+\$|\\\(|\\\[');
final _blankRe = RegExp(r'^(|-|–|—|n/?a|\?)$', caseSensitive: false);
final _numberRe = RegExp(
  r'^[~≈<>≥≤+\-−±]?\s*[$€£¥₹]?'
  r'\s*[+\-−]?\d[\d,. ]*\d?\s*(?:[kKmMbB]\b|%|[a-zA-Zµ°/]{1,5}\d?)?$',
);

/// A cell as plain text: markup, icon tags and link targets removed.
String mdPlain(String cell) =>
    cell.replaceAllMapped(_markup, (m) => m[1] ?? '').trim();

bool _isMath(String cell) => _mathRe.hasMatch(cell);

/// Roughly how many characters a math cell draws: TeX commands are one
/// glyph, braces and script markers take no space.
int _mathChars(String cell) => cell
    .replaceAll(RegExp(r'\\[a-zA-Z]+'), 'x')
    .replaceAll(RegExp(r'[{}^_$]|\\[()\[\]]'), '')
    .length;

/// Columns whose non-blank body cells are all numbers (and at least one).
List<bool> mdNumericColumns(MdTableBlock block) => [
  for (var c = 0; c < block.header.length; c++)
    () {
      var seen = 0;
      for (final r in block.rows) {
        final s = mdPlain(r[c]);
        if (_blankRe.hasMatch(s)) continue;
        if (!_numberRe.hasMatch(s)) return false;
        seen++;
      }
      return seen > 0;
    }(),
];

/// The first number in [cell], with k/M/B suffixes expanded.
double? mdParseNumber(String cell) {
  final s = mdPlain(cell).replaceAll('−', '-');
  final m = RegExp(r'-?\d[\d,]*(?:\.\d+)?\s*([kKmMbB])?\b').firstMatch(s);
  if (m == null) return null;
  final raw = m[0]!.replaceAll(RegExp(r'[,\s]'), '');
  final digits = raw.replaceAll(RegExp(r'[kKmMbB]$'), '');
  var v = double.tryParse(digits);
  if (v == null) return null;
  switch (m[1]?.toLowerCase()) {
    case 'k':
      v *= 1e3;
    case 'm':
      v *= 1e6;
    case 'b':
      v *= 1e9;
  }
  return v;
}

/// Row indexes in display order. Blank cells always sort last; ties keep
/// the original order.
List<int> mdSortedOrder(
  MdTableBlock block,
  int col,
  MdSort dir,
  List<bool> numeric,
) {
  final order = List<int>.generate(block.rows.length, (i) => i);
  if (dir == MdSort.none || col < 0 || col >= block.header.length) {
    return order;
  }
  final sign = dir == MdSort.asc ? 1 : -1;
  int cmp(int a, int b) {
    final x = block.rows[a][col];
    final y = block.rows[b][col];
    final bx = _blankRe.hasMatch(mdPlain(x));
    final by = _blankRe.hasMatch(mdPlain(y));
    if (bx || by) return bx == by ? a - b : (bx ? 1 : -1);
    int c;
    if (numeric[col]) {
      c = (mdParseNumber(x) ?? 0).compareTo(mdParseNumber(y) ?? 0);
    } else {
      c = mdPlain(x).toLowerCase().compareTo(mdPlain(y).toLowerCase());
    }
    return c == 0 ? a - b : c * sign;
  }

  order.sort(cmp);
  return order;
}

/// Next sort state when a header is tapped: asc, desc, original.
(int, MdSort) mdNextSort(int col, int current, MdSort dir) {
  if (col != current) return (col, MdSort.asc);
  return switch (dir) {
    MdSort.none => (col, MdSort.asc),
    MdSort.asc => (col, MdSort.desc),
    MdSort.desc => (-1, MdSort.none),
  };
}

/// The table as tab-separated text (header first), markup removed.
String mdTableToTsv(MdTableBlock block) {
  String cell(String s) => mdPlain(s).replaceAll(RegExp(r'[\t\r\n]+'), ' ');
  String row(List<String> r) => r.map(cell).join(MdTableStrings.tabSeparator);
  return [row(block.header), for (final r in block.rows) row(r)].join('\n');
}

double _measure(String text, TextStyle style, TextScaler scaler) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// Measures the table and picks its layout.
///
/// [lock] keeps a streaming table from changing its mind: fit may only grow
/// into scroll, scroll and cards stay. [prefer] is the reader's choice
/// (cards or a table). [wide] is the full-screen view: a scrolling table
/// with generous columns.
MdTablePlan planTable({
  required MdTableBlock block,
  required double avail,
  required TextStyle body,
  required TextStyle head,
  required TextScaler scaler,
  MdTableLayout? lock,
  MdTableLayout? prefer,
  bool wide = false,
}) {
  final cols = block.header.length;
  final numeric = mdNumericColumns(block);
  const pad = MdTableSizes.cellHorizontal * 2;
  final sortSlot =
      AppIconSize.xs + MdTableSizes.sortIconGap; // header arrow, reserved

  // Natural (unwrapped) width of each column, padding included.
  final nat = <double>[];
  for (var c = 0; c < cols; c++) {
    var w = _measure(mdPlain(block.header[c]).toUpperCase(), head, scaler);
    w = (w + sortSlot) * MdTableSizes.measureSlack;
    for (final r in block.rows) {
      final cell = r[c];
      final cw = _isMath(cell)
          ? _mathChars(cell) * MdTableSizes.charWidth
          : _measure(
                  mdPlain(cell),
                  c == 0 ? body.copyWith(fontWeight: FontWeight.w700) : body,
                  scaler,
                ) *
                MdTableSizes.measureSlack;
      w = math.max(w, cw);
    }
    nat.add(w + pad);
  }
  final mathCol = [
    for (var c = 0; c < cols; c++)
      [block.header[c], for (final r in block.rows) r[c]].any(_isMath),
  ];

  double cap(int c, double normal) =>
      mathCol[c] ? MdTableSizes.mathMaxColumn : normal;
  const minCol = MdTableSizes.minColumn;
  List<double> clampTo(double Function(int) maxOf) => [
    for (var c = 0; c < cols; c++)
      nat[c].clamp(minCol, math.max(minCol, maxOf(c))),
  ];

  // Header label width for cards.
  var label = 0.0;
  for (var c = 1; c < cols; c++) {
    label = math.max(
      label,
      _measure(mdPlain(block.header[c]).toUpperCase(), head, scaler),
    );
  }
  label = (label * MdTableSizes.measureSlack).clamp(
    MdTableSizes.labelMinWidth,
    math.min(MdTableSizes.labelMaxWidth, avail * MdTableSizes.labelShare),
  );

  MdTablePlan make(MdTableLayout l, List<double> w) =>
      MdTablePlan(layout: l, widths: w, numeric: numeric, labelWidth: label);

  List<double> scrollWidths(double normalMax) {
    final w = clampTo(
      (c) => cap(c, c == 0 ? MdTableSizes.firstMaxColumn : normalMax),
    );
    if (!wide && cols > 1) {
      w[0] = math.min(w[0], avail * MdTableSizes.stickyMaxShare);
    }
    return w;
  }

  if (wide) {
    return make(
      MdTableLayout.scroll,
      scrollWidths(MdTableSizes.fullscreenMaxColumn),
    );
  }

  // Fit: widths at their natural size, wrapped a little if that is enough.
  List<double>? fitWidths() {
    final base = clampTo(
      (c) =>
          cap(c, c == 0 ? MdTableSizes.firstMaxColumn : MdTableSizes.maxColumn),
    );
    final total = base.fold<double>(0, (a, b) => a + b);
    if (total <= avail) {
      return [for (final w in base) w * avail / total];
    }
    if (cols > 2 && (total - avail) / total > MdTableSizes.shrinkTolerance) {
      return null;
    }
    var cut = total - avail;
    final out = [...base];
    // Wrap the value columns first, the row label last. Math keeps its size.
    for (final group in [
      [for (var c = 1; c < cols; c++) c],
      [0],
    ]) {
      final slack = group.fold<double>(
        0,
        (a, c) => a + (mathCol[c] ? 0 : out[c] - minCol),
      );
      if (slack <= 0) continue;
      final take = math.min(cut, slack);
      for (final c in group) {
        if (mathCol[c]) continue;
        out[c] -= (out[c] - minCol) * take / slack;
      }
      cut -= take;
      if (cut <= 0) break;
    }
    return cut > 0.5 ? null : out;
  }

  final fit = fitWidths();
  final scroll = scrollWidths(MdTableSizes.scrollMaxColumn);
  final scrollTotal = scroll.fold<double>(0, (a, b) => a + b);

  MdTableLayout auto() {
    if (fit != null) return MdTableLayout.fit;
    final valueCols = cols - 1;
    final longProse =
        valueCols >= MdTableSizes.comparisonMinValueColumns &&
        valueCols <= MdTableSizes.comparisonMaxValueColumns &&
        [
          for (var c = 1; c < cols; c++) nat[c],
        ].any((w) => w > MdTableSizes.longCell);
    if (longProse) return MdTableLayout.cards;
    final feasible =
        cols <= MdTableSizes.maxScrollColumns &&
        scrollTotal <= avail * MdTableSizes.maxScrollFactor;
    return feasible ? MdTableLayout.scroll : MdTableLayout.cards;
  }

  var layout = auto();
  if (prefer == MdTableLayout.cards) {
    layout = MdTableLayout.cards;
  } else if (prefer != null) {
    layout = fit != null ? MdTableLayout.fit : MdTableLayout.scroll;
  } else if (lock != null) {
    layout = switch (lock) {
      MdTableLayout.cards => MdTableLayout.cards,
      MdTableLayout.scroll => MdTableLayout.scroll,
      MdTableLayout.fit =>
        layout == MdTableLayout.fit ? MdTableLayout.fit : MdTableLayout.scroll,
    };
  }
  return make(layout, layout == MdTableLayout.fit ? (fit ?? scroll) : scroll);
}

/// Icon for the active sort direction.
AppIconData mdSortIcon(MdSort dir) =>
    dir == MdSort.desc ? AppIcons.sortDescending : AppIcons.sortAscending;
