import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

/// Splits [text] into spans, marking each case-insensitive hit of [query].
List<TextSpan> highlightSpans(String text, String query, TextStyle hit) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var at = 0;
  while (at < text.length) {
    final i = lower.indexOf(q, at);
    if (i < 0) break;
    if (i > at) spans.add(TextSpan(text: text.substring(at, i)));
    spans.add(TextSpan(text: text.substring(i, i + q.length), style: hit));
    at = i + q.length;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// One-line text with the search hits in the accent color.
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    required this.query,
    required this.style,
    this.maxLines = 1,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final hit = style.copyWith(
      color: context.palette.accent,
      fontVariations: const [FontVariation.weight(600)],
    );
    return Text.rich(
      TextSpan(style: style, children: highlightSpans(text, query, hit)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
