import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/changelog.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/dot_grid_background.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../settings/widgets/settings_kit.dart';

/// Building blocks of the "What's new" screen and the one-time update sheet.

/// Space Mono metadata (kickers, dates, counts, kind pills).
TextStyle changelogMono(Color color) =>
    AppTextStyles.label.copyWith(color: color);

/// The line-art scene on the latest release's hero.
const changelogHeroArt = IllustrationKind.homeThink;

/// Changes of [r] grouped New → Improved → Fixed, empty kinds left out.
List<(ChangeKind, List<Change>)> groupByKind(Release r) => [
  for (final k in ChangeKind.values)
    if (r.items.any((c) => c.kind == k))
      (k, [for (final c in r.items) if (c.kind == k) c]),
];

/// The tiny "NEW / IMPROVED / FIXED" pill. New is red, Improved is ink,
/// Fixed is an outline, so the kinds differ by more than hue.
class ChangeKindTag extends StatelessWidget {
  const ChangeKindTag(this.kind, {super.key, this.count});

  final ChangeKind kind;

  /// Shown before the label ("4 NEW").
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color fg, Color? bg, Color? border) = switch (kind) {
      ChangeKind.added => (
        p.accent,
        p.accent.withValues(alpha: M3Sizes.tagAlpha),
        null,
      ),
      ChangeKind.improved => (
        p.textPrimary,
        p.textPrimary.withValues(alpha: M3Sizes.tagAlpha),
        null,
      ),
      ChangeKind.fixed => (p.textSecondary, null, p.borderStrong),
    };
    final label = ChangelogStrings.kind(kind);
    return Container(
      constraints: const BoxConstraints(minHeight: M3Sizes.chipHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: border == null
            ? null
            : Border.all(color: border, width: AppBorder.thin),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          count == null ? label : '$count $label',
          style: changelogMono(fg),
        ),
      ),
    );
  }
}

