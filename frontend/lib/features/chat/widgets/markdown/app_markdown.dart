import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../data/chat_event.dart';
import '../open_url.dart';
import 'citation_chip.dart';
import 'citation_syntax.dart';
import 'evidence_sheet.dart';
import 'code_block_builder.dart';
import 'emoji_icons.dart';
import 'inline_icon.dart';
import 'inline_image.dart';
import 'md_blocks.dart';
import 'md_callout.dart';
import 'math_syntax.dart';
import 'math_view.dart';
import 'md_table.dart';
import 'timeline_list.dart';

/// Markdown for assistant replies: code blocks, diagrams, citation tags.
class AppMarkdown extends StatelessWidget {
  const AppMarkdown({
    super.key,
    required this.data,
    required this.citations,
    required this.streaming,
    this.evidence = const [],
  });

  final String data;
  final List<Citation> citations;
  final List<Evidence> evidence;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    return _Flow(
      // The package only re-parses when the text or style changes, so the
      // switch from streaming to done (code -> rendered diagrams) needs new
      // elements.
      key: ValueKey(streaming),
      source: emojiToIcons(
        streaming ? hidePartialMath(hidePartialIcon(data)) : data,
      ),
      citations: citations,
      evidence: evidence,
      streaming: streaming,
    );
  }

  static MarkdownStyleSheet styleSheet(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return MarkdownStyleSheet(
      p: t.body,
      h1: t.title,
      h2: t.title,
      h3: t.title,
      h4: t.title,
      strong: t.body.copyWith(fontWeight: FontWeight.w700),
      em: t.body.copyWith(fontStyle: FontStyle.italic),
      listBullet: t.body,
      a: t.body.copyWith(
        color: p.accent,
        decoration: TextDecoration.underline,
        decorationColor: p.accent,
      ),
      blockquote: t.body.copyWith(color: p.textSecondary),
      code: t.code.copyWith(backgroundColor: p.surfaceHigh),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: p.borderStrong, width: 2)),
      ),
      blockquotePadding: const EdgeInsets.only(left: AppSpacing.md),
      // Code and diagram blocks draw their own frame.
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      tableHead: t.label,
      tableBody: t.bodySmall.copyWith(color: p.textPrimary),
      tableBorder: TableBorder.all(color: p.border, width: AppBorder.thin),
      tableCellsPadding: const EdgeInsets.all(AppSpacing.sm),
    );
  }
}

/// Block-level layout: plain markdown, with lists, tables and callouts pulled
/// out into their own widgets. Item, cell and callout text recurse into it.
class _Flow extends StatelessWidget {
  const _Flow({
    super.key,
    required this.source,
    required this.citations,
    required this.streaming,
    this.evidence = const [],
    this.cell,
  });

  final String source;
  final List<Citation> citations;
  final List<Evidence> evidence;
  final bool streaming;

  /// null = body text, otherwise a table cell (true = header cell).
  final bool? cell;

  Widget _inline(BuildContext context, String text, {bool? cell}) => _Flow(
    source: text,
    citations: citations,
    evidence: evidence,
    streaming: streaming,
    cell: cell,
  );

  @override
  Widget build(BuildContext context) {
    final cell = this.cell;
    if (cell != null) return _markdown(context, source, cell: cell);

    final blocks = parseBlocks(source);
    if (blocks.length == 1 && blocks.first is MdText) {
      return _markdown(context, source);
    }
    final children = <Widget>[];
    for (final b in blocks) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(switch (b) {
        MdText() => _markdown(context, b.text),
        MdListBlock() => TimelineList(
          list: b.list,
          renderText: (t) => _inline(context, t),
        ),
        MdTableBlock() => MdTable(
          block: b,
          renderCell: (t, {required header}) =>
              _inline(context, t, cell: header),
        ),
        MdMathBlock() => MathBlock(tex: b.tex),
        MdImageBlock() => InlineImageBlock(query: b.query, caption: b.caption),
        MdCalloutBlock() => MdCallout(
          block: b,
          renderBody: (t) => _inline(context, t),
        ),
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _markdown(BuildContext context, String text, {bool? cell}) {
    var sheet = AppMarkdown.styleSheet(context);
    if (cell != null) {
      final p = context.palette;
      final t = context.text;
      final bodyStyle = t.bodySmall.copyWith(color: p.textPrimary);
      sheet = sheet.copyWith(
        p: cell ? bodyStyle.copyWith(fontWeight: FontWeight.w700) : bodyStyle,
        strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
        code: t.code.copyWith(
          fontSize: MdSizes.tableCodeFontSize,
          backgroundColor: p.surfaceHigh,
        ),
      );
    }
    return MarkdownBody(
      data: prepareCitations(text, citations),
      selectable: false,
      styleSheet: sheet,
      inlineSyntaxes: [
        MathSyntax(),
        CitationSyntax(),
        IconSyntax(),
        StrayImageSyntax(),
      ],
      builders: {
        'pre': CodeBlockBuilder(streaming: streaming),
        'icon': IconBuilder(),
        'math': MathBuilder(inTable: cell != null),
        'cite': CitationBuilder(
          citations: citations,
          onTap: (context, citation) =>
              showEvidenceSheet(context, citation, evidence),
        ),
      },
      onTapLink: (text, href, title) {
        if (href != null) openUrl(context, href);
      },
    );
  }
}
