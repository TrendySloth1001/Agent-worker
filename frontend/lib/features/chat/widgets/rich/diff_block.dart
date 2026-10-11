import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/haptics.dart';
import '../../../../core/constants/rich_cards.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/copy_action.dart';
import 'rich_frame.dart';
import 'rich_parsers.dart';

/// ```diff block: added lines tinted, removed lines red, hunks muted.
class DiffBlock extends StatelessWidget {
  const DiffBlock({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return RichCard(
      title: RichStrings.diff,
      trailing: CopyAction(text: code),
      child: DiffLines(code: code),
    );
  }
}

/// The diff body alone (no card): old/new line numbers, green adds, red
/// removals, soft-wrapped by default with a WRAP / SCROLL toggle. Shared
/// with the GitHub commit / compare widgets.
class DiffLines extends StatefulWidget {
  const DiffLines({super.key, required this.code, this.wrap = true});

  final String code;

  /// Start soft-wrapped (best on phones) or horizontally scrollable.
  final bool wrap;

  @override
  State<DiffLines> createState() => _DiffLinesState();
}

class _DiffRow {
  const _DiffRow(this.kind, this.text, this.oldNo, this.newNo);
  final DiffKind kind;
  final String text;
  final int? oldNo, newNo;
}

final _hunkRe = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');

class _DiffLinesState extends State<DiffLines> {
  late bool _wrap = widget.wrap;
  bool _all = false;

  /// Rows with line numbers taken from the hunk headers.
  List<_DiffRow> _parse() {
    final rows = <_DiffRow>[];
    var inHunk = false;
    int? oldNo, newNo;
    for (final raw in widget.code.split('\n')) {
      final line = raw.replaceAll('\t', DiffStyle.tabSpaces);
      final kind = diffKind(line, inHunk: inHunk);
      switch (kind) {
        case DiffKind.hunk:
          inHunk = true;
          final m = _hunkRe.firstMatch(line);
          oldNo = m == null ? null : int.parse(m[1]!);
          newNo = m == null ? null : int.parse(m[2]!);
          rows.add(_DiffRow(kind, line, null, null));
        case DiffKind.added:
          rows.add(_DiffRow(kind, line.substring(1), null, newNo));
          if (newNo != null) newNo++;
        case DiffKind.removed:
          rows.add(_DiffRow(kind, line.substring(1), oldNo, null));
          if (oldNo != null) oldNo++;
        case DiffKind.context:
          final text = inHunk && line.startsWith(' ')
              ? line.substring(1)
              : line;
          rows.add(_DiffRow(kind, text, oldNo, newNo));
          if (oldNo != null) oldNo++;
          if (newNo != null) newNo++;
        case DiffKind.meta:
          rows.add(_DiffRow(kind, line, null, null));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final green = p.isDark ? DiffStyle.addDark : DiffStyle.addLight;
    final code = t.code.copyWith(
      fontSize: DiffStyle.fontSize,
      height: DiffStyle.lineHeight,
    );
    final numStyle = code.copyWith(color: p.textTertiary);
    final all = _parse();
    final rows = _all ? all : all.take(DiffStyle.maxRows).toList();
    final hasNumbers = all.any((r) => r.oldNo != null || r.newNo != null);

    Widget row(_DiffRow r) {
      final (Color? bg, Color fg, String sign) = switch (r.kind) {
        DiffKind.added => (
          green.withValues(alpha: DiffStyle.addAlpha),
          green,
          '+',
        ),
        DiffKind.removed => (
          p.accent.withValues(alpha: DiffStyle.removeAlpha),
          p.accent,
          '-',
        ),
        DiffKind.hunk => (p.surfaceHigh, p.textTertiary, ''),
        DiffKind.meta => (null, p.textTertiary, ''),
        DiffKind.context => (null, p.synPlain, ''),
      };
      final text = Text(
        r.text.isEmpty ? ' ' : r.text,
        softWrap: _wrap,
        style: code.copyWith(
          color: r.kind == DiffKind.added ? p.textPrimary : fg,
        ),
      );
      return Container(
        color: bg,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasNumbers) ...[
              SizedBox(
                width: DiffStyle.numberWidth,
                child: Text(
                  r.oldNo?.toString() ?? '',
                  textAlign: TextAlign.right,
                  style: numStyle,
                ),
              ),
              SizedBox(
                width: DiffStyle.numberWidth,
                child: Text(
                  r.newNo?.toString() ?? '',
                  textAlign: TextAlign.right,
                  style: numStyle,
                ),
              ),
            ],
            SizedBox(
              width: DiffStyle.signWidth + AppSpacing.xs,
              child: Text(
                sign,
                textAlign: TextAlign.center,
                style: code.copyWith(color: fg),
              ),
            ),
            if (_wrap) Expanded(child: text) else text,
          ],
        ),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [for (final r in rows) row(r)],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Haptics.tap();
                  setState(() => _wrap = !_wrap);
                },
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Text(
                    _wrap ? DiffStyle.scroll : DiffStyle.wrap,
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_wrap)
          body
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(child: body),
          ),
        if (!_all && all.length > rows.length)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tap();
              setState(() => _all = true);
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                '${DiffStyle.showAll} · ${all.length - rows.length}',
                style: t.caption.copyWith(color: p.textPrimary),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}
