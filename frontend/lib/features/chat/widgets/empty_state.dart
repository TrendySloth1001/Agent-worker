import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/greetings.dart';
import '../../auth/auth_controller.dart';
import '../../../core/constants/illustrations.dart';
import '../../../core/haptics.dart';
import '../../../core/constants/suggest.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/widgets/rotating_illustration.dart';
import '../../../data/suggest_api.dart';
import 'suggestion_chips.dart';

/// A greeting on a new chat under one line-art scene, both picked at random
/// each time an empty chat opens, plus a few one-tap starter prompts.
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

  /// Picked once per empty chat, so it never changes while you look at it.
  final Greeting _greeting = Greetings.pick(
    name: AuthController.instance.user?.name,
  );

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
                    const RotatingIllustration(
                      kinds: IllustrationKind.home,
                      height: IllustrationSizes.hello,
                      cycle: false,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Text(
                    _greeting.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: context.text.headline.copyWith(
                      fontSize: AppFontSize.display,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _greeting.subtitle,
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall,
                  ),
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
