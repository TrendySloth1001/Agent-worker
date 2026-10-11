import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import 'math_view.dart';

/// Inline TeX: `$x$`, `$$x$$`, `\(x\)` and `\[x\]` written inside a sentence.
///
/// A `$` only opens math when it is not preceded by a word character, `\` or
/// `$`, is followed by a non-space, and closes on a `$` that follows a
/// non-space and is not followed by a digit. That keeps "$5 and $10" text.
const _pattern =
    r'(?<![\\$\w])\$\$(?!\s)((?:\\.|[^\\\n])+?)(?<!\s)\$\$'
    r'|(?<![\\$\w])\$(?![\s$])((?:\\.|[^$\\\n])+?)(?<![\s\\])\$(?![\d$])'
    r'|\\\(((?:\\.|[^\\\n])+?)\\\)'
    r'|\\\[((?:\\.|[^\\\n])+?)\\\]';

final _numberOnly = RegExp(r'^[\d\s.,%]+$');

/// True when [tex] from a single-`$` match is plausibly math (not a price).
bool looksLikeMath(String tex) {
  final t = tex.trim();
  return t.isNotEmpty && !_numberOnly.hasMatch(t);
}

class MathSyntax extends md.InlineSyntax {
  MathSyntax() : super(_pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = (match[1] ?? match[2] ?? match[3] ?? match[4] ?? '').trim();
    if (!looksLikeMath(tex)) {
      // Returning false would make the parser retry the same spot forever,
      // so a number or price is emitted as plain text and consumed.
      parser.addNode(md.Text(match[0]!));
      return true;
    }
    parser.addNode(md.Element.text('math', tex));
    return true;
  }
}

class MathBuilder extends MarkdownElementBuilder {
  MathBuilder({this.inTable = false});

  /// Table cells shrink formulas to fit the column instead of baseline-flowing.
  final bool inTable;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = parentStyle ?? preferredStyle ?? context.text.body;
    final size =
        (style.fontSize ?? context.text.body.fontSize!) *
        MdSizes.mathInlineScale;
    final color = style.color ?? context.palette.textPrimary;
    final tex = element.textContent;
    if (inTable) return TableMath(tex: tex, fontSize: size, color: color);
    // A Text.rich holding a baseline-aligned WidgetSpan is merged into the
    // surrounding paragraph, so the formula sits on the text baseline.
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InlineMath(tex: tex, fontSize: size, color: color),
          ),
        ],
      ),
    );
  }
}

final _fenceLine = RegExp(r'^\s*(`{3,}|~{3,})\s*([A-Za-z]*)');
final _mathLangs = {'math', 'latex', 'tex'};

/// Whether a fence info string marks display math.
bool isMathFence(String lang) => _mathLangs.contains(lang.toLowerCase());

/// While streaming, drops a trailing math segment that is not closed yet so
/// half-written TeX never flashes. Code (fences, `inline code`) is skipped.
String hidePartialMath(String text) {
  if (!text.contains(r'$') && !text.contains(r'\[') && !text.contains(r'\(')) {
    if (!text.contains('math') && !text.contains('tex')) return text;
  }
  final n = text.length;
  var i = 0;
  var inFence = false;
  String? fenceChar;
  var fenceLen = 0;
  var fenceMathStart = -1;

  bool atLineStart(int k) => k == 0 || text[k - 1] == '\n';

  while (i < n) {
    if (atLineStart(i)) {
      final eol = text.indexOf('\n', i);
      final end = eol < 0 ? n : eol;
      final line = text.substring(i, end);
      final m = _fenceLine.firstMatch(line);
      if (m != null) {
        final marker = m[1]!;
        if (!inFence) {
          inFence = true;
          fenceChar = marker[0];
          fenceLen = marker.length;
          fenceMathStart = isMathFence(m[2]!) ? i : -1;
        } else if (marker[0] == fenceChar &&
            marker.length >= fenceLen &&
            line.substring(m.end).trim().isEmpty) {
          inFence = false;
          fenceMathStart = -1;
        }
        i = eol < 0 ? n : eol + 1;
        continue;
      }
      if (inFence) {
        i = eol < 0 ? n : eol + 1;
        continue;
      }
    }
    final c = text[i];
    if (c == '`') {
      var run = 1;
      while (i + run < n && text[i + run] == '`') {
        run++;
      }
      final close = text.indexOf('`' * run, i + run);
      i = close < 0 ? i + run : close + run;
      continue;
    }
    if (c == r'\') {
      if (i + 1 < n && (text[i + 1] == '[' || text[i + 1] == '(')) {
        final closer = text[i + 1] == '[' ? r'\]' : r'\)';
        final close = text.indexOf(closer, i + 2);
        if (close < 0) return text.substring(0, i);
        i = close + 2;
      } else {
        i += 2;
      }
      continue;
    }
    if (c == r'$') {
      if (i + 1 < n && text[i + 1] == r'$') {
        final close = text.indexOf(r'$$', i + 2);
        if (close < 0) return text.substring(0, i);
        i = close + 2;
        continue;
      }
      final prev = i == 0 ? '' : text[i - 1];
      final opens =
          i + 1 < n &&
          text[i + 1].trim().isNotEmpty &&
          !RegExp(r'[\w\\$]').hasMatch(prev);
      if (!opens) {
        // A lone `$` as the last character may be the first half of `$$`.
        if (i + 1 == n && !RegExp(r'[\w\\$]').hasMatch(prev)) {
          return text.substring(0, i);
        }
        i++;
        continue;
      }
      final eol = text.indexOf('\n', i);
      final end = eol < 0 ? n : eol;
      final close = text.indexOf(r'$', i + 1);
      if (close >= 0 && close < end) {
        i = close + 1;
        continue;
      }
      if (eol < 0 && !_numberOnly.hasMatch(text.substring(i + 1))) {
        return text.substring(0, i);
      }
      i++;
      continue;
    }
    i++;
  }
  if (inFence && fenceMathStart >= 0) return text.substring(0, fenceMathStart);
  return text;
}
