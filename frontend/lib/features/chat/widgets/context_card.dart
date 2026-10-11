import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';
import '../../../data/chat_message.dart';
import 'markdown/app_markdown.dart';

/// The briefing a merged chat starts from: which chats it came from and
/// the summary the model reads in their place.
class ContextCard extends StatefulWidget {
  const ContextCard({super.key, required this.message, required this.onOpen});

  final ChatMessage message;

  /// Opens one of the original chats by id.
  final ValueChanged<String> onOpen;

  @override
  State<ContextCard> createState() => _ContextCardState();
}

class _ContextCardState extends State<ContextCard> {
  bool _expanded = false;

  List<({String id, String title})> get _sources => [
    for (final s in widget.message.meta['sources'] as List? ?? const [])
      if (s is Map<String, dynamic> && s['id'] is String)
        (id: s['id'] as String, title: s['title'] as String? ?? ''),
  ];

  bool get _fallback => widget.message.meta['summarySource'] == 'fallback';

  void _toggle() {
    Haptics.tap();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                AppIcons.merge,
                size: AppIconSize.sm,
                color: p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(LineageStrings.mergedFrom, style: t.caption),
              ),
              if (_fallback)
                Text(
                  LineageStrings.fallbackSummary,
                  style: t.caption.copyWith(color: p.textTertiary),
                ),
            ],
          ),
          if (_sources.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final s in _sources)
                  _SourceChip(
                    title: s.title.isEmpty ? AppStrings.untitled : s.title,
                    onTap: () {
                      Haptics.tap();
                      widget.onOpen(s.id);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AnimatedSize(
            duration: AppDurations.normal,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: _expanded
                    ? double.infinity
                    : LineageSizes.summaryPeek,
              ),
              child: ClipRect(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: AppMarkdown(
                    data: widget.message.content,
                    citations: const [],
                    streaming: false,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: IconLabel(
                icon: _expanded ? AppIcons.collapse : AppIcons.expand,
                text: _expanded
                    ? LineageStrings.hideSummary
                    : LineageStrings.showSummary,
                style: t.caption,
                color: p.textSecondary,
                iconSize: AppIconSize.sm,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            LineageStrings.summaryNote,
            style: t.bodySmall.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Bordered pill naming an original chat; tap opens it.
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: AppSizes.chipHeight,
        constraints: const BoxConstraints(maxWidth: LineageSizes.chipMaxWidth),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.chipHorizontalPadding,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: p.borderStrong, width: AppBorder.thin),
        ),
        child: IconLabel(
          icon: AppIcons.chevronRight,
          text: title.toUpperCase(),
          style: context.text.caption,
          color: p.textPrimary,
        ),
      ),
    );
  }
}
