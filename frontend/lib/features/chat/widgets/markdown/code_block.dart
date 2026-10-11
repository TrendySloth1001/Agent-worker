import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' as hl;

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/copy_action.dart';

/// Fenced code: language label, COPY, horizontal scroll, syntax colors.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language,
    this.highlight = true,
    this.headerLabel,
    this.headerLabelColor,
  });

  final String code;
  final String? language;

  /// Off while a reply is still streaming.
  final bool highlight;

  /// Replaces the language label (for example an error title).
  final String? headerLabel;
  final Color? headerLabelColor;

  static final _cache = <String, List<hl.Node>>{};
  static const _cacheSize = 64;

  static List<hl.Node>? _parse(String code, String language) {
    final key = '$language\u0000$code';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    try {
      final nodes = hl.highlight.parse(code, language: language).nodes;
      if (nodes == null) return null;
      _cache[key] = nodes;
      if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
      return nodes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final lang = (language ?? '').trim();
    final label = headerLabel ?? (lang.isEmpty ? '' : lang.toUpperCase());

    List<hl.Node>? nodes;
    if (highlight &&
        lang.isNotEmpty &&
        code.length <= AppSizes.codeMaxHighlightChars) {
      nodes = _parse(code, lang);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.codeBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: AppSizes.codeHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: headerLabelColor),
                  ),
                ),
                CopyAction(text: code),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text.rich(
              TextSpan(
                style: t.code,
                children: nodes == null
                    ? [TextSpan(text: code)]
                    : _spans(nodes, p),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _keyword = {
    'keyword',
    'built_in',
    'type',
    'literal',
    'selector-tag',
    'selector-id',
    'selector-class',
    'name',
    'tag',
    'section',
    'bullet',
    'title',
  };
  static const _string = {
    'string',
    'regexp',
    'symbol',
    'attr',
    'attribute',
    'meta',
    'meta-string',
    'link',
    'template-variable',
    'variable',
    'subst',
  };
  static const _number = {'number', 'params', 'class'};
  static const _comment = {'comment', 'doctag', 'quote', 'formula'};

  Color? _color(String? className, AppPalette p) {
    if (className == null) return null;
    for (final part in className.split(' ')) {
      if (_comment.contains(part)) return p.synComment;
      if (_keyword.contains(part)) return p.synKeyword;
      if (_string.contains(part)) return p.synString;
      if (_number.contains(part)) return p.synNumber;
    }
    return null;
  }

  List<InlineSpan> _spans(List<hl.Node> nodes, AppPalette p) {
    return [
      for (final node in nodes)
        TextSpan(
          text: node.value,
          style: TextStyle(color: _color(node.className, p)),
          children: node.children == null ? null : _spans(node.children!, p),
        ),
    ];
  }
}