/// Big version, date, headline and an illustration for the newest release.
class ReleaseHero extends StatelessWidget {
  const ReleaseHero({super.key, required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      container: true,
      child: Material(
        color: scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(ChangelogSizes.heroRadius),
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: DotGridBackground()),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: LayoutBuilder(
                builder: (context, box) {
                  final showArt =
                      box.maxWidth / scale >= ChangelogSizes.heroArtMinWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ChangelogStrings.heroKicker(release.date),
                        style: changelogMono(p.accent),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                header: true,
                                child: Text(
                                  release.version,
                                  style: context.text.display.copyWith(
                                    fontSize: ChangelogSizes.heroVersion,
                                    letterSpacing: ChangelogSizes.heroVersionTracking,
                                    color: p.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (showArt)
                            Illustration(
                              kind: changelogHeroArt,
                              height: ChangelogSizes.heroArt,
                              paper: scheme.surfaceContainer,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        release.headline,
                        style: context.text.headline.copyWith(
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final (k, items) in groupByKind(release))
                            ChangeKindTag(k, count: items.length),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo or glyph of a change in a tonal circle.
class ChangeIcon extends StatelessWidget {
  const ChangeIcon(
    this.change, {
    super.key,
    this.box = ChangelogSizes.featureIconBox,
    this.size = ChangelogSizes.featureIcon,
  });

  final Change change;
  final double box, size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
      ),
      alignment: Alignment.center,
      child: AppIcon(
        change.icon,
        size: size,
        color: change.kind == ChangeKind.added ? p.accent : p.textPrimary,
      ),
    );
  }
}

/// One highlight: icon, bold title and one line of detail.
class ChangeRow extends StatelessWidget {
  const ChangeRow(
    this.change, {
    super.key,
    this.compact = false,
    this.showKind = false,
  });

  final Change change;

  /// Smaller icon and type, for the timeline and the sheet.
  final bool compact;

  /// Adds the kind pill under the text (lists that mix kinds).
  final bool showKind;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.md : AppSpacing.lg,
          vertical: compact ? AppSpacing.md : AppSpacing.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            compact
                ? ChangeIcon(
                    change,
                    box: ChangelogSizes.timelineIconBox,
                    size: ChangelogSizes.timelineIcon,
                  )
                : ChangeIcon(change),
            SizedBox(width: compact ? AppSpacing.md : AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    change.title,
                    style:
                        (compact ? context.text.body : context.text.title)
                            .copyWith(
                              color: p.textPrimary,
                              fontVariations: const [
                                FontVariation.weight(700),
                              ],
                            ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    change.detail,
                    style: context.text.bodySmall.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                  if (showKind) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ChangeKindTag(change.kind),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A kind header ("NEW" pill) and its highlights as a grouped card list.
class ChangeSection extends StatelessWidget {
  const ChangeSection({super.key, required this.kind, required this.items});

  final ChangeKind kind;
  final List<Change> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          SettingsSizes.headerInset,
          AppSpacing.xl,
          SettingsSizes.headerInset,
          AppSpacing.md,
        ),
        child: Semantics(
          header: true,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChangeKindTag(kind),
          ),
        ),
      ),
      SettingsGroup(
        entries: [for (final c in items) GroupEntry(ChangeRow(c))],
      ),
    ],
  );
}

/// One earlier release on the timeline: a dot on the rail, version, date,
/// headline and a "6 changes" toggle that expands the list.
class ReleaseTimelineItem extends StatefulWidget {
  const ReleaseTimelineItem({
    super.key,
    required this.release,
    this.initiallyExpanded = false,
    this.isFirst = false,
    this.isLast = false,
  });

  final Release release;

  /// The rail starts at the first dot.
  final bool isFirst;
  final bool initiallyExpanded;

  /// The rail stops at the last dot.
  final bool isLast;

  @override
  State<ReleaseTimelineItem> createState() => _ReleaseTimelineItemState();
}

class _ReleaseTimelineItemState extends State<ReleaseTimelineItem> {
  late bool _open = widget.initiallyExpanded;

  void _toggle() {
    Haptics.tap();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = widget.release;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce ? Duration.zero : ChangelogSizes.expandDuration;
    final dot = _open ? ChangelogSizes.railDotOpen : ChangelogSizes.railDot;
    return Stack(
      children: [
        // The rail: a hairline through every dot.
        Positioned(
          left: (ChangelogSizes.railWidth - ChangelogSizes.railLine) / 2,
          top: widget.isFirst ? ChangelogSizes.railDotTop : 0,
          bottom: widget.isLast ? null : 0,
          height: widget.isLast
              ? (widget.isFirst ? 0 : ChangelogSizes.railDotTop)
              : null,
          child: Container(width: ChangelogSizes.railLine, color: p.border),
        ),
        Positioned(
          left: (ChangelogSizes.railWidth - dot) / 2,
          top: ChangelogSizes.railDotTop - dot / 2,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _open ? p.accent : p.background,
              border: Border.all(
                color: _open ? p.accent : p.borderStrong,
                width: AppBorder.thick,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: ChangelogSizes.railWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: _open,
                onTapHint: _open
                    ? ChangelogStrings.collapse
                    : ChangelogStrings.expand,
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.minTap,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.sm,
                        AppSpacing.xs,
                        AppSpacing.md,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _header(context)),
                          AnimatedRotation(
                            turns: _open ? ChangelogSizes.chevronTurns : 0,
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              child: AppIcon(
                                ChangelogIcons.chevron,
                                size: AppIconSize.lg,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _open
                      ? Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.sm,
                            bottom: AppSpacing.lg,
                          ),
                          child: SettingsGroup(
                            entries: [
                              for (final c in r.items)
                                GroupEntry(
                                  ChangeRow(c, compact: true, showKind: true),
                                ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final p = context.palette;
    final r = widget.release;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          children: [
            Text(
              r.version,
              style: context.text.metric.copyWith(
                fontSize: ChangelogSizes.timelineVersion,
                color: p.textPrimary,
                fontVariations: const [FontVariation.weight(700)],
              ),
            ),
            Text(
              r.date.toUpperCase(),
              style: changelogMono(p.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          r.headline,
          style: context.text.body.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          ChangelogStrings.count(r.items.length).toUpperCase(),
          style: changelogMono(_open ? p.accent : p.textSecondary),
        ),
      ],
    );
  }
}
