import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import 'md_blocks.dart';
import 'md_table_grid.dart';
import 'md_table_model.dart';

/// One card per row: the row label as the title, then a "HEADER  value"
/// line for every other column. Easier to read than narrow wrapped columns.
class MdTableCards extends StatelessWidget {
  const MdTableCards({
    super.key,
    required this.block,
    required this.plan,
    required this.order,
    required this.renderCell,
  });

  final MdTableBlock block;
  final MdTablePlan plan;
  final List<int> order;
  final MdCellBuilder renderCell;

  String _or(String s) => s.isEmpty ? MdTableStrings.empty : s;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final cols = block.header.length;
    return Column(
      key: MdTableLayout.cards.key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < order.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              color: i.isOdd
                  ? p.surfaceRaised.withValues(alpha: MdTableSizes.zebraAlpha)
                  : null,
              border: i == 0 ? null : Border(top: BorderSide(color: p.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(MdTableSizes.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: renderCell(
                      _or(block.rows[order[i]][0]),
                      header: true,
                    ),
                  ),
                  for (var c = 1; c < cols; c++) ...[
                    SizedBox(
                      height: c == 1
                          ? MdTableSizes.cardTitleGap
                          : MdTableSizes.cardLineGap,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: plan.labelWidth,
                          child: Padding(
                            // Lines the caption up with the value's first line.
                            padding: const EdgeInsets.only(top: AppSpacing.xxs),
                            child: Text(
                              mdPlain(block.header[c]).toUpperCase(),
                              style: t.caption.copyWith(color: p.textTertiary),
                            ),
                          ),
                        ),
                        const SizedBox(width: MdTableSizes.labelGap),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: renderCell(
                              _or(block.rows[order[i]][c]),
                              header: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
