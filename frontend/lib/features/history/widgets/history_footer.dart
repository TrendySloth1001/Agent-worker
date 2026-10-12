import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/apps.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/auth_constants.dart';
import '../../../core/constants/history.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/constants/storage.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/auth_controller.dart';
import '../../settings/widgets/settings_kit.dart';
import 'history_header.dart';

/// Bottom of the sidebar: Material 3 destinations (Apps, Docs, Storage,
/// Archived) as tonal pills, then the account card as Settings draws it, with
/// a settings button.
class HistoryFooter extends StatelessWidget {
  const HistoryFooter({
    super.key,
    required this.archivedActive,
    required this.compact,
    required this.onApps,
    required this.onDocs,
    required this.onStorage,
    required this.onArchived,
    required this.onProfile,
    required this.onSettings,
  });

  final bool archivedActive;

  /// Icons only, in one row, for short (landscape) screens.
  final bool compact;
  final VoidCallback onApps;
  final VoidCallback onDocs;
  final VoidCallback onStorage;
  final VoidCallback onArchived;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _Destination(
        icon: AppsIcons.hub,
        label: HistoryStrings.apps,
        compact: compact,
        onTap: onApps,
      ),
      _Destination(
        icon: HistoryIcons.docs,
        label: HistoryStrings.docs,
        compact: compact,
        onTap: onDocs,
      ),
      _Destination(
        icon: StorageIcons.section,
        label: HistoryStrings.storage,
        compact: compact,
        onTap: onStorage,
      ),
      _Destination(
        icon: HistoryIcons.archive,
        label: HistoryStrings.archived,
        compact: compact,
        selected: archivedActive,
        onTap: onArchived,
      ),
    ];
    const gap = SizedBox(width: DrawerMotion.footerGap);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DrawerMotion.itemInset,
        AppSpacing.sm,
        DrawerMotion.itemInset,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // One row of four: icons only on short screens, icon over label otherwise.
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) gap,
                Expanded(child: tiles[i]),
              ],
            ],
          ),
          const SizedBox(height: DrawerMotion.footerGap),
          _AccountCard(onProfile: onProfile, onSettings: onSettings),
        ],
      ),
    );
  }
}

/// A drawer destination: icon and label in a stadium, filled when selected.
class _Destination extends StatelessWidget {
  const _Destination({
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
    this.selected = false,
  });

  final AppIconData icon;
  final String label;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        // Plain buttons: no fill unless this destination is active.
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DrawerMotion.footerTileRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: SizedBox(
            height: compact
                ? DrawerMotion.footerTileHeight
                : DrawerMotion.footerTileTallHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(icon, size: AppIconSize.md, color: color),
                if (!compact) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall!.copyWith(color: color),
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

/// Avatar, name and email in a Settings group cell; the row opens Profile and
/// the trailing button opens Settings.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.onProfile, required this.onSettings});

  final VoidCallback onProfile;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final auth = AuthController.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final user = auth.user;
        return SettingsGroup(
          entries: [
            GroupEntry(
              Semantics(
                button: true,
                label: ProfileStrings.openProfile,
                child: ListTile(
                  contentPadding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.lg,
                    end: AppSpacing.xs,
                  ),
                  leading: UserAvatar(user: user, size: HistorySizes.avatar),
                  title: Text(
                    user?.displayName ?? SettingsStrings.accountFallback,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    user?.email ?? SettingsStrings.accountHelp,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: SidebarIconButton(
                    icon: AppIcons.settings,
                    label: HistoryStrings.openSettings,
                    onTap: onSettings,
                    color: p.textSecondary,
                  ),
                  onTap: () {
                    Haptics.tap();
                    onProfile();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
