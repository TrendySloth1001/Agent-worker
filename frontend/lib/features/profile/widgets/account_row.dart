import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/auth_constants.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/auth_controller.dart';

/// Drawer header row: avatar, name and email. Opens the profile.
class AccountRow extends StatelessWidget {
  const AccountRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final auth = AuthController.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final user = auth.user;
        return Semantics(
          button: true,
          label: ProfileStrings.openProfile,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  UserAvatar(user: user, size: AuthSizes.avatarDrawer),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.body.copyWith(
                            fontVariations: const [FontVariation.weight(600)],
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          user?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.caption,
                        ),
                      ],
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
        );
      },
    );
  }
}
