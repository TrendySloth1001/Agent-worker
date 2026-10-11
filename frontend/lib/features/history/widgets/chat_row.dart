import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/conversation.dart';

/// One conversation in a list: title, preview and time, red dot if current.
class ChatRow extends StatelessWidget {
  const ChatRow({
    super.key,
    required this.chat,
    required this.time,
    required this.isCurrent,
    required this.onTap,
    required this.onLongPress,
  });

  final ConversationSummary chat;
  final String time;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isCurrent) ...[
                        Container(
                          width: AppSizes.dot,
                          height: AppSizes.dot,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Expanded(
                        child: Text(
                          chat.title ?? AppStrings.untitled,
                          style: t.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (chat.preview.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      chat.preview,
                      style: t.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (chat.isFork || chat.isMerge) ...[
              AppIcon(
                chat.isFork ? AppIcons.fork : AppIcons.merge,
                size: AppIconSize.xs,
                color: p.textTertiary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                chat.isFork ? LineageStrings.fork : LineageStrings.merge,
                style: t.caption.copyWith(color: p.textTertiary),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            if (chat.pinned) ...[
              AppIcon(
                AppIcons.pin,
                size: AppIconSize.xs,
                color: p.textTertiary,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(time, style: t.caption),
          ],
        ),
      ),
    );
  }
}
