import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../data/chat_event.dart';
import 'citation_chip.dart';

/// A bare link in an answer ("see https://www.imdb.com/title/tt123/") shows
/// as a compact chip (site logo + name), never as raw text. Links written
/// as `[text](url)` or `<url>`, and links in code, stay as they are.
class BareUrlSyntax extends md.InlineSyntax {
  BareUrlSyntax()
    : super(
        r'''(?<![\[(<"'=/\w])https?://[^\s<>()\[\]"'`]*[^\s<>()\[\]"'`.,;:!?*_]''',
      );

  static const tag = 'urlchip';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final url = match[0]!;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      parser.addNode(md.Text(url));
    } else {
      parser.addNode(md.Element.text(tag, url));
    }
    return true;
  }
}

/// The source-style chip a bare link becomes; a tap opens the link.
Citation linkCitation(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').replaceFirst(
    RegExp(r'^www\.'),
    '',
  );
  return Citation(id: '', title: host, url: url, site: host);
}

class BareUrlBuilder extends MarkdownElementBuilder {
  BareUrlBuilder({required this.onTap});

  final void Function(BuildContext context, String url) onTap;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final url = element.textContent;
    // Merged into the paragraph like a citation chip, so it stays in the line.
    return Text.rich(
      TextSpan(
        style: parentStyle,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: CitationChip(
              citation: linkCitation(url),
              onTap: () => onTap(context, url),
            ),
          ),
        ],
      ),
    );
  }
}
