import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_event.dart';
import '../../../data/chat_message.dart';

/// Caption for a live Round Table phase.
String tablePhaseLabel(String? phase) => TableWaitStrings.phase(phase);

/// Live view of the table while the reply is not written yet: a progress
/// meter with elapsed time and estimate, one row per seat with its state,
/// research and one-line TL;DR, and the choice to answer fast or be notified.
class RoundTablePanel extends StatefulWidget {
  const RoundTablePanel({
    super.key,
    required this.message,
    this.onAnswerFast,
    this.onNotify,
  });

  final ChatMessage message;

  /// Cancels the table and answers with one model.
  final VoidCallback? onAnswerFast;

  /// Asks for a system notification when the answer is ready.
  final VoidCallback? onNotify;

  @override
  State<RoundTablePanel> createState() => _RoundTablePanelState();
}

class _RoundTablePanelState extends State<RoundTablePanel> {
  late final Timer _timer;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      TableMeterSizes.tick,
      (_) => setState(() => _ticks++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  /// The steps this table shows; research only when it happened.
  List<String> _steps(ChatMessage m) => [
    if (m.tableSeen.contains('researching')) 'researching',
    'seating',
    'drafting',
    'checking',
    'reviewing',
    'synthesizing',
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final m = widget.message;
    final since = m.tableStamp == null
        ? Duration.zero
        : DateTime.now().difference(m.tableStamp!);
    final elapsed = Duration(milliseconds: m.tableElapsedMs) + since;
    final eta = m.tableEtaMs;
    final leftMs = eta == null ? null : math.max(eta - since.inMilliseconds, 0);
    final steps = _steps(m);
    final current = math.max(steps.indexOf(m.tablePhase ?? ''), 0);
    final fraction = leftMs == null
        ? (current + 0.5) / steps.length
        : elapsed.inMilliseconds / (elapsed.inMilliseconds + leftMs);
    final leftLabel = leftMs == null
        ? ''
        : leftMs < Duration.millisecondsPerSecond
        ? TableWaitStrings.almostDone
        : TableWaitStrings.left((leftMs / 1000).ceil());
    final research = m.liveSeats.isEmpty ? m.tableResearch : const {};

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(
                AppIcons.roundTable,
                size: AppIconSize.sm,
                color: p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${TableStrings.title}${TableStrings.separator}'
                  '${tablePhaseLabel(m.tablePhase)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
              ),
              Text(
                TableWaitStrings.clock(elapsed),
                style: t.caption.copyWith(color: p.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _DotMeter(
            fraction: fraction.clamp(0.0, 1.0).toDouble(),
            blink: _ticks.isEven,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Steps(steps: steps, current: current),
              ),
              if (leftLabel.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  leftLabel,
                  style: t.caption.copyWith(color: p.textPrimary),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            TableWaitStrings.intro,
            style: t.bodySmall.copyWith(color: p.textSecondary),
          ),
          for (final entry in research.entries) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: TableSizes.statusIcon,
                  child: Text(entry.key, style: t.caption),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: QueryChips(queries: entry.value)),
              ],
            ),
          ],
          for (final seat in m.liveSeats) ...[
            const SizedBox(height: AppSpacing.md),
            TableSeatRow(seat: seat),
            if (seat.queries.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(
                  left: TableSizes.statusIcon + AppSpacing.sm,
                ),
                child: QueryChips(queries: seat.queries),
              ),
            ],
          ],
          if (widget.onAnswerFast != null || widget.onNotify != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (widget.onAnswerFast != null)
                  _PanelAction(
                    icon: TableIcons.answerFast,
                    label: TableWaitStrings.answerFast,
                    onTap: widget.onAnswerFast!,
                  ),
                if (widget.onNotify != null)
                  _PanelAction(
                    icon: m.notifyWhenDone ? AppIcons.check : TableIcons.notify,
                    label: m.notifyWhenDone
                        ? TableWaitStrings.willNotify
                        : TableWaitStrings.notifyMe,
                    active: m.notifyWhenDone,
                    onTap: m.notifyWhenDone ? null : widget.onNotify,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Dot-matrix progress bar: filled dots, one blinking red dot at the head.
class _DotMeter extends StatelessWidget {
  const _DotMeter({required this.fraction, required this.blink});

  final double fraction;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        const pitch = TableMeterSizes.cell + TableMeterSizes.cellGap;
        final count = math.max(
          ((box.maxWidth + TableMeterSizes.cellGap) / pitch).floor(),
          1,
        );
        final filled = (fraction * count).floor().clamp(0, count - 1);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: TableMeterSizes.cell,
                height: TableMeterSizes.cell,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.none),
                  color: i < filled
                      ? p.textPrimary
                      : i == filled && blink
                      ? p.accent
                      : p.border,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// RESEARCH SEAT DRAFT CHECK REVIEW CHAIR, the current one bright.
class _Steps extends StatelessWidget {
  const _Steps({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  static String _short(String step) => switch (step) {
    'researching' => TableWaitStrings.stepResearch,
    'seating' => TableWaitStrings.stepSeat,
    'drafting' => TableWaitStrings.stepDraft,
    'checking' => TableWaitStrings.stepCheck,
    'reviewing' => TableWaitStrings.stepReview,
    _ => TableWaitStrings.stepChair,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: [
        for (var i = 0; i < steps.length; i++)
          Text(
            _short(steps[i]),
            style: t.caption.copyWith(
              color: i == current
                  ? p.textPrimary
                  : i < current
                  ? p.textSecondary
                  : p.textTertiary,
            ),
          ),
      ],
    );
  }
}

/// Outlined pill action under the meter.
class _PanelAction extends StatelessWidget {
  const _PanelAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = active ? p.accent : p.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              Haptics.tap();
              onTap!();
            },
      child: Container(
        height: TableMeterSizes.actionHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: active ? p.accent : p.borderStrong,
            width: AppBorder.thin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: AppIconSize.xs, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: context.text.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// What a seat searched the web for: search icon + query, one chip each.
class QueryChips extends StatelessWidget {
  const QueryChips({super.key, required this.queries});

  final List<String> queries;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final q in queries)
          Container(
            constraints: const BoxConstraints(
              maxWidth: TableMeterSizes.queryChipMaxWidth,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: p.border, width: AppBorder.thin),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  TableIcons.query,
                  size: AppIconSize.xs,
                  color: p.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    q,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One seat: status mark, model name, CHAIR tag and its TL;DR.
class TableSeatRow extends StatelessWidget {
  const TableSeatRow({super.key, required this.seat, this.live = true});

  final TableSeat seat;

  /// Live rows pulse while working and show objection counts.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: TableSizes.statusIcon,
          child: Center(
            child: _StatusMark(seat: seat, live: live),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      seat.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: p.textPrimary),
                    ),
                  ),
                  if (seat.isChair) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const ChairTag(),
                  ],
                  if (live && seat.objections > 0) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text('${seat.objections}', style: t.caption),
                  ],
                ],
              ),
              if (seat.summary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  seat.summary,
                  maxLines: TableSizes.summaryLines,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Small outlined CHAIR label for seat A.
class ChairTag extends StatelessWidget {
  const ChairTag({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.borderStrong, width: AppBorder.thin),
      ),
      child: Text(TableStrings.chair, style: context.text.caption),
    );
  }
}

class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.seat, required this.live});

  final TableSeat seat;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (seat.status == 'working') return const _PulseDot();
    if (seat.status == 'failed') {
      return AppIcon(
        AppIcons.close,
        size: TableSizes.statusIcon,
        color: p.textTertiary,
      );
    }
    if (live && seat.objections > 0) {
      return AppIcon(
        AppIcons.alert,
        size: TableSizes.statusIcon,
        color: p.textSecondary,
      );
    }
    return AppIcon(
      AppIcons.check,
      size: TableSizes.statusIcon,
      color: p.textPrimary,
    );
  }
}

/// A dot that fades in and out while the seat is working.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: TableSizes.pulse,
    lowerBound: TableSizes.pulseMinOpacity,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: TableSizes.statusDot,
        height: TableSizes.statusDot,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.palette.accent,
        ),
      ),
    );
  }
}
