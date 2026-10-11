import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/rich_cards.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../markdown/inline_icon.dart';
import 'rich_frame.dart';

class FlowTile {
  const FlowTile(this.value, this.label);
  final String value, label;
}

class FlowStage {
  const FlowStage.row(this.tiles)
    : title = '',
      subtitle = '',
      value = '',
      style = '',
      iconSet = null,
      iconName = null;

  const FlowStage.box({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.style,
    this.iconSet,
    this.iconName,
  }) : tiles = const [];

  final List<FlowTile> tiles;
  final String title, subtitle, value, style;
  final String? iconSet, iconName;

  bool get isRow => tiles.isNotEmpty;
}

class FlowData {
  const FlowData({
    required this.title,
    required this.stages,
    required this.source,
  });
  final String title, source;
  final List<FlowStage> stages;
}

final _flowIcon = RegExp(
  r'^\{\{icon:([a-z0-9]+(?:-[a-z0-9]+)*):([a-z0-9]+(?:-[a-z0-9]+)*)\}\}\s*',
);

/// Parses a ```flow block; null when it has no stages.
FlowData? parseFlow(String src) {
  var title = '';
  final stages = <FlowStage>[];
  for (final raw in src.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trim();
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim().toLowerCase();
    final value = line.substring(idx + 1).trim();
    if (value.isEmpty) continue;
    switch (key) {
      case 'title':
        title = value;
      case 'row':
        final tiles = <FlowTile>[];
        for (final part in value.split(';')) {
          final bits = part.split('|').map((e) => e.trim()).toList();
          if (bits.first.isEmpty) continue;
          tiles.add(FlowTile(bits.first, bits.length > 1 ? bits[1] : ''));
        }
        if (tiles.isNotEmpty) stages.add(FlowStage.row(tiles));
      case 'box':
        var text = value;
        String? set, name;
        final m = _flowIcon.firstMatch(text);
        if (m != null) {
          set = m[1];
          name = m[2];
          text = text.substring(m.end);
        }
        final bits = text.split('|').map((e) => e.trim()).toList();
        if (bits.first.isEmpty) continue;
        var style = '';
        var val = '';
        var sub = bits.length > 1 ? bits[1] : '';
        if (bits.length > 2) {
          // "TITLE | value | style" or "TITLE | subtitle | style".
          val = bits[1];
          sub = '';
          style = bits[2].toLowerCase();
        }
        stages.add(
          FlowStage.box(
            title: bits.first,
            subtitle: sub,
            value: val,
            style: style,
            iconSet: set,
            iconName: name,
          ),
        );
    }
  }
  if (stages.isEmpty) return null;
  return FlowData(title: title, stages: stages, source: src);
}

/// ```flow block: stages joined by down arrows.
class FlowCard extends StatelessWidget {
  const FlowCard({super.key, required this.data});

  final FlowData data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final stages = data.stages;
    return RichCard(
      title: data.title.isEmpty ? FlowStrings.flow : data.title.toUpperCase(),
      leading: AppIcon(AskIcons.flow, size: AppIconSize.sm, color: p.accent),
      actions: [RichAction.copy(text: data.source, label: AppStrings.copy)],
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < stages.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Center(
                    child: AppIcon(
                      AskIcons.arrowDown,
                      size: AskSizes.arrow,
                      color: p.textTertiary,
                    ),
                  ),
                ),
              stages[i].isRow
                  ? _RowStage(tiles: stages[i].tiles)
                  : _BoxStage(stage: stages[i], text: t),
            ],
          ],
        ),
      ),
    );
  }
}

class _RowStage extends StatelessWidget {
  const _RowStage({required this.tiles});

  final List<FlowTile> tiles;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final tile in tiles)
          Container(
            constraints: const BoxConstraints(
              minWidth: AskSizes.tileMinWidth,
              maxWidth: AskSizes.tileMaxWidth,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: p.border, width: AppBorder.thin),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tile.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.metric,
                ),
                if (tile.label.isNotEmpty)
                  Text(
                    tile.label.toUpperCase(),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BoxStage extends StatelessWidget {
  const _BoxStage({required this.stage, required this.text});

  final FlowStage stage;
  final AppTextTheme text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = stage.style == 'accent';
    final dark = stage.style == 'dark';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dark ? p.surfaceHigh : p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: accent ? p.accent : p.border,
          width: AppBorder.thin,
        ),
      ),
      child: Row(
        children: [
          if (stage.iconSet != null && stage.iconName != null) ...[
            InlineIcon(
              set: stage.iconSet!,
              name: stage.iconName!,
              size: AskSizes.flowIcon,
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.title,
                  style: text.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (stage.value.isNotEmpty)
                  Text(
                    stage.value,
                    style: text.metric.copyWith(
                      color: accent ? p.accent : p.textPrimary,
                    ),
                  ),
                if (stage.subtitle.isNotEmpty)
                  Text(stage.subtitle, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
