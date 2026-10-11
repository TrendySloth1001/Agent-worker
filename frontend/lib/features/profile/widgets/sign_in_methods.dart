import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../data/sso_api.dart';
import '../../settings/widgets/section_header.dart';

/// Profile → SIGN-IN METHODS: email/password, linked GitHub and Google
/// accounts, with LINK / UNLINK / SET PASSWORD. The last way in cannot be
/// unlinked.
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
    final canUnlink = methods.count > 1;
    final github = methods.of(SsoProviderIds.github);
    final google = methods.of(SsoProviderIds.google);

    Widget unlinkOrOnly(LinkedIdentity i) => canUnlink
        ? _RowAction(
            label: SsoStrings.unlink,
            color: p.error,
            busy: busy == i.id,
            onTap: () => onUnlink(i),
          )
        : const MetaChip(SsoStrings.onlyMethod);

    final githubMark = BrandMark.github(
      size: SsoSizes.rowMark,
      color: p.textSecondary,
    );
    const googleMark = BrandMark.google(size: SsoSizes.rowMark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MethodRow(
          leading: AppIcon(
            SsoIcons.password,
            size: AppIconSize.md,
            color: p.textSecondary,
          ),
          title: SsoStrings.emailPassword,
          subtitle: email,
          trailing: methods.hasPassword
              ? const MetaChip(SsoStrings.passwordOn, emphasis: true)
              : _RowAction(
                  label: SsoStrings.setPassword,
                  color: p.textPrimary,
                  onTap: onSetPassword,
                ),
        ),
        for (final i in github)
          _MethodRow(
            leading: githubMark,
            title: SsoStrings.githubLabel,
            subtitle: i.login != null
                ? SsoStrings.account(i.login!)
                : (i.email ?? ''),
            trailing: unlinkOrOnly(i),
          ),
        if (github.isEmpty && (providers?.github ?? false))
          _MethodRow(
            leading: githubMark,
            title: SsoStrings.githubLabel,
            trailing: _RowAction(
              label: SsoStrings.link,
              color: p.textPrimary,
              busy: busy == SsoProviderIds.github,
              onTap: onLinkGithub,
            ),
          ),
        for (final i in google)
          _MethodRow(
            leading: googleMark,
            title: SsoStrings.googleLabel,
            subtitle: i.email ?? '',
            trailing: unlinkOrOnly(i),
          ),
        if (google.isEmpty && (providers?.google ?? false))
          _MethodRow(
            leading: googleMark,
            title: SsoStrings.googleLabel,
            trailing: _RowAction(
              label: SsoStrings.link,
              color: p.textPrimary,
              busy: busy == SsoProviderIds.google,
              onTap: onLinkGoogle,
            ),
          ),
      ],
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.leading,
    required this.title,
    required this.trailing,
    this.subtitle,
  });

  final Widget leading, trailing;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: FlatCard(
        child: Row(
          children: [
            SizedBox.square(
              dimension: AppIconSize.md,
              child: Center(child: leading),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.bodySmall.copyWith(
                      color: p.textPrimary,
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.caption,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing,
          ],
        ),
      ),
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
      onPressed: () {
        Haptics.tap();
        onTap();
      },
      child: Text(label, style: context.text.caption.copyWith(color: color)),
    );
  }
}
