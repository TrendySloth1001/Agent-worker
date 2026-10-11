import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/illustrations.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/illustration.dart';

/// HELLO on a new chat, with a peep and a few one-tap starter prompts.
/// The art and then the prompts drop out when space runs short (keyboard).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.onSuggestion});

  /// Sends a starter prompt; prompts are hidden when null.
  final ValueChanged<String>? onSuggestion;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final top = padding.top + AppSizes.topInset;
    final bottom = padding.bottom + AppSpacing.md + AppSizes.bottomInset;
    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxHeight - top - bottom;
        final showArt = room >= IllustrationSizes.helloHiddenBelow;
        final showPrompts =
            onSuggestion != null && room >= EmptyChatSuggestions.hiddenBelow;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            top,
            AppSpacing.screenPadding,
            bottom,
          ),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showArt) ...[
                    const Illustration(
                      kind: IllustrationKind.hello,
                      height: IllustrationSizes.hello,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Text(AppStrings.emptyTitle, style: context.text.display),
                  const SizedBox(height: AppSpacing.sm),
                  Text(AppStrings.emptySubtitle, style: context.text.bodySmall),
                  if (showPrompts) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final prompt in AppStrings.emptyPrompts)
                          _PromptChip(
                            label: prompt,
                            onTap: () {
                              Haptics.tap();
                              onSuggestion!(prompt);
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      child: Material(
        color: p.surface,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: Container(
            height: EmptyChatSuggestions.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: p.borderStrong, width: AppBorder.thin),
            ),
            child: Text(
              label,
              style: context.text.bodySmall.copyWith(color: p.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
