import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_html.dart';
import '../markdown/code_block.dart';

/// Syntax-highlighted HTML source (COPY comes from CodeBlock's header).
/// With [maxHeight] it scrolls inside a bounded box; without it fills the
/// parent.
class HtmlSourceView extends StatelessWidget {
  const HtmlSourceView({super.key, required this.source, this.maxHeight});

  final String source;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final block = CodeBlock(code: source, language: HtmlStrings.sourceLanguage);
    if (maxHeight == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [block],
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight!),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: block,
      ),
    );
  }
}
