import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/rich_cards.dart';
import '../../../../core/theme/app_palette.dart';
import '../markdown/inline_icon.dart';
import 'rich_parsers.dart';

/// ```card block: icon + title/subtitle, then label / value rows.
class SpecCard extends StatelessWidget {
  const SpecCard({super.key, required this.data});

  final SpecCardData data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.codeBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (data.iconSet != null && data.iconName != null) ...[
                InlineIcon(
                  set: data.iconSet!,
                  name: data.iconName!,
                  size: RichSizes.specIcon,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (data.subtitle.isNotEmpty)
                      Text(
                        data.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (data.rows.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(
              height: AppBorder.thin,
              thickness: AppBorder.thin,
              color: p.border,
            ),
            for (final (k, v) in data.rows)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      flex: 2,
                      child: Text(k.toUpperCase(), style: t.caption),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      flex: 3,
                      child: Text.rich(
                        _value(v, context),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Splits on backticks: odd segments are inline code.
  TextSpan _value(String v, BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final base = t.bodySmall.copyWith(color: p.textPrimary);
    final code = t.code.copyWith(
      fontSize: base.fontSize,
      backgroundColor: p.surfaceHigh,
    );
    final parts = v.split('`');
    // An unmatched backtick means no code spans at all.
    if (parts.length.isEven) return TextSpan(text: v, style: base);
    return TextSpan(
      style: base,
      children: [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].isNotEmpty)
            TextSpan(text: parts[i], style: i.isOdd ? code : null),
      ],
    );
  }
}
