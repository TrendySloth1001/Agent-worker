import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import 'inline_icon.dart';
import 'md_blocks.dart';

/// A section title. Big ones (`#`, `##`) get a hairline above to separate
/// sections; a leading `{{icon:…}}` becomes a circular badge.
class MdHeading extends StatelessWidget {
  const MdHeading({
    super.key,
    required this.block,
    required this.first,
    required this.renderText,
  });

  final MdHeadingBlock block;

  /// First block of the reply: no rule above.
  final bool first;
  final Widget Function(String text, TextStyle style) renderText;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final big = block.level <= 2;
    final style = context.text.title.copyWith(
      fontSize: big ? MdSizes.h2FontSize : MdSizes.h3FontSize,
      fontWeight: big ? FontWeight.w700 : FontWeight.w600,
      height: 1.25,
      color: p.textPrimary,
    );
    final icon = block.icon;
    final fontSize = style.fontSize!;
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          IconAvatar(
            size: fontSize * MdSizes.iconAvatarScale,
            child: InlineIcon(
              set: icon.split(':').first,
              name: icon.split(':').last,
              size: fontSize * MdSizes.headingIconScale,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        // "2. Title" would otherwise parse as an ordered list item.
        Expanded(
          child: renderText(
            block.text.replaceFirstMapped(
              RegExp(r'^(\d+)([.)])\s'),
              (m) => '${m[1]}\\${m[2]} ',
            ),
            style,
          ),
        ),
      ],
    );
    if (!big || first) return title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: AppBorder.thin, color: p.border),
        const SizedBox(height: AppSpacing.lg),
        title,
      ],
    );
  }
}
