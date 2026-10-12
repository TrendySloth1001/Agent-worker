import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/chat_event.dart';

/// Small WHO AGREED pill in the round table header.
class WhoAgreedToggle extends StatelessWidget {
  const WhoAgreedToggle({super.key, required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Container(
        height: TableSupportSizes.toggleHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: TableSupportSizes.togglePadH,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? Theme.of(context).colorScheme.secondaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          TableSupportStrings.toggle,
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color: on ? p.textPrimary : p.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Each answer sentence with a dot per seat: filled when that seat's draft
/// makes the same claim. Tapping a filled dot shows the matching passage.
class WhoAgreedList extends StatelessWidget {
  const WhoAgreedList({super.key, required this.table});

  final TableTranscript table;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final seats = [
      for (final s in table.seats)
        if (s.status != 'failed') s,
    ];
    return Container(
      constraints: const BoxConstraints(maxHeight: TableSupportSizes.maxHeight),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.border, width: AppBorder.thin),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(TableSupportStrings.hint, style: t.caption),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                for (final s in seats)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SeatDot(seat: s.seat, filled: true),
                      const SizedBox(width: AppSpacing.xs),
                      Text(s.name, style: t.caption),
                    ],
                  ),
              ],
            ),
            for (var i = 0; i < table.support.length; i++) ...[
              if (i > 0 &&
                  table.support[i].paragraph != table.support[i - 1].paragraph)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Container(height: AppBorder.thin, color: p.border),
                ),
              _SentenceRow(
                item: table.support[i],
                seats: [for (final s in seats) s.seat],
                names: {for (final s in seats) s.seat: s.name},
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SentenceRow extends StatefulWidget {
  const _SentenceRow({
    required this.item,
    required this.seats,
    required this.names,
  });

  final TableSupport item;
  final List<String> seats;
  final Map<String, String> names;

  @override
  State<_SentenceRow> createState() => _SentenceRowState();
}

class _SentenceRowState extends State<_SentenceRow> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final item = widget.item;
    final excerpt = _open == null ? null : item.excerpts[_open];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.sentence,
                  maxLines: TableSupportSizes.sentenceLines,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall.copyWith(
                    color: item.seats.isEmpty
                        ? p.textTertiary
                        : p.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              for (final s in widget.seats) ...[
                const SizedBox(width: TableSupportSizes.dotGap),
                SeatDot(
                  seat: s,
                  filled: item.seats.contains(s),
                  selected: _open == s,
                  disputed: item.disputed,
                  onTap: item.seats.contains(s)
                      ? () => setState(() => _open = _open == s ? null : s)
                      : null,
                ),
              ],
            ],
          ),
          if (item.disputed)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                TableSupportStrings.disputed,
                style: t.caption.copyWith(color: p.accent),
              ),
            ),
          if (excerpt != null)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: p.border, width: AppBorder.thin),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    TableSupportStrings.seatOf(
                      _open!,
                      widget.names[_open] ?? '',
                    ),
                    style: t.caption,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(excerpt, style: t.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A seat letter in a tiny circle; filled when the seat backs the claim.
class SeatDot extends StatelessWidget {
  const SeatDot({
    super.key,
    required this.seat,
    required this.filled,
    this.selected = false,
    this.disputed = false,
    this.onTap,
  });

  final String seat;
  final bool filled, selected, disputed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = disputed ? p.accent : p.textPrimary;
    final dot = Container(
      width: TableSupportSizes.dot,
      height: TableSupportSizes.dot,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? tone : null,
        border: Border.all(
          color: filled
              ? tone
              : selected
              ? p.textPrimary
              : p.border,
          width: selected ? AppBorder.thick : AppBorder.thin,
        ),
      ),
      child: Text(
        seat,
        style: context.text.caption.copyWith(
          color: filled ? p.textInverse : p.textTertiary,
          height: 1,
        ),
      ),
    );
    if (onTap == null) return dot;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap!();
      },
      child: dot,
    );
  }
}
