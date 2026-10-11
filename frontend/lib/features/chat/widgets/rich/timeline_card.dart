import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/constants/widget_playful.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

class TimelineEvent {
  const TimelineEvent(this.when, this.title, this.detail);
  final String when, title, detail;
}

class TimelineData {
  const TimelineData(this.title, this.events);
  final String title;
  final List<TimelineEvent> events;
}

/// Parses a ```timeline block; null when there are no events.
TimelineData? parseTimeline(String src) {
  var title = '';
  final events = <TimelineEvent>[];
  for (final line in playfulLines(src)) {
    if (line.toLowerCase().startsWith('title:')) {
      title = line.substring(6).trim();
      continue;
    }
    if (!line.contains('|') || events.length >= PlayfulLimits.events) continue;
    final parts = line.split('|').map((e) => e.trim()).toList();
    if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) continue;
    events.add(
      TimelineEvent(parts[0], parts[1], parts.skip(2).join(' | ').trim()),
    );
  }
  if (events.isEmpty) return null;
  return TimelineData(title, events);
}

/// ```timeline block: vertical rail with expandable events.
class TimelineCard extends StatefulWidget {
  const TimelineCard({super.key, required this.source});

  final String source;

  @override
  State<TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<TimelineCard> {
  late TimelineData? _data = parseTimeline(widget.source);
  final Set<int> _open = {0};

  @override
  void didUpdateWidget(TimelineCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _data = parseTimeline(widget.source);
      _open
        ..clear()
        ..add(0);
    }
  }

  bool get _allOpen => _open.length >= _data!.events.length;

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(
        title: WidgetKitStrings.timeline,
        source: widget.source,
      );
    }
    final n = d.events.length;
    return RichCard(
      title: d.title.isEmpty
          ? WidgetKitStrings.timeline
          : '${WidgetKitStrings.timeline} / ${d.title.toUpperCase()}',
      trailing: PlayfulTag('$n'),
      actions: [
        RichAction(
          icon: _allOpen ? PlayfulIcons.collapse : PlayfulIcons.expand,
          label: _allOpen
              ? PlayfulStrings.collapseAll
              : PlayfulStrings.expandAll,
          onTap: () async {
            setState(() {
              if (_allOpen) {
                _open.clear();
              } else {
                _open
                  ..clear()
                  ..addAll(List.generate(n, (i) => i));
              }
            });
            return true;
          },
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(PlayfulSizes.pad),
        child: Column(
          children: [
            for (var i = 0; i < n; i++)
              _Row(
                event: d.events[i],
                first: i == 0,
                last: i == n - 1,
                open: _open.contains(i),
                onTap: () {
                  Haptics.tap();
                  setState(() {
                    if (!_open.remove(i)) _open.add(i);
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.event,
    required this.first,
    required this.last,
    required this.open,
    required this.onTap,
  });

  final TimelineEvent event;
  final bool first, last, open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final hasDetail = event.detail.isNotEmpty;
    final lit = open || last;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: PlayfulSizes.railWidth,
              child: Column(
                children: [
                  Container(
                    width: AppBorder.thin,
                    height: AppSpacing.sm,
                    color: first ? null : p.borderStrong,
                  ),
                  AnimatedContainer(
                    duration: PlayfulDurations.expand,
                    width: PlayfulSizes.dot,
                    height: PlayfulSizes.dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: open ? p.accent : p.codeBackground,
                      border: Border.all(
                        color: lit ? p.accent : p.borderStrong,
                        width: AppBorder.thick,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: AppBorder.thin,
                      color: last ? null : p.borderStrong,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: AppSpacing.md,
                  top: AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.when.toUpperCase(),
                                style: t.caption.copyWith(
                                  color: open ? p.accent : p.textTertiary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                event.title,
                                style: t.bodySmall.copyWith(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasDetail)
                          AppIcon(
                            open ? PlayfulIcons.collapse : PlayfulIcons.expand,
                            size: AppIconSize.sm,
                            color: p.textTertiary,
                          ),
                      ],
                    ),
                    AnimatedSize(
                      duration: PlayfulDurations.expand,
                      alignment: Alignment.topCenter,
                      curve: Curves.easeOut,
                      child: open && hasDetail
                          ? Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: Text(event.detail, style: t.bodySmall),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
