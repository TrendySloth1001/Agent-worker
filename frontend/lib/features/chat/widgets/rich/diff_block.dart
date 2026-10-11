import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
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
    final p = context.palette;
    final t = context.text;
    final lines = code.split('\n');
    var inHunk = false;
    final rows = <Widget>[];
    for (final line in lines) {
      final kind = diffKind(line, inHunk: inHunk);
      if (kind == DiffKind.hunk) inHunk = true;
      final gutter = switch (kind) {
        DiffKind.added => '+',
        DiffKind.removed => '-',
        _ => ' ',
      };
      final text = switch (kind) {
        DiffKind.added || DiffKind.removed => line.substring(1),
        _ => line,
      };
      final (Color? bg, Color fg) = switch (kind) {
        DiffKind.added => (
          p.textPrimary.withValues(alpha: RichSizes.diffAddAlpha),
          p.textPrimary,
        ),
        DiffKind.removed => (
          p.accent.withValues(alpha: RichSizes.diffRemoveAlpha),
          p.accent,
        ),
        DiffKind.hunk || DiffKind.meta => (null, p.textTertiary),
        DiffKind.context => (null, p.synPlain),
      };
      rows.add(
        Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              SizedBox(
                width: RichSizes.diffGutter,
                child: Text(gutter, style: t.code.copyWith(color: fg)),
              ),
              Text(text, style: t.code.copyWith(color: fg)),
            ],
          ),
        ),
      );
    }
    return RichCard(
      title: RichStrings.diff,
      trailing: CopyAction(text: code),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ),
    );
  }
}
