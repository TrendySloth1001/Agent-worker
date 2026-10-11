import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/theme/app_palette.dart';

/// `==text==`: the phrase the reader must not miss, drawn as a marker
/// highlight in the accent color.
class HighlightSyntax extends md.InlineSyntax {
  HighlightSyntax() : super(r'==(?=\S)([^=\n]{1,160}?)(?<=\S)==');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mark', match[1]!));
    return true;
  }
}

class HighlightBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final p = context.palette;
    final style = parentStyle ?? context.text.body;
    // A Text.rich is merged into the paragraph, so the mark wraps with it.
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: style.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w600,
          backgroundColor: p.accent.withValues(alpha: MdSizes.markAlpha),
        ),
      ),
    );
  }
}
