import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/changelog.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/m3_kit_extras.dart';
import 'widgets/changelog_parts.dart';

/// About → What's new: the latest release as a hero with its highlights
/// grouped New / Improved / Fixed, then earlier releases on a collapsible
/// timeline.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key, this.releases = Changelog.releases});

  /// Newest first. Overridable for tests.
  final List<Release> releases;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ChangelogScreen()));

  @override
  Widget build(BuildContext context) {
    final latest = releases.first;
    final earlier = releases.skip(1).toList();
    return M3Page(
      title: ChangelogStrings.title,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
            vertical: AppSpacing.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ChangelogSizes.maxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ReleaseHero(release: latest),
                    for (final (kind, items) in groupByKind(latest))
                      ChangeSection(kind: kind, items: items),
                    if (earlier.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SettingsSizes.headerInset,
                          AppSpacing.xxl,
                          SettingsSizes.headerInset,
                          AppSpacing.md,
                        ),
                        child: Semantics(
                          header: true,
                          child: Text(
                            ChangelogStrings.earlier,
                            style: changelogMono(
                              context.palette.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      for (final (i, r) in earlier.indexed)
                        ReleaseTimelineItem(
                          key: ValueKey(r.version),
                          release: r,
                          isFirst: i == 0,
                          isLast: i == earlier.length - 1,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
