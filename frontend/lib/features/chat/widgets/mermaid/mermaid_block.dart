import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../markdown/code_block.dart';
import 'mermaid_view.dart';
import 'mermaid_viewer_screen.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/widgets/app_icon.dart';

/// Limits how many WebViews are alive at once; the rest wait for a tap.
abstract final class MermaidPool {
  static int _live = 0;

  static bool tryAcquire() {
    if (_live >= AppSizes.maxLiveDiagrams) return false;
    _live++;
    return true;
  }

  static void release() {
    if (_live > 0) _live--;
  }
}

/// A rendered diagram inside a reply. Falls back to the raw source when the
/// syntax is invalid.
class MermaidBlock extends StatefulWidget {
  const MermaidBlock({super.key, required this.source});

  final String source;

  @override
  State<MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<MermaidBlock> {
  late bool _live = MermaidPool.tryAcquire();
  double? _height;
  bool _failed = false;

  @override
  void dispose() {
    if (_live) MermaidPool.release();
    super.dispose();
  }

  void _onResult(MermaidResult result) {
    if (!mounted) return;
    setState(() {
      switch (result) {
        case MermaidSized(:final height):
          _height = height;
        case MermaidFailed():
          _failed = true;
          if (_live) {
            MermaidPool.release();
            _live = false;
          }
      }
    });
  }

  void _openViewer() {
    Haptics.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MermaidViewerScreen(source: widget.source),
      ),
    );
  }

  void _renderHere() {
    if (MermaidPool.tryAcquire()) {
      Haptics.tap();
      setState(() => _live = true);
    } else {
      _openViewer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return CodeBlock(
        code: widget.source,
        language: 'mermaid',
        highlight: false,
        headerLabel: AppStrings.diagramSyntaxError,
        headerLabelColor: context.palette.accent,
      );
    }
    final p = context.palette;
    final t = context.text;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
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
                Expanded(child: Text(AppStrings.diagram, style: t.caption)),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openViewer,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.fullscreen,
                        size: AppIconSize.sm,
                        color: p.textTertiary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(AppStrings.viewDiagram, style: t.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_live)
            Stack(
              children: [
                SizedBox(
                  height: _height ?? AppSizes.mermaidMinHeight,
                  child: IgnorePointer(
                    child: MermaidView(
                      source: widget.source,
                      onResult: _onResult,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _openViewer,
                  ),
                ),
              ],
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _renderHere,
              child: SizedBox(
                height: AppSizes.mermaidPlaceholderHeight,
                child: Center(
                  child: Text(AppStrings.tapToRender, style: t.caption),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
