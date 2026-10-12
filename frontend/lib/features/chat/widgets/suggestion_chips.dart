import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/suggest.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/chat_message.dart';
import '../chat_actions.dart';

/// Follow-up prompts under the newest reply. Tap sends one; long-press puts
/// it in the composer to edit. Hidden on older replies and while sending.
class SuggestionChips extends StatelessWidget {
  const SuggestionChips({super.key, required this.message});

  final ChatMessage message;

  /// The saved follow-ups of [message] (empty when it has none).
  static List<String> itemsOf(ChatMessage message) => [
    for (final s
        in message.meta[SuggestConfig.followUpKey] as List? ?? const [])
      if (s is String && s.trim().isNotEmpty) s.trim(),
  ];

  @override
  Widget build(BuildContext context) {
    final actions = ChatActions.of(context);
    final items = itemsOf(message);
    if (actions == null ||
        actions.sending ||
        !identical(actions.latest, message) ||
        items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Semantics(
        label: SuggestStrings.followUps,
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final text in items)
              PromptChip(
                label: text,
                onTap: () {
                  Haptics.tap();
                  actions.send(text);
                },
                onLongPress: actions.edit == null
                    ? null
                    : () {
                        Haptics.tick();
                        actions.edit!(text);
                      },
              ),
          ],
        ),
      ),
    );
  }
}

/// Outlined pill with a prompt; shared by follow-ups and starter prompts.
class PromptChip extends StatelessWidget {
  const PromptChip({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

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
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: SuggestSizes.chipHeight,
              maxWidth: SuggestSizes.chipMaxWidth,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
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
