import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/changelog.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../settings/widgets/settings_kit.dart';
import 'changelog_screen.dart';
import 'widgets/changelog_parts.dart';

/// The one-time "What's new in X" sheet after the app updates.
///
/// Call [WhatsNew.maybeShow] once the home screen is up. The first launch
/// after install only records the version (new users get the tour instead);
/// later launches show the sheet once per new version that has an entry in
/// [Changelog].
abstract final class WhatsNew {
  /// The release to announce for [current] given the [lastSeen] version,
  /// or null: nothing seen yet (fresh install), same version, or no entry.
  static Release? due({required String? lastSeen, required String current}) {
    if (lastSeen == null || lastSeen == current) return null;
    return Changelog.find(current);
  }

  /// Shows the sheet if the app was updated since the last launch.
  /// Returns whether it was shown. [version] overrides the installed
  /// version (tests).
  static Future<bool> maybeShow(BuildContext context, {String? version}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = version ?? (await PackageInfo.fromPlatform()).version;
    final lastSeen = prefs.getString(ChangelogPrefs.lastSeenVersion);
    final release = due(lastSeen: lastSeen, current: current);
    if (lastSeen != current) {
      await prefs.setString(ChangelogPrefs.lastSeenVersion, current);
    }
    if (release == null || !context.mounted) return false;
    await show(context, release);
    return true;
  }

  /// Opens the sheet for [release]; "See all" opens the full screen.
  static Future<void> show(BuildContext context, Release release) async {
    final seeAll = await showM3Sheet<bool>(
      context,
      builder: (_) => WhatsNewSheet(release: release),
    );
    if (seeAll == true && context.mounted) {
      await ChangelogScreen.open(context);
    }
  }
}

/// Sheet body: kicker, headline, the top highlights and two buttons.
class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key, required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shown = release.items.take(ChangelogSizes.sheetItems).toList();
    final more = release.items.length - shown.length;
    final buttonText = context.text.body.copyWith(
      fontVariations: const [FontVariation.weight(600)],
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
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
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SettingsSizes.headerInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ChangelogStrings.sheetKicker(release.version),
                    style: changelogMono(p.accent),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    header: true,
                    child: Text(
                      release.headline,
                      style: context.text.headline.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsGroup(
              entries: [
                for (final c in shown)
                  GroupEntry(ChangeRow(c, compact: true)),
              ],
            ),
            if (more > 0) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                ChangelogStrings.sheetMore(more).toUpperCase(),
                textAlign: TextAlign.center,
                style: changelogMono(p.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        AppSizes.buttonHeight,
                      ),
                      shape: const StadiumBorder(),
                      textStyle: buttonText,
                    ),
                    onPressed: () {
                      Haptics.tap();
                      Navigator.of(context).pop(true);
                    },
                    child: const Text(ChangelogStrings.seeAll),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        AppSizes.buttonHeight,
                      ),
                      shape: const StadiumBorder(),
                      textStyle: buttonText,
                    ),
                    onPressed: () {
                      Haptics.tap();
                      Navigator.of(context).pop(false);
                    },
                    child: const Text(ChangelogStrings.gotIt),
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
