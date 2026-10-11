import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/constants/widget_playful.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

class ChecklistData {
  const ChecklistData(this.title, this.items, this.done);
  final String title;
  final List<String> items;
  final List<bool> done;
}

/// Parses a ```checklist block; null when there are no items.
ChecklistData? parseChecklist(String src) {
  var title = '';
  final items = <String>[];
  final done = <bool>[];
  final box = RegExp(r'^(?:[-*]\s*)?\[( |x|X)\]\s*(.+)$');
  for (final line in playfulLines(src)) {
    final m = box.firstMatch(line);
    if (m != null) {
      if (items.length < PlayfulLimits.checklistItems) {
        items.add(m.group(2)!.trim());
        done.add(m.group(1) != ' ');
      }
    } else if (line.toLowerCase().startsWith('title:')) {
      title = line.substring(6).trim();
    }
  }
  if (items.isEmpty) return null;
  return ChecklistData(title, items, done);
}

/// ```checklist block: tick items off, copy or send progress.
class ChecklistCard extends StatefulWidget {
  const ChecklistCard({super.key, required this.source});

  final String source;

  @override
  State<ChecklistCard> createState() => _ChecklistCardState();
}

class _ChecklistCardState extends State<ChecklistCard> {
  late ChecklistData? _data = parseChecklist(widget.source);
  late List<bool> _done = List.of(_data?.done ?? const []);
  bool _flash = false;

  @override
  void didUpdateWidget(ChecklistCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _data = parseChecklist(widget.source);
      _done = List.of(_data?.done ?? const []);
    }
  }

  int get _count => _done.where((e) => e).length;

  void _toggle(int i) {
    final wasAll = _count == _done.length;
    setState(() => _done[i] = !_done[i]);
    final all = _count == _done.length;
    if (all && !wasAll) {
      Haptics.received();
      setState(() => _flash = true);
      Future<void>.delayed(PlayfulDurations.flash, () {
        if (mounted) setState(() => _flash = false);
      });
    } else {
      Haptics.tick();
    }
  }

  String _markdown() {
    final d = _data!;
    return [
      if (d.title.isNotEmpty) d.title,
      for (var i = 0; i < d.items.length; i++)
        '- [${_done[i] ? 'x' : ' '}] ${d.items[i]}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(
        title: WidgetKitStrings.checklist,
        source: widget.source,
      );
    }
    final p = context.palette;
    final t = context.text;
    final total = d.items.length;
    final all = _count == total;
    return RichCard(
      title: d.title.isEmpty
          ? WidgetKitStrings.checklist
          : '${WidgetKitStrings.checklist} / ${d.title.toUpperCase()}',
      trailing: all
          ? Text(
              PlayfulStrings.allDone,
              style: t.caption.copyWith(color: p.accent),
            )
          : null,
      actions: [
        RichAction.copy(text: _markdown()),
        RichAction(
          icon: PlayfulIcons.send,
          label: PlayfulStrings.sendProgress,
          doneLabel: PlayfulStrings.sent,
          enabled: playfulCanSend(context),
          onTap: () async => playfulSend(
            context,
            PlayfulStrings.progressPrompt(
              d.title.isEmpty ? PlayfulStrings.checklistUntitled : d.title,
              [
                for (var i = 0; i < total; i++)
                  if (!_done[i]) d.items[i],
              ],
              total,
            ),
          ),
        ),
      ],
      child: AnimatedContainer(
        duration: PlayfulDurations.flash,
        color: _flash
            ? p.accent.withValues(alpha: PlayfulSizes.flashAlpha)
            : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PlayfulSizes.pad,
                PlayfulSizes.pad,
                PlayfulSizes.pad,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DotNumber(
                    '$_count/$total',
                    size: PlayfulSizes.smallNumberFont + 4,
                    color: all ? p.accent : null,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PlayfulSizes.pad),
              child: PlayfulBar(value: _count / total),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (var i = 0; i < total; i++)
              _Item(text: d.items[i], done: _done[i], onTap: () => _toggle(i)),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.text, required this.done, required this.onTap});

  final String text;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: PlayfulSizes.tileMinHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: PlayfulSizes.pad,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: PlayfulDurations.expand,
              width: PlayfulSizes.checkBox,
              height: PlayfulSizes.checkBox,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? p.accent : null,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: done ? p.accent : p.borderStrong,
                  width: AppBorder.thin,
                ),
              ),
              child: done
                  ? AppIcon(
                      PlayfulIcons.check,
                      size: AppIconSize.sm,
                      color: p.textInverse,
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: PlayfulDurations.expand,
                style: t.bodySmall.copyWith(
                  color: done ? p.textTertiary : p.textPrimary,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: p.textTertiary,
                ),
                child: Text(text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
