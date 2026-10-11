import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_event.dart';
import 'round_table_panel.dart';

/// "ROUND TABLE · 3 MODELS · AGREED" above a reply the table wrote.
/// Expands to each seat's draft, the review points and open questions.
class RoundTableHeader extends StatefulWidget {
  const RoundTableHeader({super.key, required this.table});

  final TableTranscript table;

  @override
  State<RoundTableHeader> createState() => _RoundTableHeaderState();
}

class _RoundTableHeaderState extends State<RoundTableHeader> {
  bool _expanded = false;

  void _toggle() {
    Haptics.tap();
    setState(() => _expanded = !_expanded);
  }

  String get _consensus => switch (widget.table.consensus) {
    'disputed' => TableStrings.disputed,
    'resolved' => TableStrings.resolved,
    _ => TableStrings.agreed,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final table = widget.table;
    final seated = table.seats.where((s) => s.status != 'failed').length;
    final tone = table.disputed ? p.accent : p.textSecondary;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.roundTable,
                    size: AppIconSize.sm,
                    color: tone,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${TableStrings.title}${TableStrings.separator}'
                      '${TableStrings.modelCount(seated)}'
                      '${TableStrings.separator}$_consensus',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: tone),
                    ),
                  ),
                  AppIcon(
                    _expanded ? AppIcons.collapse : AppIcons.expand,
                    size: AppIconSize.sm,
                    color: p.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) _details(context),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final table = widget.table;
    final points = [for (final r in table.reviews) ...r.points];
    final reviewed = table.reviews.any((r) => r.verdict != 'unknown');
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.border, width: AppBorder.thin),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final seat in table.seats) ...[
            TableSeatRow(seat: seat, live: false),
            if (seat.draft.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(
                  left: TableSizes.statusIcon + AppSpacing.sm,
                ),
                child: _Draft(text: _withoutTldr(seat.draft)),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (reviewed) ...[
            Text(TableStrings.reviews, style: t.caption),
            const SizedBox(height: AppSpacing.xs),
            if (points.isEmpty)
              Text(TableStrings.allAgree, style: t.bodySmall)
            else
              for (final kind in const ['error', 'disagree', 'missing'])
                if (points.any((x) => x.kind == kind))
                  _PointGroup(
                    kind: kind,
                    points: [
                      for (final x in points)
                        if (x.kind == kind) x,
                    ],
                  ),
          ],
          if (table.unresolved.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              TableStrings.couldNotAgree,
              style: t.caption.copyWith(color: p.accent),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final u in table.unresolved) _Bullet(text: u),
          ],
        ],
      ),
    );
  }
}

/// A seat's draft: four lines, tap to show all.
class _Draft extends StatefulWidget {
  const _Draft({required this.text});

  final String text;

  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        setState(() => _open = !_open);
      },
      child: AnimatedSize(
        duration: AppDurations.fast,
        alignment: Alignment.topCenter,
        child: Text(
          widget.text,
          maxLines: _open ? null : TableSizes.draftPeekLines,
          overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
          style: context.text.bodySmall,
        ),
      ),
    );
  }
}

class _PointGroup extends StatelessWidget {
  const _PointGroup({required this.kind, required this.points});

  final String kind;
  final List<TablePoint> points;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final title = switch (kind) {
      'error' => TableStrings.kindError,
      'missing' => TableStrings.kindMissing,
      _ => TableStrings.kindDisagree,
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: t.caption.copyWith(color: context.palette.textSecondary),
          ),
          for (final x in points)
            _Bullet(
              prefix: x.seat.isEmpty
                  ? null
                  : '${TableStrings.onSeat}${x.seat}${TableStrings.separator}',
              text: x.detail.isEmpty
                  ? x.claim
                  : '${x.claim}${TableStrings.dash}${x.detail}',
            ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.prefix});

  final String text;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              width: TableSizes.statusDot,
              height: AppBorder.thin,
              color: p.textTertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (prefix != null) TextSpan(text: prefix, style: t.caption),
                  TextSpan(text: text),
                ],
              ),
              style: t.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The draft without its `TL;DR:` first line, which the seat row already shows.
String _withoutTldr(String draft) => draft.replaceFirst(
  RegExp(r'^\s*TL;DR:[^\n]*\n*', caseSensitive: false),
  '',
);
