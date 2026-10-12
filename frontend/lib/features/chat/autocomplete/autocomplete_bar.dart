import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/suggest.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/glass.dart';

/// Row above the composer: an accept button for the ghost text and the
/// next-word chips. Empty (zero height) when there is nothing to offer.
class AutocompleteBar extends StatelessWidget {
  const AutocompleteBar({
    super.key,
    required this.ghost,
    required this.words,
    required this.onAccept,
    required this.onWord,
  });

  final String ghost;
  final List<String> words;
  final VoidCallback onAccept;
  final ValueChanged<String> onWord;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return AnimatedSize(
      duration: AppDurations.fast,
      alignment: Alignment.bottomCenter,
      child: ghost.isEmpty && words.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (ghost.isNotEmpty) ...[
                      Semantics(
                        button: true,
                        label: SuggestStrings.accept,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Haptics.tap();
                            onAccept();
                          },
                          child: Glass(
                            radius: AppRadius.pill,
                            child: SizedBox(
                              width: SuggestSizes.acceptWidth,
                              height: SuggestSizes.wordChipHeight,
                              child: AppIcon(
                                SuggestIcons.accept,
                                size: AppIconSize.sm,
                                color: p.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    for (final word in words) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Haptics.tap();
                          onWord(word);
                        },
                        child: Glass(
                          radius: AppRadius.pill,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.chipHorizontalPadding,
                          ),
                          child: SizedBox(
                            height: SuggestSizes.wordChipHeight,
                            child: Center(
                              child: Text(
                                word,
                                style: t.bodySmall.copyWith(
                                  color: p.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
