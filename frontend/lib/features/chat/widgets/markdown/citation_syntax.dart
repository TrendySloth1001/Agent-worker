import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../data/chat_event.dart';
import 'citation_chip.dart';

/// Turns `[K1]` / `[W2]` into a `cite` element. A following `(` means it is
/// a normal markdown link, so it is left alone.
class CitationSyntax extends md.InlineSyntax {
  CitationSyntax() : super(r'\[([KWDG]\d{1,2})\](?!\()');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('cite', match[1]!));
    return true;
  }
}

/// Renders a known citation as an inline site chip; unknown ids render
/// nothing.
class CitationBuilder extends MarkdownElementBuilder {
  CitationBuilder({required this.citations, required this.onTap});

  final List<Citation> citations;
  final void Function(BuildContext context, Citation citation) onTap;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final id = element.textContent;
    final citation = citations.where((c) => c.id == id).firstOrNull;
    if (citation == null) return const SizedBox.shrink();
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
              onTap: () => onTap(context, citation),
            ),
          ),
        ],
      ),
    );
  }
}
