import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/auth_constants.dart';
import '../../../core/constants/history.dart';
import '../../../core/constants/storage.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/auth_controller.dart';
import 'history_header.dart';

/// Bottom of the sidebar: quick entries (Knowledge, Docs, Storage, Archived)
/// and the account row, which opens the profile, with a settings button.
class HistoryFooter extends StatelessWidget {
  const HistoryFooter({
    super.key,
    required this.archivedActive,
    required this.compact,
    required this.onKnowledge,
    required this.onDocs,
    required this.onStorage,
    required this.onArchived,
    required this.onProfile,
    required this.onSettings,
  });

  final bool archivedActive;

  /// Icons only, for short (landscape) screens.
  final bool compact;
  final VoidCallback onKnowledge;
  final VoidCallback onDocs;
  final VoidCallback onStorage;
  final VoidCallback onArchived;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: AppBorder.thin, color: p.border),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HistorySizes.rowInset,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              _Quick(
                icon: AppIcons.knowledge,
                label: HistoryStrings.knowledge,
                compact: compact,
                onTap: onKnowledge,
              ),
              _Quick(
                icon: HistoryIcons.docs,
                label: HistoryStrings.docs,
                compact: compact,
                onTap: onDocs,
              ),
              _Quick(
                icon: StorageIcons.section,
                label: HistoryStrings.storage,
                compact: compact,
                onTap: onStorage,
              ),
              _Quick(
                icon: HistoryIcons.archive,
                label: HistoryStrings.archived,
                compact: compact,
                selected: archivedActive,
                onTap: onArchived,
              ),
            ],
          ),
        ),
        _AccountRow(onProfile: onProfile, onSettings: onSettings),
      ],
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({
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
    final p = context.palette;
    final color = selected ? p.accent : p.textSecondary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(HistorySizes.rowRadius),
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: compact
                  ? HistorySizes.iconButton
                  : HistorySizes.quickHeight,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(icon, size: AppIconSize.md, color: color),
                if (!compact) ...[
                  const SizedBox(height: AppSpacing.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: context.text.bodySmall.copyWith(
                        color: color,
                        fontSize: HistorySizes.quickLabelMax,
                      ),
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

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.onProfile, required this.onSettings});

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
        return ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: HistorySizes.profileHeight,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: ProfileStrings.openProfile,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () {
                      Haptics.tap();
                      onProfile();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPadding,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          UserAvatar(user: user, size: HistorySizes.avatar),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              user?.displayName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.body.copyWith(
                                fontVariations: const [
                                  FontVariation.weight(500),
                                ],
                              ),
                            ),
                          ),
                          AppIcon(
                            AppIcons.chevronRight,
                            size: AppIconSize.sm,
                            color: p.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: SidebarIconButton(
                  icon: AppIcons.settings,
                  label: HistoryStrings.openSettings,
                  onTap: onSettings,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
