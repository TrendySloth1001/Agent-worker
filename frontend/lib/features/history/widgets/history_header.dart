import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/history.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/constants/app_icons.dart';

/// Tappable icon with a 44dp target, a tooltip and a semantics label.
class SidebarIconButton extends StatelessWidget {
  const SidebarIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: () {
            Haptics.tap();
            onTap();
          },
          radius: HistorySizes.iconButton / 2,
          child: SizedBox.square(
            dimension: HistorySizes.iconButton,
            child: Center(
              child: AppIcon(
                icon,
                size: AppIconSize.lg - AppSpacing.xxs,
                color: color ?? context.palette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top of the sidebar: the wordmark with search and new chat, or the search
/// field once it is open, or BACK + ARCHIVED while the archive is shown.
class HistoryHeader extends StatelessWidget {
  const HistoryHeader({
    super.key,
    required this.searchOpen,
    required this.archived,
    required this.search,
    required this.searchFocus,
    required this.onQuery,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onNewChat,
    required this.onBack,
  });

  final bool searchOpen;
  final bool archived;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ValueChanged<String> onQuery;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final VoidCallback onNewChat;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: HistorySizes.headerHeight),
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : HistoryDurations.swap,
        child: searchOpen
            ? _searchRow(context)
            : archived
            ? _archivedRow(context)
            : _brandRow(context),
      ),
    );
  }

  Widget _brandRow(BuildContext context) {
    final p = context.palette;
    return Padding(
      key: const ValueKey('brand'),
      padding: const EdgeInsets.only(
        left: AppSpacing.screenPadding,
        right: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                AppStrings.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.title.copyWith(
                  fontVariations: const [FontVariation.weight(600)],
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            width: AppSizes.dot,
            height: AppSizes.dot,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
          ),
          const Spacer(),
          SidebarIconButton(
            icon: HistoryIcons.search,
            label: HistoryStrings.search,
            onTap: onOpenSearch,
          ),
          SidebarIconButton(
            icon: HistoryIcons.newChat,
            label: HistoryStrings.newChat,
            onTap: onNewChat,
          ),
        ],
      ),
    );
  }

  Widget _archivedRow(BuildContext context) {
    return Padding(
      key: const ValueKey('archived'),
      padding: const EdgeInsets.only(right: AppSpacing.screenPadding),
      child: Row(
        children: [
          SidebarIconButton(
            icon: HistoryIcons.back,
            label: HistoryStrings.backToChats,
            onTap: onBack,
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                HistoryStrings.archivedTitle,
                style: context.text.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SidebarIconButton(
            icon: HistoryIcons.search,
            label: HistoryStrings.search,
            onTap: onOpenSearch,
          ),
        ],
      ),
    );
  }

  Widget _searchRow(BuildContext context) {
    final p = context.palette;
    return Padding(
      key: const ValueKey('search'),
      padding: const EdgeInsets.only(
        left: AppSpacing.screenPadding,
        right: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: search,
              focusNode: searchFocus,
              autofocus: true,
              onChanged: onQuery,
              style: context.text.body,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: HistoryStrings.searchHint,
                prefixIcon: AppIcon(
                  HistoryIcons.search,
                  size: AppIconSize.md,
                  color: p.textTertiary,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: AppSizes.minTap - AppSpacing.sm,
                ),
              ),
            ),
          ),
          SidebarIconButton(
            icon: HistoryIcons.close,
            label: HistoryStrings.closeSearch,
            onTap: onCloseSearch,
          ),
        ],
      ),
    );
  }
}
