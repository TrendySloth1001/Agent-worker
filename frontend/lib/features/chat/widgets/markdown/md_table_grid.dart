import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'md_blocks.dart';
import 'md_table_model.dart';

/// Renders one cell's inline markdown. [numeric] cells are right-aligned
/// with tabular figures.
typedef MdCellBuilder =
    Widget Function(String text, {required bool header, bool numeric});

/// The table proper: Space Mono caps header (tap to sort), zebra rows,
/// fixed column widths from the plan.
class MdTableGrid extends StatelessWidget {
  const MdTableGrid({
    super.key,
    required this.block,
    required this.plan,
    required this.widths,
    required this.order,
    required this.sortCol,
    required this.sortDir,
    required this.onSort,
    required this.renderCell,
    this.sortable = true,
  });

  final MdTableBlock block;
  final MdTablePlan plan;

  /// Header taps sort (tables with a few rows only).
  final bool sortable;

  /// Final column widths (the plan's, stretched to fill the frame).
  final List<double> widths;
  final List<int> order;
  final int sortCol;
  final MdSort sortDir;
  final ValueChanged<int> onSort;
  final MdCellBuilder renderCell;

  bool _right(int c) => c > 0 && plan.numeric[c];

  Widget _head(BuildContext context, int c) {
    final p = context.palette;
    final active = sortCol == c && sortDir != MdSort.none;
    final style = context.text.caption.copyWith(
      color: active ? p.textPrimary : p.textSecondary,
    );
    final label = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MdTableSizes.cellHorizontal,
        vertical: MdTableSizes.cellVertical,
      ),
      child: _headRow(c, style, active, p),
    );
    if (!sortable) return label;
    return Semantics(
      button: true,
      selected: active,
      value: active
          ? (sortDir == MdSort.asc
                ? MdTableStrings.sortedAscending
                : MdTableStrings.sortedDescending)
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onSort(c);
        },
        child: label,
      ),
    );
  }

  Widget _headRow(int c, TextStyle style, bool active, AppPalette p) {
    return Row(
      mainAxisAlignment: _right(c)
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            mdPlain(block.header[c]).toUpperCase(),
            style: style,
            softWrap: true,
          ),
        ),
        if (active) ...[
          const SizedBox(width: MdTableSizes.sortIconGap),
          AppIcon(mdSortIcon(sortDir), size: AppIconSize.xs, color: p.accent),
        ],
      ],
    );
  }

  Widget _body(String text, int c) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: MdTableSizes.cellHorizontal,
      vertical: MdTableSizes.cellVertical,
    ),
    child: Align(
      alignment: _right(c) ? Alignment.centerRight : Alignment.centerLeft,
      child: renderCell(text, header: c == 0, numeric: _right(c)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cols = block.header.length;
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      columnWidths: {
        for (var c = 0; c < cols; c++) c: FixedColumnWidth(widths[c]),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: p.border, width: AppBorder.thin),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: p.surfaceHigh,
            border: Border(
              bottom: BorderSide(
                color: p.borderStrong,
                width: MdTableSizes.headerRule,
              ),
            ),
          ),
          children: [for (var c = 0; c < cols; c++) _head(context, c)],
        ),
        for (var i = 0; i < order.length; i++)
          TableRow(
            decoration: i.isOdd
                ? BoxDecoration(
                    color: p.surfaceRaised.withValues(
                      alpha: MdTableSizes.zebraAlpha,
                    ),
                  )
                : null,
            children: [
              for (var c = 0; c < cols; c++) _body(block.rows[order[i]][c], c),
            ],
          ),
      ],
    );
  }
}

/// Horizontal scroller with the first column frozen, an edge fade while
/// more content is hidden, and a one-time "swipe" hint.
class MdStickyScroll extends StatefulWidget {
  const MdStickyScroll({
    super.key,
    required this.contentWidth,
    required this.firstWidth,
    required this.grid,
  });

  final double contentWidth;
  final double firstWidth;

  /// Builds the grid (called twice: scrolling copy and the frozen overlay).
  final Widget Function() grid;

  @override
  State<MdStickyScroll> createState() => _MdStickyScrollState();
}

class _MdStickyScrollState extends State<MdStickyScroll> {
  final _controller = ScrollController();
  bool _scrolled = false;
  bool _everScrolled = false;
  bool _more = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update(ScrollMetrics m) {
    final scrolled = m.pixels > 1;
    final more = m.pixels < m.maxScrollExtent - 1;
    if (scrolled == _scrolled && more == _more) return;
    setState(() {
      _scrolled = scrolled;
      _more = more;
      _everScrolled = _everScrolled || scrolled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        _update(n.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0) _update(n.metrics);
          return false;
        },
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: widget.grid(),
            ),
            if (_scrolled) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: widget.firstWidth,
                child: ExcludeFocus(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: p.surface),
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: widget.contentWidth,
                        maxWidth: widget.contentWidth,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: widget.grid(),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: widget.firstWidth,
                top: 0,
                bottom: 0,
                width: MdTableSizes.stickyShadowWidth,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          p.borderStrong.withValues(
                            alpha: MdTableSizes.stickyShadowAlpha,
                          ),
                          p.borderStrong.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: MdTableSizes.fadeWidth,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _more ? 1 : 0,
                  duration: AppDurations.fast,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [p.surface.withValues(alpha: 0), p.surface],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _more && !_everScrolled ? MdTableSizes.hintAlpha : 0,
                  duration: AppDurations.fast,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: p.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            MdTableStrings.swipe,
                            style: t.caption.copyWith(color: p.textSecondary),
                          ),
                          AppIcon(
                            AppIcons.chevronRight,
                            size: AppIconSize.xs,
                            color: p.textSecondary,
                          ),
                        ],
                      ),
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
