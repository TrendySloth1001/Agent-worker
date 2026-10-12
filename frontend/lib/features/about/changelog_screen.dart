import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/changelog.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../settings/widgets/settings_kit.dart';

/// About → What's new: every release, newest first.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ChangelogScreen()));

  @override
  Widget build(BuildContext context) {
    return M3Page(
      title: ChangelogStrings.title,
      slivers: [
        M3Body(
          children: [
            for (final (i, r) in Changelog.releases.indexed) ...[
              Row(
                children: [
                  Expanded(
                    child: SettingsGroupHeader(
                      ChangelogStrings.heading(r.version, r.date),
                    ),
                  ),
                  if (i == 0)
                    const M3Tag(ChangelogStrings.latest, accent: true),
                ],
              ),
              M3Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in r.changes)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xxs,
                              ),
                              child: AppIcon(
                                ChangelogIcons.bullet,
                                size: AppIconSize.sm,
                                color: i == 0
                                    ? context.palette.accent
                                    : context.palette.textTertiary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                c,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ],
    );
  }
}
