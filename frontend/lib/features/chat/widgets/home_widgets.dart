import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/home_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/conversation.dart';
import '../../settings/format.dart';

TextStyle _weight(TextStyle s, double w) =>
    s.copyWith(fontVariations: [FontVariation.weight(w)]);

/// A starter prompt: icon, tiny category, title and a one-line hint.
/// Tap sends it; long-press puts it in the composer.
class StarterCard extends StatelessWidget {
  const StarterCard({
    super.key,
    required this.starter,
    required this.onSend,
    required this.onEdit,
    this.compact = false,
  });

  /// Short-screen card: two title lines, no minimum height.
  final bool compact;
  final Starter starter;
  final VoidCallback onSend;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: p.border, width: AppBorder.thin),
    );
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: HomeStrings.starterSemantics(
        starter.kind.label,
        starter.title,
        starter.hint,
      ),
      onTap: onSend,
      onLongPress: onEdit,
      onLongPressHint: HomeStrings.longPressHint,
      child: Material(
        color: p.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: () {
            Haptics.tap();
            onSend();
          },
          onLongPress: () {
            Haptics.tap();
            onEdit();
          },
          child: Container(
            constraints: BoxConstraints(
              minHeight: compact ? 0 : HomeSizes.cardHeight,
            ),
            padding: const EdgeInsets.all(HomeSizes.cardPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: HomeSizes.cardIcon,
                      height: HomeSizes.cardIcon,
                      decoration: BoxDecoration(
                        color: p.surfaceHigh,
                        shape: BoxShape.circle,
                      ),
                      child: AppIcon(
                        starter.kind.icon,
                        size: AppIconSize.md,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        starter.kind.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  starter.title,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: _weight(
                    t.bodySmall,
                    600,
                  ).copyWith(color: p.textPrimary, height: 1.3),
                ),
                if (starter.hint != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    starter.hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall.copyWith(
                      fontSize: AppFontSize.label,
                      color: p.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tonal chip that teaches a feature; filled while that feature is on.
class CapabilityChip extends StatelessWidget {
  const CapabilityChip({
    super.key,
    required this.capability,
    required this.on,
    required this.onTap,
  });

  final HomeCapability capability;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = on ? p.textInverse : p.textPrimary;
    return Semantics(
      button: true,
      toggled: on,
      excludeSemantics: true,
      label: capability.label,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: HomeSizes.hit),
          child: Center(
            child: AnimatedContainer(
              duration: AppDurations.fast,
              height: HomeSizes.chipHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: on ? p.textPrimary : p.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(capability.icon, size: AppIconSize.md, color: fg),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    capability.label,
                    style: _weight(
                      context.text.bodySmall,
                      500,
                    ).copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recent chats as one grouped card: big radius at the ends, small between.
class RecentChats extends StatelessWidget {
  const RecentChats({super.key, required this.chats, required this.onOpen});

  final List<ConversationSummary> chats;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < chats.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xxs),
          _RecentRow(
            chat: chats[i],
            first: i == 0,
            last: i == chats.length - 1,
            onTap: () => onOpen(chats[i].id),
          ),
        ],
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.chat,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final ConversationSummary chat;
  final bool first, last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    const big = Radius.circular(HomeSizes.bigRadius);
    const small = Radius.circular(HomeSizes.smallRadius);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: first ? big : small,
        bottom: last ? big : small,
      ),
    );
    final title = (chat.title ?? '').trim().isEmpty
        ? HomeStrings.untitled
        : chat.title!.trim();
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: HomeStrings.openChat(title),
      onTap: onTap,
      child: Material(
        color: p.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: HomeSizes.recentRow),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: HomeSizes.recentIcon,
                  height: HomeSizes.recentIcon,
                  decoration: BoxDecoration(
                    color: p.surfaceHigh,
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(
                    HomeIcons.recent,
                    size: AppIconSize.md,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _weight(
                          t.bodySmall,
                          500,
                        ).copyWith(color: p.textPrimary),
                      ),
                      Text(
                        '${agoLabel(chat.updatedAt)} · '
                        '${HomeStrings.messages(chat.messageCount).toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption,
                      ),
                    ],
                  ),
                ),
                AppIcon(
                  HomeIcons.next,
                  size: AppIconSize.md,
                  color: p.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
