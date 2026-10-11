import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/connections.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../chat/widgets/rich/playful_common.dart';
import 'device_code_panel.dart';

/// One-tap GitHub waiting state: "Waiting for GitHub…", where it opened
/// (GitHub app or browser), OPEN AGAIN + CANCEL and a USE A CODE INSTEAD link
/// that falls back to the device code. Shared by the connect card, Settings,
/// the sign-in sheet and Profile → LINK.
class GithubWebPanel extends StatelessWidget {
  const GithubWebPanel({
    super.key,
    required this.title,
    required this.openedInApp,
    required this.onCancel,
    this.onOpenAgain,
    this.onUseCode,
    this.busyLabel,
  });

  final String title;
  final bool openedInApp;

  /// Set while starting or finishing (shows a spinner instead of the buttons).
  final String? busyLabel;
  final VoidCallback onCancel;
  final VoidCallback? onOpenAgain, onUseCode;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final busy = busyLabel != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GithubHeading(title),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            if (busy)
              SizedBox.square(
                dimension: AppIconSize.sm,
                child: CircularProgressIndicator(
                  strokeWidth: AppBorder.thick,
                  color: p.textPrimary,
                ),
              )
            else
              const PulseDot(),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                busyLabel ?? GithubWebStrings.waiting,
                style: t.caption,
              ),
            ),
          ],
        ),
        if (!busy) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            openedInApp ? GithubWebStrings.inApp : GithubWebStrings.inBrowser,
            style: t.bodySmall.copyWith(color: p.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            if (onOpenAgain != null && !busy) ...[
              Expanded(
                child: PlayfulButton(
                  label: GithubWebStrings.openAgain,
                  icon: ConnectIcons.open,
                  primary: true,
                  expand: true,
                  onTap: () {
                    Haptics.tap();
                    onOpenAgain!();
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ] else
              const Spacer(),
            PlayfulButton(
              label: GithubWebStrings.cancel,
              onTap: () {
                Haptics.tap();
                onCancel();
              },
            ),
          ],
        ),
        if (onUseCode != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(child: UseCodeLink(onTap: onUseCode!)),
        ],
      ],
    );
  }
}

/// Small text link: USE A CODE INSTEAD.
class UseCodeLink extends StatelessWidget {
  const UseCodeLink({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextButton.icon(
      onPressed: () {
        Haptics.tap();
        onTap();
      },
      icon: AppIcon(
        ConnectIcons.copy,
        size: AppIconSize.xs,
        color: p.textSecondary,
      ),
      label: Text(
        GithubWebStrings.useCode,
        style: context.text.button.copyWith(color: p.textSecondary),
      ),
    );
  }
}
