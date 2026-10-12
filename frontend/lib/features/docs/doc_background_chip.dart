import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import 'doc_controller.dart';
import 'doc_registry.dart';
import 'doc_screen.dart';

/// "1 DOC WRITING": a document still being written while the user is
/// elsewhere (another chat, the chat list). Tap to open it. Renders nothing
/// when no document is in the background.
class DocBackgroundChip extends StatelessWidget {
  const DocBackgroundChip({super.key, this.fallback});

  /// Shown when no document is writing in the background.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final registry = DocRegistry.instance;
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final c = registry.backgroundRunning;
        if (c == null) return fallback ?? const SizedBox.shrink();
        return _Chip(
          key: const ValueKey(DocBackgroundChip),
          controller: c,
          count: registry.running.where((x) => !x.viewing).length,
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.controller, required this.count});

  final DocController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final doc = controller.doc;
    final progress = doc.total > 0 ? ' ${doc.done}/${doc.total}' : '';
    return Semantics(
      button: true,
      label: DocStrings.backgroundOpen,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          openDoc(context, controller.id);
        },
        child: Center(
          child: Container(
            height: DocSizes.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: DocSizes.chipPadH),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: p.borderStrong, width: AppBorder.thin),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Pulse(),
                const SizedBox(width: AppSpacing.sm),
                AppIcon(DocIcons.doc, size: AppIconSize.sm, color: p.textPrimary),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    '${DocStrings.backgroundRunning(count)}$progress',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption.copyWith(color: p.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent dot fading in and out while the doc is written.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: DocSizes.pulse)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: DocSizes.pulseMin, end: 1.0).animate(_c),
    child: Container(
      width: DocSizes.chipDot,
      height: DocSizes.chipDot,
      decoration: BoxDecoration(
        color: context.palette.accent,
        shape: BoxShape.circle,
      ),
    ),
  );
}
