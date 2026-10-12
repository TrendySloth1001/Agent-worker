import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/constants/widget_structure.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/copy_action.dart';
import 'md_blocks.dart';
import 'md_table_grid.dart';
import 'md_table_model.dart';

/// The table on its own page: pinch to zoom, drag in both directions, any
/// orientation. COPY gives Markdown or tab-separated text.
class MdTableFullscreen extends StatefulWidget {
  const MdTableFullscreen({
    super.key,
    required this.block,
    required this.renderCell,
    this.sortCol = -1,
    this.sortDir = MdSort.none,
  });

  final MdTableBlock block;
  final MdCellBuilder renderCell;
  final int sortCol;
  final MdSort sortDir;

  static Future<void> open(
    BuildContext context, {
    required MdTableBlock block,
    required MdCellBuilder renderCell,
    int sortCol = -1,
    MdSort sortDir = MdSort.none,
  }) {
    Haptics.tap();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MdTableFullscreen(
          block: block,
          renderCell: renderCell,
          sortCol: sortCol,
          sortDir: sortDir,
        ),
      ),
    );
  }

  @override
  State<MdTableFullscreen> createState() => _MdTableFullscreenState();
}

class _MdTableFullscreenState extends State<MdTableFullscreen> {
  late int _col = widget.sortCol;
  late MdSort _dir = widget.sortDir;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final plan = planTable(
      block: widget.block,
      avail: MediaQuery.sizeOf(context).width,
      body: t.bodySmall.copyWith(height: MdTableSizes.lineHeight),
      head: t.caption,
      scaler: MediaQuery.textScalerOf(context),
      wide: true,
    );
    final order = mdSortedOrder(widget.block, _col, _dir, plan.numeric);
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: MdTableSizes.fullscreenBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Haptics.tap();
                      Navigator.of(context).pop();
                    },
                    icon: AppIcon(
                      AppIcons.close,
                      color: p.textPrimary,
                      semanticLabel: 'Close',
                    ),
                  ),
                  Expanded(child: Text(MdTableStrings.table, style: t.label)),
                  CopyAction(
                    text: widget.block.source,
                    label: MdTableStrings.copyMarkdown,
                  ),
                  const SizedBox(width: MdTableSizes.chromeGap),
                  CopyAction(
                    text: mdTableToTsv(widget.block),
                    label: MdTableStrings.copyTsv,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                constrained: false,
                minScale: MdTableSizes.fullscreenMinScale,
                maxScale: MdTableSizes.fullscreenMaxScale,
                boundaryMargin: const EdgeInsets.all(
                  MdTableSizes.fullscreenMargin,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border.all(color: p.border),
                    ),
                    child: MdTableGrid(
                      block: widget.block,
                      plan: plan,
                      widths: plan.widths,
                      order: order,
                      sortCol: _col,
                      sortDir: _dir,
                      onSort: (c) => setState(() {
                        final next = mdNextSort(c, _col, _dir);
                        _col = next.$1;
                        _dir = next.$2;
                      }),
                      renderCell: widget.renderCell,
                      sortable:
                          widget.block.rows.length >=
                          StructLimits.sortableMinRows,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
