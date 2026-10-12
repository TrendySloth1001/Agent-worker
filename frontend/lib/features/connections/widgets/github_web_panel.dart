import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/connections.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
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
  Widget build(BuildContext context) =>
      M3Themed(child: Builder(builder: _panel));

  Widget _panel(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final muted = tt.bodySmall!.copyWith(color: scheme.onSurfaceVariant);
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
                  color: p.accent,
                ),
              )
            else
              const PulseDot(),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(busyLabel ?? ConnectCopy.webWaiting, style: muted),
            ),
          ],
        ),
        if (!busy) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            openedInApp ? GithubWebStrings.inApp : GithubWebStrings.inBrowser,
            style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            if (onOpenAgain != null && !busy) ...[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.textInverse,
                  ),
                  onPressed: () {
                    Haptics.tap();
                    onOpenAgain!();
                  },
                  icon: const AppIcon(ConnectIcons.open, size: AppIconSize.sm),
                  label: const Text(ConnectCopy.openAgain),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ] else
              const Spacer(),
            TextButton(
              onPressed: () {
                Haptics.tap();
                onCancel();
              },
              child: const Text(ConnectCopy.cancel),
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
        ConnectCopy.useCode,
        style: Theme.of(
          context,
        ).textTheme.labelLarge!.copyWith(color: p.textSecondary),
      ),
    );
  }
}
