import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/profile_copy.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../data/sso_api.dart';
import '../../settings/widgets/settings_kit.dart';

/// Profile sign-in methods as one grouped container: email/password and the
/// GitHub and Google accounts, each showing whether it is linked, with LINK /
/// UNLINK / SET PASSWORD. The last way in cannot be unlinked.
class SignInMethodsList extends StatelessWidget {
  const SignInMethodsList({
    super.key,
    required this.email,
    required this.methods,
    required this.providers,
    required this.busy,
    required this.onSetPassword,
    required this.onLinkGithub,
    required this.onLinkGoogle,
    required this.onUnlink,
  });

  final String email;
  final SignInMethods methods;

  /// Which providers the server offers; null hides the LINK rows.
  final SsoProviders? providers;

  /// Provider id (or identity id) with an action running.
  final String? busy;
  final VoidCallback onSetPassword, onLinkGithub, onLinkGoogle;
  final ValueChanged<LinkedIdentity> onUnlink;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final canUnlink = methods.count > 1;
    final github = methods.of(SsoProviderIds.github);
    final google = methods.of(SsoProviderIds.google);

    Widget unlinkOrOnly(LinkedIdentity i) => canUnlink
        ? _RowAction(
            label: SsoStrings.unlink,
            color: scheme.error,
            busy: busy == i.id,
            onTap: () => onUnlink(i),
          )
        : const SettingsMetaLabel(SsoStrings.onlyMethod);

    Widget mark(Widget w) => SizedBox.square(
      dimension: SettingsSizes.iconCircle,
      child: Center(child: w),
    );
    final githubMark = mark(
      BrandMark.github(size: SsoSizes.rowMark, color: scheme.onSurface),
    );
    final googleMark = mark(const BrandMark.google(size: SsoSizes.rowMark));

    return SettingsGroup(
      entries: [
        GroupEntry(
          SettingsTile(
            icon: SsoIcons.password,
            title: SsoStrings.emailPassword,
            summary: email,
            trailing: methods.hasPassword
                ? const SettingsMetaLabel(ProfileCopy.linked, accent: true)
                : _RowAction(
                    label: SsoStrings.setPassword,
                    color: p.textPrimary,
                    onTap: onSetPassword,
                  ),
          ),
        ),
        for (final i in github)
          GroupEntry(
            SettingsTile(
              icon: SsoIcons.methods,
              leading: githubMark,
              title: SsoStrings.githubLabel,
              summary: i.login != null
                  ? SsoStrings.account(i.login!)
                  : (i.email ?? ProfileCopy.linked),
              trailing: unlinkOrOnly(i),
            ),
          ),
        if (github.isEmpty && (providers?.github ?? false))
          GroupEntry(
            SettingsTile(
              icon: SsoIcons.methods,
              leading: githubMark,
              title: SsoStrings.githubLabel,
              summary: ProfileCopy.notLinked,
              trailing: _RowAction(
                label: SsoStrings.link,
                color: p.textPrimary,
                busy: busy == SsoProviderIds.github,
                onTap: onLinkGithub,
              ),
            ),
          ),
        for (final i in google)
          GroupEntry(
            SettingsTile(
              icon: SsoIcons.methods,
              leading: googleMark,
              title: SsoStrings.googleLabel,
              summary: i.email ?? ProfileCopy.linked,
              trailing: unlinkOrOnly(i),
            ),
          ),
        if (google.isEmpty && (providers?.google ?? false))
          GroupEntry(
            SettingsTile(
              icon: SsoIcons.methods,
              leading: googleMark,
              title: SsoStrings.googleLabel,
              summary: ProfileCopy.notLinked,
              trailing: _RowAction(
                label: SsoStrings.link,
                color: p.textPrimary,
                busy: busy == SsoProviderIds.google,
                onTap: onLinkGoogle,
              ),
            ),
          ),
      ],
    );
  }
}

/// Small text action on a row; a spinner while [busy].
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: SizedBox.square(
          dimension: AppIconSize.sm,
          child: CircularProgressIndicator(
            strokeWidth: AppBorder.thick,
            color: color,
          ),
        ),
      );
    }
    return TextButton(
      style: TextButton.styleFrom(foregroundColor: color),
      onPressed: () {
        Haptics.tap();
        onTap();
      },
      child: Text(label),
    );
  }
}
