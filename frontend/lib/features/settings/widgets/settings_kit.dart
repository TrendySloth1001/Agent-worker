import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/system_chrome.dart';
import '../../../core/widgets/app_icon.dart';
import 'section_header.dart';

/// One searchable, deep-linkable row of a settings page.
class SettingItem {
  const SettingItem({
    required this.id,
    required this.title,
    required this.build,
    this.keywords = '',
  });

  /// Stable id used to deep-link from search.
  final String id;
  final String title;

  /// Lowercase synonyms the search also matches.
  final String keywords;

  /// The cell content. Wrapped in a [SettingsGroup] cell by the page.
  final WidgetBuilder build;
}

/// A titled run of [items] drawn as one segmented group.
class SettingsSection {
  const SettingsSection({this.title, required this.items, this.wrap});

  final String? title;
  final List<SettingItem> items;

  /// Wraps the whole group, e.g. in a `RadioGroup`.
  final Widget Function(BuildContext context, Widget group)? wrap;
}

/// A cell of a [SettingsGroup].
class GroupEntry {
  const GroupEntry(this.child, {this.anchor, this.highlight = false});

  final Widget child;

  /// Lets the page scroll this cell into view (search deep link).
  final GlobalKey? anchor;
  final bool highlight;
}

/// Android 16 style grouped settings: rounded cells, big radius at the group's
/// start and end, small radius between, a thin gap in between.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.entries});

  final List<GroupEntry> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    Radius r(bool outer) => Radius.circular(
      outer ? SettingsSizes.groupOuterRadius : SettingsSizes.groupInnerRadius,
    );
    final last = entries.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i <= last; i++) ...[
          if (i > 0) const SizedBox(height: SettingsSizes.groupGap),
          KeyedSubtree(
            key: entries[i].anchor,
            child: Material(
              animationDuration: reduce ? Duration.zero : AppDurations.normal,
              color: entries[i].highlight
                  ? scheme.surfaceContainerHighest
                  : scheme.surfaceContainer,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: r(i == 0),
                  bottom: r(i == last),
                ),
              ),
              child: CardChrome(child: entries[i].child),
            ),
          ),
        ],
      ],
    );
  }
}

/// Small accent label above a group, as Android does.
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SettingsSizes.headerInset,
        SettingsSizes.groupSpacing,
        SettingsSizes.headerInset,
        AppSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelLarge!.copyWith(color: context.palette.accent),
        ),
      ),
    );
  }
}

/// Leading icon in a tonal circle.
class SettingsIconCircle extends StatelessWidget {
  const SettingsIconCircle(this.icon, {super.key, this.color});

  final AppIconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: SettingsSizes.iconCircle,
      height: SettingsSizes.iconCircle,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
      ),
      child: Center(
        child: AppIcon(
          icon,
          size: SettingsSizes.iconGlyph,
          color: color ?? scheme.onSurface,
        ),
      ),
    );
  }
}

/// M3 list row: leading icon circle, title, supporting text.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.summary,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final AppIconData icon;
  final String title;
  final String? summary;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor, titleColor;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListTile(
      leading: SettingsIconCircle(icon, color: iconColor),
      title: Text(
        title,
        style: titleColor == null
            ? null
            : tt.titleMedium!.copyWith(color: titleColor),
      ),
      subtitle: summary == null || summary!.isEmpty ? null : Text(summary!),
      trailing: trailing,
      onTap: onTap == null
          ? null
          : () {
              Haptics.tap();
              onTap!();
            },
    );
  }
}

/// Tapping anywhere on the row toggles the M3 switch (with thumb icons).
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.summary,
  });

  final AppIconData icon;
  final String title;
  final String? summary;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SwitchListTile(
      secondary: SettingsIconCircle(icon),
      title: Text(title),
      subtitle: summary == null ? null : Text(summary!),
      value: value,
      thumbIcon: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Icon(Icons.check, color: p.accent)
            : Icon(Icons.close, color: p.background),
      ),
      onChanged: (v) {
        Haptics.tap();
        onChanged(v);
      },
    );
  }
}

/// One option of [showChoiceDialog].
class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, [this.help]);

  final T value;
  final String label;
  final String? help;
}

/// Android style chooser: a dialog with radio rows; the row picked is
/// returned straight away.
Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<ChoiceOption<T>> options,
  required T current,
}) {
  Haptics.tap();
  return showDialog<T>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      content: SingleChildScrollView(
        child: RadioGroup<T>(
          groupValue: current,
          onChanged: (v) {
            if (v == null) return;
            Haptics.tap();
            Navigator.pop(ctx, v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                RadioListTile<T>(
                  value: o.value,
                  title: Text(o.label),
                  subtitle: o.help == null ? null : Text(o.help!),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(SettingsStrings.cancel),
        ),
      ],
    ),
  );
}

/// Material 3 shared-axis (horizontal) route between settings pages. With
/// reduced motion the page simply appears.
Route<T> settingsRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, _, _) => page,
  transitionDuration: SettingsSizes.pageTransition,
  reverseTransitionDuration: SettingsSizes.pageTransition,
  transitionsBuilder: (context, animation, secondary, child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    const shift = SettingsSizes.pageShift;
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final exit = CurvedAnimation(parent: secondary, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: Listenable.merge([enter, exit]),
      child: child,
      builder: (context, child) {
        // Incoming: fades in during the second part, slides in from the end.
        final fadeIn = Interval(0.3, 1).transform(enter.value);
        final fadeOut = 1 - Interval(0, 0.6).transform(exit.value);
        final dx = (1 - enter.value) * shift - exit.value * shift;
        return Opacity(
          opacity: (fadeIn * fadeOut).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  },
);

/// Scaffold shared by the root and every sub-page: large collapsing app bar,
/// edge-to-edge content and the Settings Material 3 theme.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.onRefresh,
    this.controller,
    this.showBack = true,
  });

  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.settings(Theme.of(context)),
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final p = context.palette;
    Widget scroll = CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar.large(
          automaticallyImplyLeading: false,
          leading: showBack
              ? IconButton(
                  icon: const AppIcon(AppIcons.back, size: AppIconSize.lg),
                  tooltip: AppStrings.back,
                  onPressed: () {
                    Haptics.tap();
                    Navigator.maybePop(context);
                  },
                )
              : null,
          title: Text(title),
        ),
        SliverSafeArea(
          top: false,
          bottom: false,
          sliver: SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
            ),
            sliver: SliverList.list(children: children),
          ),
        ),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(
        color: p.accent,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        onRefresh: onRefresh!,
        child: scroll,
      );
    }
    return AnnotatedRegion(
      value: systemOverlayFor(context),
      child: Scaffold(backgroundColor: p.background, body: scroll),
    );
  }
}
