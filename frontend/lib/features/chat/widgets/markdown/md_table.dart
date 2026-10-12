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
import 'md_table_cards.dart';
import 'md_table_fullscreen.dart';
import 'md_table_grid.dart';
import 'md_table_model.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/widgets/m3_kit_extras.dart' show sentenceCase;

/// A markdown table that adapts to the screen. It is measured, then drawn as
/// a normal table (fits), a sideways scroller with a frozen first column, or
/// one card per row (long comparison text, very many columns). A header
/// toggle switches TABLE and CARDS, and an expand button opens it full
/// screen. Header taps sort.
class MdTable extends StatefulWidget {
  const MdTable({
    super.key,
    required this.block,
    required this.renderCell,
    this.streaming = false,
  });

  final MdTableBlock block;

  /// Renders one cell's inline markdown.
  final MdCellBuilder renderCell;

  /// While the reply is still arriving the layout is locked once the table
  /// has its header and a couple of rows, so it does not jump per token.
  final bool streaming;

  @override
  State<MdTable> createState() => _MdTableState();
}

class _MdTableState extends State<MdTable> {
  MdTableLayout? _locked;

  /// The reader's choice; null follows the automatic layout.
  MdTableLayout? _prefer;
  int _sortCol = -1;
  MdSort _sortDir = MdSort.none;

  void _sort(int c) => setState(() {
    final next = mdNextSort(c, _sortCol, _sortDir);
    _sortCol = next.$1;
    _sortDir = next.$2;
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final block = widget.block;
    final scaler = MediaQuery.textScalerOf(context);
    final body = t.bodySmall.copyWith(height: MdTableSizes.lineHeight);

    return LayoutBuilder(
      builder: (context, box) {
        final avail = box.maxWidth - AppBorder.thin * 2;
        final plan = planTable(
          block: block,
          avail: avail,
          body: body,
          head: t.caption,
          scaler: scaler,
          lock: widget.streaming ? _locked : null,
          prefer: _prefer,
        );
        if (!widget.streaming) {
          _locked = null;
        } else if (block.rows.length >= MdTableSizes.streamLockRows) {
          _locked = plan.layout;
        }
        final order = mdSortedOrder(block, _sortCol, _sortDir, plan.numeric);
        final cards = plan.layout == MdTableLayout.cards;

        // Stretch to the frame when the columns are narrower than it.
        final total = plan.total;
        final widths = total < avail
            ? [for (final w in plan.widths) w * avail / total]
            : plan.widths;

        Widget grid() => MdTableGrid(
          block: block,
          plan: plan,
          widths: widths,
          order: order,
          sortCol: _sortCol,
          sortDir: _sortDir,
          onSort: _sort,
          renderCell: widget.renderCell,
          sortable: block.rows.length >= StructLimits.sortableMinRows,
        );

        final Widget content = switch (plan.layout) {
          MdTableLayout.cards => MdTableCards(
            block: block,
            plan: plan,
            order: order,
            renderCell: widget.renderCell,
          ),
          MdTableLayout.fit => KeyedSubtree(
            key: MdTableLayout.fit.key,
            child: grid(),
          ),
          MdTableLayout.scroll => KeyedSubtree(
            key: MdTableLayout.scroll.key,
            child: MdStickyScroll(
              contentWidth: widths.fold<double>(0, (a, b) => a + b),
              firstWidth: widths[0],
              grid: grid,
            ),
          ),
        };

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
                height: MdTableSizes.headerHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: block.header.length > 1
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _ViewToggle(
                                  cards: cards,
                                  onChanged: (c) => setState(
                                    () => _prefer = c
                                        ? MdTableLayout.cards
                                        : MdTableLayout.fit,
                                  ),
                                ),
                              )
                            : Text(
                                sentenceCase(MdTableStrings.table),
                                style: t.caption.copyWith(
                                  fontFamily: AppFonts.body,
                                  letterSpacing: 0,
                                  fontSize: AppFontSize.label,
                                ),
                              ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: MdTableStrings.expand,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => MdTableFullscreen.open(
                          context,
                          block: block,
                          renderCell: widget.renderCell,
                          sortCol: _sortCol,
                          sortDir: _sortDir,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: AppIcon(
                            AppIcons.fullscreen,
                            size: AppIconSize.sm,
                            color: p.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    CopyAction(text: block.source),
                  ],
                ),
              ),
              content,
            ],
          ),
        );
      },
    );
  }
}

/// TABLE | CARDS segmented switch.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.cards, required this.onChanged});

  final bool cards;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget seg(String label, bool isCards) {
      final on = cards == isCards;
      return Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on
              ? null
              : () {
                  Haptics.tap();
                  onChanged(isCards);
                },
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: MdTableSizes.toggleHPad,
              vertical: MdTableSizes.toggleVPad,
            ),
            decoration: BoxDecoration(
              color: on ? p.surfaceHigh : Colors.transparent,
              borderRadius: BorderRadius.circular(MdTableSizes.toggleRadius),
            ),
            child: Text(
              sentenceCase(label),
              style: context.text.caption.copyWith(
                fontFamily: AppFonts.body,
                letterSpacing: 0,
                fontSize: AppFontSize.label,
                color: on ? p.textPrimary : p.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        seg(MdTableStrings.table, false),
        seg(MdTableStrings.cards, true),
      ],
    );
  }
}
