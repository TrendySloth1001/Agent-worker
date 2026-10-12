import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/onboarding.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/illustration.dart';
import '../../settings/widgets/settings_kit.dart';

/// One tour page: illustration, step + kicker, headline, body and [children],
/// centered and scrolling when the screen is short or the text large.
class TourPage extends StatelessWidget {
  const TourPage({
    super.key,
    required this.index,
    required this.art,
    required this.kicker,
    required this.title,
    required this.body,
    this.children = const [],
    this.hero = false,
  });

  /// The welcome page: a bigger illustration.
  final bool hero;

  final int index;
  final IllustrationKind art;
  final String kicker, title, body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Large text needs the room: measure the height in "1x text" units.
    final height =
        MediaQuery.sizeOf(context).height /
        MediaQuery.textScalerOf(context).scale(1);
    final compact = height < OnboardingSizes.artCompactBelow;
    final artHeight = switch ((hero, compact)) {
      (true, false) => OnboardingSizes.heroArt,
      (true, true) => OnboardingSizes.heroArtCompact,
      (false, false) => OnboardingSizes.art,
      (false, true) => OnboardingSizes.artCompact,
    };
    final parts = <Widget>[
      Center(
        child: Illustration(kind: art, height: artHeight),
      ),
      const SizedBox(height: AppSpacing.xl),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: OnboardingStrings.step(index, OnboardingSizes.pages),
              style: TextStyle(color: p.accent),
            ),
            const TextSpan(text: '  '),
            TextSpan(text: kicker),
          ],
        ),
        style: context.text.caption.copyWith(color: p.textSecondary),
      ),
      const SizedBox(height: AppSpacing.sm),
      Semantics(
        header: true,
        child: Text(
          title,
          style: context.text.headline.copyWith(
            fontSize: OnboardingSizes.headline,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(body, style: context.text.body.copyWith(color: p.textSecondary)),
      if (children.isNotEmpty) const SizedBox(height: AppSpacing.xl),
      ...children,
    ];
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: OnboardingSizes.maxWidth,
              minHeight: math.max(0, box.maxHeight - AppSpacing.lg * 2),
            ),
            child: _Stagger(children: parts),
          ),
        ),
      ),
    );
  }
}

/// Page content rises in, one part after another (instant with reduced
/// motion).
class _Stagger extends StatefulWidget {
  const _Stagger({required this.children});

  final List<Widget> children;

  @override
  State<_Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<_Stagger>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: OnboardingDurations.entrance,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.children.length;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (var i = 0; i < n; i++) _rise(i, n, widget.children[i])],
    );
  }

  Widget _rise(int i, int n, Widget child) {
    if (child is SizedBox) return child;
    final start = math.min(i * OnboardingSizes.stagger / 2, 0.5);
    final t = CurvedAnimation(
      parent: _c,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - t.value) * OnboardingSizes.rise),
          child: child,
        ),
      ),
    );
  }
}

/// Feature rows in one rounded group: icon circle, title, one line.
class TourPoints extends StatelessWidget {
  const TourPoints(this.points, {super.key});

  final List<TourPoint> points;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      entries: [
        for (final point in points)
          GroupEntry(
            ListTile(
              leading: SettingsIconCircle(point.icon),
              title: Text(point.title),
              subtitle: Text(point.detail),
            ),
          ),
      ],
    );
  }
}

/// Nothing-style glyph dots: past pages ink, the current one a red pill,
/// the rest dim. Tapping a dot jumps to that page.
class TourDots extends StatelessWidget {
  const TourDots({
    super.key,
    required this.page,
    required this.count,
    required this.onTap,
  });

  final int page, count;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : OnboardingDurations.dot;
    return Semantics(
      label: OnboardingStrings.pageLabel(page, count),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: OnboardingSizes.dotGap / 2,
                  vertical: AppSpacing.sm,
                ),
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: i == page
                      ? OnboardingSizes.dotActive
                      : OnboardingSizes.dot,
                  height: OnboardingSizes.dot,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    color: i == page
                        ? p.accent
                        : i < page
                        ? p.textPrimary
                        : p.borderStrong,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Selectable reply-style chip.
class TourChoice extends StatelessWidget {
  const TourChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: p.textPrimary,
      labelStyle: TextStyle(color: selected ? p.textInverse : p.textPrimary),
      shape: StadiumBorder(
        side: BorderSide(color: selected ? p.textPrimary : p.borderStrong),
      ),
      onSelected: (_) {
        Haptics.tap();
        onTap();
      },
    );
  }
}
