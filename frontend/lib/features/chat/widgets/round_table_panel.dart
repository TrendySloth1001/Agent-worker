import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_event.dart';

/// Caption for a live Round Table phase.
String tablePhaseLabel(String? phase) => switch (phase) {
  'seating' => TableStrings.seating,
  'drafting' => TableStrings.drafting,
  'checking' => TableStrings.checking,
  'reviewing' => TableStrings.reviewing,
  'synthesizing' => TableStrings.synthesizing,
  _ => TableStrings.status,
};

/// Live view of the table while the reply is not written yet: the phase,
/// then one row per seat with its state and one-line TL;DR.
class RoundTablePanel extends StatelessWidget {
  const RoundTablePanel({super.key, required this.seats, this.phase});

  final List<TableSeat> seats;
  final String? phase;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
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
                  '${tablePhaseLabel(phase)}',
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
          for (final seat in seats) ...[
            const SizedBox(height: AppSpacing.md),
            TableSeatRow(seat: seat),
          ],
        ],
      ),
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
