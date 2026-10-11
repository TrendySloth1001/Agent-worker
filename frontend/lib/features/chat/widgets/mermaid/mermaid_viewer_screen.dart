import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/system_chrome.dart';
import '../../../../core/widgets/copy_action.dart';
import '../markdown/code_block.dart';
import 'mermaid_view.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/widgets/app_icon.dart';

/// Full-screen diagram with pinch zoom and COPY SOURCE.
class MermaidViewerScreen extends StatefulWidget {
  const MermaidViewerScreen({super.key, required this.source});

  final String source;

  @override
  State<MermaidViewerScreen> createState() => _MermaidViewerScreenState();
}

class _MermaidViewerScreenState extends State<MermaidViewerScreen> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const AppIcon(AppIcons.back, size: AppIconSize.md),
            tooltip: AppStrings.back,
            onPressed: () {
              Haptics.tap();
              Navigator.pop(context);
            },
          ),
          title: const Text(AppStrings.diagram),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.screenPadding),
              child: Center(
                child: CopyAction(
                  text: widget.source,
                  label: AppStrings.copySource,
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppBorder.thin),
            child: Divider(color: p.border),
          ),
        ),
        body: _failed
            ? ListView(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  CodeBlock(
                    code: widget.source,
                    language: 'mermaid',
                    highlight: false,
                    headerLabel: AppStrings.diagramSyntaxError,
                    headerLabelColor: p.accent,
                  ),
                ],
              )
            : SafeArea(
                child: MermaidView(
                  source: widget.source,
                  full: true,
                  onResult: (r) {
                    if (r is MermaidFailed) setState(() => _failed = true);
                  },
                ),
              ),
      ),
    );
  }
}
