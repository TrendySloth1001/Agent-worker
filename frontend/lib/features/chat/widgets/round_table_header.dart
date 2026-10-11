import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_event.dart';
import 'markdown/app_markdown.dart';
import 'round_table_panel.dart';
import 'source_chips.dart';

/// "ROUND TABLE · 3 MODELS · AGREED" above a reply the table wrote.
/// Expands to each seat's draft, the review points and open questions.
class RoundTableHeader extends StatefulWidget {
  const RoundTableHeader({
    super.key,
    required this.table,
    this.citations = const [],
  });

  final TableTranscript table;

  /// The reply's sources; seat drafts cite the same tags.
  final List<Citation> citations;

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
            Padding(
              padding: const EdgeInsets.only(
                left: TableSizes.statusIcon + AppSpacing.sm,
              ),
              child: _SeatDetails(seat: seat, citations: widget.citations),
            ),
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

/// Under a seat: what it searched, its draft with citation chips, and the
/// sources it cited.
class _SeatDetails extends StatelessWidget {
  const _SeatDetails({required this.seat, required this.citations});

  final TableSeat seat;
  final List<Citation> citations;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final byId = {for (final c in citations) c.id: c};
    final cited = [
      for (final tag in seat.sources)
        if (byId[tag] != null) byId[tag]!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seat.queries.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          QueryChips(queries: seat.queries),
        ],
        if (seat.draft.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          _Draft(text: _withoutTldr(seat.draft), citations: citations),
        ],
        if (cited.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(TableWaitStrings.sources, style: t.caption),
          const SizedBox(height: AppSpacing.xs),
          SourceChips(citations: cited, used: const {}),
        ],
      ],
    );
  }
}

/// A seat's draft as markdown with citation chips; long drafts start
/// collapsed with a SHOW ALL toggle.
class _Draft extends StatefulWidget {
  const _Draft({required this.text, required this.citations});

  final String text;
  final List<Citation> citations;

  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final long = widget.text.length > TableMeterSizes.draftPeekChars;
    final body = AppMarkdown(
      data: widget.text,
      citations: widget.citations,
      streaming: false,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: AppDurations.fast,
          alignment: Alignment.topCenter,
          child: !long || _open
              ? body
              : ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: TableMeterSizes.draftPeekHeight,
                  ),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: body,
                  ),
                ),
        ),
        if (long)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tap();
              setState(() => _open = !_open);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                _open ? TableWaitStrings.showLess : TableWaitStrings.showAll,
                style: context.text.caption.copyWith(color: p.textTertiary),
              ),
            ),
          ),
      ],
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
