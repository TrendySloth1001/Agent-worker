import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/profile_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/widgets/m3_kit_extras.dart';

/// "Taking a break?": the sign-out confirmation as a bottom sheet with an
/// illustration, a reassuring line and Stay / Sign out.
class LogOutSheet extends StatelessWidget {
  const LogOutSheet({super.key});

  /// Opens the sheet; true when the user chose to sign out.
  static Future<bool> show(BuildContext context) async {
    final ok = await showM3Sheet<bool>(
      context,
      builder: (_) => const LogOutSheet(),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pill = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size.fromHeight(AppSizes.buttonHeight),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(
        context.text.body.copyWith(
          fontVariations: const [FontVariation.weight(600)],
        ),
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Illustration(
                kind: IllustrationKind.homeCoffee,
                height: LogOutSheetSizes.illustration,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              ProfileCopy.logOutKicker,
              textAlign: TextAlign.center,
              style: context.text.caption.copyWith(color: p.accent),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              ProfileCopy.logOutTitle,
              textAlign: TextAlign.center,
              style: context.text.headline,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              ProfileCopy.logOutBody,
              textAlign: TextAlign.center,
              style: context.text.body.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: pill,
                    onPressed: () {
                      Haptics.tap();
                      Navigator.pop(context, false);
                    },
                    child: const Text(ProfileCopy.logOutStay),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    style: pill.copyWith(
                      backgroundColor: WidgetStatePropertyAll(p.error),
                      foregroundColor: WidgetStatePropertyAll(
                        p.isDark ? p.textPrimary : p.textInverse,
                      ),
                    ),
                    onPressed: () {
                      Haptics.tap();
                      Navigator.pop(context, true);
                    },
                    child: const Text(ProfileCopy.logOut),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

abstract final class LogOutSheetSizes {
  static const illustration = 150.0;
}
