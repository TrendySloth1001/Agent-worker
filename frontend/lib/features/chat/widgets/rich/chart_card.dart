import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_chart.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'chart_fullscreen.dart';
import 'chart_model.dart';
import 'chart_table.dart';
import 'chart_views.dart';
import 'rich_frame.dart';

/// ```chart widget: bar, line, area, pie, donut, scatter and radar charts from
/// a small JSON object. Falls back to the raw source when it cannot be drawn.
class ChartCard extends StatefulWidget {
  const ChartCard({super.key, required this.source});

  final String source;

  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  late ChartSpec? _spec = ChartSpec.parse(widget.source);
  bool _table = false;

  @override
  void didUpdateWidget(ChartCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _spec = ChartSpec.parse(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    if (spec == null) return _RawFallback(source: widget.source);
    final title = spec.title.isEmpty
        ? WidgetKitStrings.chart
        : spec.title.toUpperCase();
    return RichCard(
      title: title,
      leading: AppIcon(
        _icon(spec.kind),
        size: AppIconSize.sm,
        color: context.palette.accent,
      ),
      actions: [
        RichAction(
          icon: _table ? _icon(spec.kind) : ChartIcons.table,
          label: _table ? ChartStrings.chart : ChartStrings.table,
          onTap: () async {
            setState(() => _table = !_table);
            return true;
          },
        ),
        RichAction.copy(text: spec.toCsv(), label: ChartStrings.copyData),
        RichAction(
          icon: ChartIcons.fullscreen,
          label: ChartStrings.fullscreen,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChartFullscreen(spec: spec, title: title),
              ),
            );
            return true;
          },
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: AnimatedSwitcher(
          duration: AppDurations.fast,
          child: _table
              ? ChartTable(key: const ValueKey('table'), spec: spec)
              : ChartPanel(key: const ValueKey('chart'), spec: spec),
        ),
      ),
    );
  }

  static AppIconData _icon(ChartKind k) => switch (k) {
    ChartKind.bar => ChartIcons.bar,
    ChartKind.line || ChartKind.area => ChartIcons.line,
    ChartKind.pie => ChartIcons.pie,
    ChartKind.donut => ChartIcons.donut,
    ChartKind.scatter => ChartIcons.scatter,
    ChartKind.radar => ChartIcons.radar,
  };
}

class _RawFallback extends StatelessWidget {
  const _RawFallback({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    return RichCard(
      title: WidgetKitStrings.chart,
      actions: [RichAction.copy(text: source)],
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          source,
          style: context.text.code.copyWith(fontSize: ChartSizes.rawFont),
        ),
      ),
    );
  }
}
