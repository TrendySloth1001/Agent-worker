import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_playful.dart';
import '../../../../core/constants/widget_structure.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

class CompareOption {
  const CompareOption(this.name, this.tagline, this.pick, this.pros, this.cons);
  final String name, tagline;
  final bool pick;
  final List<String> pros, cons;
}

class CompareData {
  const CompareData(this.title, this.options);
  final String title;
  final List<CompareOption> options;
}

/// Parses a ```compare block:
/// `option: Name | tagline | pick` then `+ pro` / `- con` lines.
/// A single option works as a pros/cons card. Null when there is no option
/// with at least one point.
CompareData? parseCompare(String src) {
  var title = '';
  final opts = <CompareOption>[];
  String? name;
  var tagline = '';
  var pick = false;
  var pros = <String>[], cons = <String>[];

  void flush() {
    final n = name;
    if (n != null && (pros.isNotEmpty || cons.isNotEmpty)) {
      opts.add(CompareOption(n, tagline, pick, pros, cons));
    }
    name = null;
    tagline = '';
    pick = false;
    pros = <String>[];
    cons = <String>[];
  }

  for (final line in playfulLines(src)) {
    final kv = playfulKeyValue(line);
    if (kv != null && kv.$1 == 'title') {
      title = kv.$2;
    } else if (kv != null && (kv.$1 == 'option' || kv.$1 == 'opt')) {
      flush();
      if (opts.length >= StructLimits.options) break;
      final parts = kv.$2.split('|').map((e) => e.trim()).toList();
      if (parts.isEmpty || parts[0].isEmpty) continue;
      name = parts[0];
      tagline = parts.length > 1 ? parts[1] : '';
      pick = parts.length > 2 && parts[2].toLowerCase() == 'pick';
    } else if (name != null && line.startsWith('+')) {
      final t = line.substring(1).trim();
      if (t.isNotEmpty && pros.length < StructLimits.points) pros.add(t);
    } else if (name != null && (line.startsWith('-') || line.startsWith('–'))) {
      final t = line.substring(1).trim();
      if (t.isNotEmpty && cons.length < StructLimits.points) cons.add(t);
    }
  }
  flush();
  if (opts.isEmpty) return null;
  return CompareData(title, opts);
}

/// ```compare block: one card per option with pros and cons.
class CompareCard extends StatefulWidget {
  const CompareCard({super.key, required this.source});

  final String source;

  @override
  State<CompareCard> createState() => _CompareCardState();
}

class _CompareCardState extends State<CompareCard> {
  late CompareData? _data = parseCompare(widget.source);

  @override
  void didUpdateWidget(CompareCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _data = parseCompare(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(
        title: StructStrings.compare,
        source: widget.source,
      );
    }
    return RichCard(
      title: d.title.isEmpty
          ? StructStrings.compare
          : '${StructStrings.compare} / ${d.title.toUpperCase()}',
      child: Padding(
        padding: const EdgeInsets.all(StructSizes.pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < d.options.length; i++) ...[
              if (i > 0) const SizedBox(height: StructSizes.gap),
              _OptionCard(option: d.options[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option});

  final CompareOption option;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    Widget point(String text, bool pro) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: AppIcon(
              pro ? PlayfulIcons.check : PlayfulIcons.cross,
              size: StructSizes.markSize,
              color: pro ? p.textPrimary : p.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: t.bodySmall)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: option.pick ? p.accent : p.border,
          width: option.pick ? StructSizes.pickBorder : AppBorder.thin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(option.name, style: t.title)),
              if (option.pick)
                const PlayfulTag(StructStrings.pick, accent: true),
            ],
          ),
          if (option.tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                option.tagline,
                style: t.label.copyWith(color: p.textSecondary),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          for (final s in option.pros) point(s, true),
          for (final s in option.cons) point(s, false),
        ],
      ),
    );
  }
}
