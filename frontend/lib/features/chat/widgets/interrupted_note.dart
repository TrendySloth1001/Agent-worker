import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_message.dart';
import '../../docs/doc_text.dart';
import '../stream_retry.dart';

/// Under an answer whose stream broke (chat and overlay): "Reconnecting…"
/// while an automatic retry waits, then "Answer interrupted · Retry" once
/// the retries are spent. Calm secondary text, never an error line; the
/// partial answer above it stays.
class InterruptedNote extends StatelessWidget {
  const InterruptedNote({super.key, required this.message, this.onRetry});

  final ChatMessage message;

  /// Asks again (null: no Retry, e.g. an older answer).
  final VoidCallback? onRetry;

  /// Whether [m] has something to show here (an empty reply that is
  /// reconnecting shows it in its thinking indicator instead).
  static bool shows(ChatMessage m) =>
      m.interrupted ||
      (m.isStreaming &&
          m.content.isNotEmpty &&
          m.status == StreamRetry.reconnectingPhase);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = context.text.meta.copyWith(color: p.textSecondary);
    final reconnecting = !message.interrupted;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            reconnecting ? AppIcons.regenerate : AppIcons.interrupted,
            size: AppIconSize.sm,
            color: p.textTertiary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            reconnecting
                ? AppStrings.reconnecting
                : AppStrings.answerInterrupted,
            style: style,
          ),
          if (!reconnecting && onRetry != null) ...[
            Text(' · ', style: style),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Haptics.tap();
                  onRetry!();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Text(
                    AppStrings.answerRetry,
                    style: style.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: p.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
