import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../data/chat_event.dart';
import 'citation_chip.dart';

/// Turns `[K1]` / `[W2]` (or a grouped `[W1+W3]`, see `prepareCitations`)
/// into a `cite` element. A following `(` means it is a normal markdown
/// link, so it is left alone.
class CitationSyntax extends md.InlineSyntax {
  CitationSyntax() : super(r'\[([KWDGC]\d{1,3}(?:\+[KWDGC]\d{1,3})*)\](?!\()');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('cite', match[1]!));
    return true;
  }
}

/// Renders a known citation as an inline site chip; unknown ids render
/// nothing.
class CitationBuilder extends MarkdownElementBuilder {
  CitationBuilder({
    required this.citations,
    required this.onTap,
    this.onTapGroup,
  });

  final List<Citation> citations;
  final void Function(BuildContext context, Citation citation) onTap;

  /// Tap on a chip that stands for several sources; falls back to the first.
  final void Function(BuildContext context, List<Citation> group)? onTapGroup;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final byId = {for (final c in citations) c.id: c};
    final group = [
      for (final id in element.textContent.split(citeGroupSeparator)) ?byId[id],
    ];
    if (group.isEmpty) return const SizedBox.shrink();
    final citation = group.first;
    // Merged into the paragraph like inline math, so the chip stays in the
    // line instead of wrapping onto its own.
    return Text.rich(
      TextSpan(
        style: parentStyle,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: CitationChip(
              citation: citation,
              more: group.skip(1).toList(),
              onTap: () => group.length > 1 && onTapGroup != null
                  ? onTapGroup!(context, group)
                  : onTap(context, citation),
            ),
          ),
        ],
      ),
    );
  }
}
