import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../mermaid/mermaid_block.dart';
import '../rich/ask_card.dart';
import '../rich/diff_block.dart';
import '../rich/email_card.dart';
import '../rich/flow_card.dart';
import '../rich/message_card.dart';
import '../rich/rich_parsers.dart';
import '../rich/spec_card.dart';
import '../rich/widget_registry.dart';
import '../../../../core/constants/rich_cards.dart';
import 'code_block.dart';

/// Replaces fenced code (`pre > code`) with [CodeBlock], or a diagram for
/// `mermaid` fences once the reply has finished streaming.
class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder({required this.streaming});

  final bool streaming;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var language = '';
    final children = element.children;
    if (children != null && children.isNotEmpty) {
      final first = children.first;
      if (first is md.Element) {
        final cls = first.attributes['class'];
        if (cls != null && cls.startsWith('language-')) {
          language = cls.substring('language-'.length);
        }
      }
    }
    final code = element.textContent.replaceFirst(RegExp(r'\n$'), '');
    final registry = buildRichWidget(language, code, streaming: streaming);
    if (registry != null) return registry;
    if (language == 'mermaid' && !streaming) {
      return MermaidBlock(source: code);
    }
    if (streaming && (language == 'ask' || language == 'flow')) {
      return RichPlaceholder(
        label: language == 'ask' ? AskStrings.preparing : FlowStrings.preparing,
      );
    }
    if (!streaming) {
      switch (language) {
        case 'email':
          final d = parseEmail(code);
          if (d != null) return EmailCard(draft: d);
        case 'message':
          final d = parseMessage(code);
          if (d != null) return MessageCard(draft: d);
        case 'card':
          final d = parseSpecCard(code);
          if (d != null) return SpecCard(data: d);
        case 'ask':
          final d = parseAsk(code);
          if (d != null) return AskCard(data: d);
        case 'flow':
          final d = parseFlow(code);
          if (d != null) return FlowCard(data: d);
        case 'diff':
          return DiffBlock(code: code);
      }
    }
    return CodeBlock(code: code, language: language, highlight: !streaming);
  }
}
