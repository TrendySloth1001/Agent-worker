import '../../../core/constants/mascot.dart';
import '../../../core/widgets/mascot.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/illustrations.dart';
import '../../../core/haptics.dart';
import '../../../core/constants/suggest.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/suggest_api.dart';
import 'suggestion_chips.dart';

/// HELLO on a new chat, with a peep and a few one-tap starter prompts.
/// The art and then the prompts drop out when space runs short (keyboard).
class EmptyState extends StatefulWidget {
  const EmptyState({super.key, this.onSuggestion});

  /// Sends a starter prompt; prompts are hidden when null.
  final ValueChanged<String>? onSuggestion;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState> {
  /// Starters from recent chats, kept for the session so new chats show
  /// them at once; the built-in prompts fill in until they arrive.
  static List<String> _cached = const [];
  static DateTime? _cachedAt;

  List<String> _prompts = _cached;

  @override
  void initState() {
    super.initState();
    final at = _cachedAt;
    if (at != null &&
        DateTime.now().difference(at) < SuggestConfig.startersTtl) {
      return;
    }
    SuggestApi().starters().then((list) {
      if (list.isEmpty) return;
      _cached = list;
      _cachedAt = DateTime.now();
      if (mounted) setState(() => _prompts = list);
    });
  }

  ValueChanged<String>? get onSuggestion => widget.onSuggestion;

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
                    const Mascot(
                      state: MascotState.idle,
                      size: MascotSizes.hero,
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
                        for (final prompt
                            in _prompts.isEmpty
                                ? AppStrings.emptyPrompts
                                : _prompts)
                          PromptChip(
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
