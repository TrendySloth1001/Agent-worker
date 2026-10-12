import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/chat_cleanup.dart';
import '../../../core/constants/history.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../history_controller.dart';
import 'history_header.dart';

/// Contextual header while chats are being picked: close, the count,
/// select all or none, and the actions for the picked chats.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.controller,
    required this.onArchive,
    required this.onPin,
    required this.onDelete,
    this.onMore,
  });

  final HistoryController controller;
  final VoidCallback onArchive;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  /// The single picked chat's full action sheet (shown for one chat only).
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final count = c.selected.length;
    final none = count == 0;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('selection'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: ChatCleanupSizes.barHeight,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              children: [
                SidebarIconButton(
                  icon: ChatCleanupIcons.close,
                  label: ChatCleanupStrings.exitSelection,
                  onTap: c.endSelection,
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    header: true,
                    child: Text(
                      ChatCleanupStrings.selected(count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                  ),
                ),
                if (c.selectingAll)
                  Semantics(
                    label: ChatCleanupStrings.loadingAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: SizedBox.square(
                        dimension: AppIconSize.sm,
                        child: CircularProgressIndicator(
                          strokeWidth: AppBorder.thick,
                          color: context.palette.textTertiary,
                        ),
                      ),
                    ),
                  )
                else
                  TextButton(
                    onPressed: () {
                      Haptics.tap();
                      c.allSelected ? c.selectNone() : c.selectAll();
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, AppSizes.minTap),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                    ),
                    child: Text(
                      c.allSelected
                          ? ChatCleanupStrings.selectNone
                          : ChatCleanupStrings.selectAll,
                    ),
                  ),
                if (onMore != null)
                  SidebarIconButton(
                    icon: AppIcons.more,
                    label: HistoryStrings.moreActions,
                    onTap: onMore!,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: _Action(
                  icon: c.archived
                      ? ChatCleanupIcons.restore
                      : ChatCleanupIcons.archive,
                  label: c.archived
                      ? ChatCleanupStrings.restore
                      : ChatCleanupStrings.archive,
                  onTap: none ? null : onArchive,
                ),
              ),
              if (!c.archived) ...[
                const SizedBox(width: ChatCleanupSizes.actionGap),
                Expanded(
                  child: _Action(
                    icon: c.selectionPinned
                        ? ChatCleanupIcons.unpin
                        : ChatCleanupIcons.pin,
                    label: c.selectionPinned
                        ? ChatCleanupStrings.unpin
                        : ChatCleanupStrings.pin,
                    onTap: none ? null : onPin,
                  ),
                ),
              ],
              const SizedBox(width: ChatCleanupSizes.actionGap),
              Expanded(
                child: _Action(
                  icon: ChatCleanupIcons.delete,
                  label: ChatCleanupStrings.delete,
                  onTap: none ? null : onDelete,
                  background: scheme.errorContainer,
                  foreground: scheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A compact tonal button with an icon and a label.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
    this.foreground,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final scheme = Theme.of(context).colorScheme;
    final bg = background ?? scheme.surfaceContainerHigh;
    final fg = foreground ?? scheme.onSurface;
    return FilledButton.tonalIcon(
      onPressed: enabled
          ? () {
              Haptics.tap();
              onTap!();
            }
          : null,
      icon: AppIcon(icon, size: AppIconSize.sm, color: enabled ? fg : null),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, ChatCleanupSizes.actionHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
    );
  }
}
