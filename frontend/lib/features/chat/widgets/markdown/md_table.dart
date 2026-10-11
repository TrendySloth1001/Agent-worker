import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/copy_action.dart';
import 'md_blocks.dart';

final _markup = RegExp(r'[*_`~]|\{\{icon:[^}]*\}\}|\[([^\]]*)\]\([^)]*\)');

/// A markdown table: rounded frame, raised header, row dividers only, and
/// horizontal scrolling when the columns do not fit.
class MdTable extends StatelessWidget {
  const MdTable({super.key, required this.block, required this.renderCell});

  final MdTableBlock block;

  /// Renders one cell's inline markdown.
  final Widget Function(String text, {required bool header}) renderCell;

  static final _mathRe = RegExp(r'\$[^$]+\$|\\\(|\\\[');

  /// Columns holding math: they keep their width (the table scrolls instead)
  /// so formulas stay readable.
  List<bool> _mathColumns() => [
    for (var c = 0; c < block.header.length; c++)
      [block.header[c], for (final r in block.rows) r[c]].any(_mathRe.hasMatch),
  ];

  /// Roughly how many characters a cell shows once rendered: TeX commands
  /// draw as one glyph, braces and script markers take no space.
  static int _visibleChars(String cell) {
    if (!_mathRe.hasMatch(cell)) {
      return cell.replaceAllMapped(_markup, (m) => m[1] ?? '').length;
    }
    return cell
        .replaceAll(RegExp(r'\\[a-zA-Z]+'), 'x')
        .replaceAll(RegExp(r'[{}^_$]|\\[()\[\]]'), '')
        .length;
  }

  List<double> _widths() {
    final cols = block.header.length;
    final mathCols = _mathColumns();
    return [
      for (var c = 0; c < cols; c++)
        () {
          var chars = 0;
          for (final cell in [
            block.header[c],
            for (final r in block.rows) r[c],
          ]) {
            chars = math.max(chars, _visibleChars(cell));
          }
          return (chars * MdSizes.tableCharWidth + AppSpacing.md * 2).clamp(
            MdSizes.tableMinColumn,
            mathCols[c] ? MdSizes.tableMaxMathColumn : MdSizes.tableMaxColumn,
          );
        }(),
    ];
  }

  /// Fills the screen when the table is narrow. When it is wider, shrinks
  /// the roomier text columns (never math columns) toward their minimum so
  /// all columns stay visible; if that is not enough, keeps the widths and
  /// the table scrolls sideways.
  static List<double> _fit(
    List<double> base,
    double total,
    double avail,
    List<bool> fixed,
  ) {
    if (total <= avail) return [for (final w in base) w * avail / total];
    var floor = 0.0;
    for (var c = 0; c < base.length; c++) {
      floor += fixed[c] ? base[c] : MdSizes.tableMinColumn;
    }
    if (floor > avail) return base;
    final slack = total - floor;
    final cut = total - avail;
    return [
      for (var c = 0; c < base.length; c++)
        fixed[c]
            ? base[c]
            : base[c] - (base[c] - MdSizes.tableMinColumn) * cut / slack,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final base = _widths();
    final total = base.fold<double>(0, (a, b) => a + b);

    Widget cell(String text, {required bool header}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: MdSizes.tableCellVertical,
      ),
      child: renderCell(text, header: header),
    );

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: AppSizes.codeHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(AppStrings.tableLabel, style: t.caption)),
                CopyAction(text: block.source),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, box) {
              final widths = _fit(base, total, box.maxWidth, _mathColumns());
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.top,
                  columnWidths: {
                    for (var c = 0; c < widths.length; c++)
                      c: FixedColumnWidth(widths[c]),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: p.border,
                      width: AppBorder.thin,
                    ),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: p.surfaceRaised),
                      children: [
                        for (final h in block.header) cell(h, header: true),
                      ],
                    ),
                    for (final r in block.rows)
                      TableRow(
                        children: [for (final c in r) cell(c, header: false)],
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
