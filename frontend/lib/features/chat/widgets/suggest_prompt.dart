import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/smart_toggles.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';
import '../../../data/chat_event.dart';

/// Inline Material 3 prompt above the composer: the server thinks this turn
/// would benefit from the knowledge base or a Doc and asks, never assumes.
class SuggestPrompt extends StatelessWidget {
  const SuggestPrompt({
    super.key,
    required this.suggestion,
    required this.onAccept,
    required this.onDismiss,
  });

  final SuggestToggleEvent suggestion;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  bool get _isKb => suggestion.kind == SuggestKind.kb;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final scheme = Theme.of(context).colorScheme;
    final titles = suggestion.sampleTitles
        .take(SmartConfig.maxTitles)
        .join(', ');
    final title = _isKb ? SmartStrings.kbTitle : SmartStrings.docTitle;
    final body = _isKb
        ? SmartStrings.kbBody(suggestion.sampleTitles.length, titles)
        : SmartStrings.docBody;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(SmartSizes.promptRadius),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(
                _isKb ? AppIcons.knowledge : AppIcons.doc,
                size: SmartSizes.promptIcon,
                color: p.accent,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.body.copyWith(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: SmartSizes.hintSpacing),
                    Text(
                      body,
                      style: t.bodySmall.copyWith(color: p.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: p.textSecondary,
                    minimumSize: const Size(0, AppSizes.segmentHeight),
                  ),
                  onPressed: () {
                    Haptics.tap();
                    onDismiss();
                  },
                  child: Text(
                    _isKb ? SmartStrings.notNow : SmartStrings.docChat,
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppSizes.segmentHeight),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                  ),
                  onPressed: () {
                    Haptics.tap();
                    onAccept();
                  },
                  child: Text(
                    _isKb ? SmartStrings.kbUse : SmartStrings.docWrite,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle "Searched the web" note under a reply the server searched for on
/// its own (WEB on Auto). The source chips follow it.
class SearchedWebNote extends StatelessWidget {
  const SearchedWebNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconLabel(
        icon: AppIcons.web,
        text: SmartStrings.searchedWeb,
        style: context.text.caption,
        color: context.palette.textTertiary,
      ),
    );
  }
}
