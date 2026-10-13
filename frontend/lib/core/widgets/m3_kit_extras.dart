import 'mascot.dart';
import '../constants/mascot.dart';
import 'package:flutter/material.dart';

import '../../features/settings/widgets/section_header.dart';
import '../../features/settings/widgets/settings_kit.dart';
import '../constants/app_icons.dart';
import '../constants/app_sizes.dart';
import '../constants/app_strings.dart';
import '../constants/settings_copy.dart';
import '../haptics.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../theme/system_chrome.dart';
import 'app_icon.dart';
import 'dot_meter.dart';

/// Extra Material 3 building blocks on top of the settings kit, shared by the
/// Memory, Storage, Knowledge, Telemetry, About and sheet screens.
abstract final class M3Sizes {
  static const chipHeight = 24.0;
  static const emptyIcon = 56.0;
  static const heroPadding = 20.0;
  static const heroRadius = 28.0;
  static const sheetRadius = 28.0;
  static const fabBottomClearance = 88.0;
  static const dotBarHeight = 14.0;
  static const tagAlpha = 0.14;
}

/// Wraps [child] in the scoped Material 3 theme.
class M3Themed extends StatelessWidget {
  const M3Themed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: AppTheme.settings(Theme.of(context)), child: child);
}

/// Large collapsing app bar page. Like [SettingsScaffold] but with actions,
/// a floating action button, a contextual (selection) mode and free slivers.
class M3Page extends StatelessWidget {
  const M3Page({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.onRefresh,
    this.floatingActionButton,
    this.contextual = false,
    this.leading,
    this.titleWidget,
    this.controller,
    this.bottom,
  });

  final String title;

  /// Replaces [title] (e.g. a selection count).
  final Widget? titleWidget;
  final List<Widget> slivers;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final Widget? floatingActionButton;

  /// A compact tonal top bar (selection mode) instead of the large one.
  final bool contextual;
  final Widget? leading;
  final ScrollController? controller;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) =>
      M3Themed(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final back =
        leading ??
        IconButton(
          icon: const AppIcon(AppIcons.back, size: AppIconSize.lg),
          tooltip: AppStrings.back,
          onPressed: () {
            Haptics.tap();
            Navigator.maybePop(context);
          },
        );
    final titleW = titleWidget ?? Text(title);
    Widget scroll = CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (contextual)
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            leading: back,
            title: titleW,
            actions: actions,
            backgroundColor: scheme.surfaceContainerHigh,
            bottom: bottom,
          )
        else
          SliverAppBar.large(
            automaticallyImplyLeading: false,
            leading: back,
            title: titleW,
            actions: actions,
            bottom: bottom,
          ),
        ...slivers,
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                MediaQuery.paddingOf(context).bottom +
                (floatingActionButton == null
                    ? AppSpacing.xxl
                    : M3Sizes.fabBottomClearance),
          ),
        ),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(
        color: p.accent,
        backgroundColor: scheme.surfaceContainerHigh,
        onRefresh: onRefresh!,
        child: scroll,
      );
    }
    return AnnotatedRegion(
      value: systemOverlayFor(context),
      child: Scaffold(
        backgroundColor: p.background,
        floatingActionButton: floatingActionButton,
        body: scroll,
      ),
    );
  }
}

/// A padded sliver that holds box children (the usual page body).
class M3Body extends StatelessWidget {
  const M3Body({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenPadding,
      vertical: AppSpacing.sm,
    ),
    sliver: SliverList.list(children: children),
  );
}

/// A header plus a grouped list of plain widgets.
class M3Group extends StatelessWidget {
  const M3Group({super.key, this.title, required this.children, this.footer});

  final String? title;
  final List<Widget> children;

  /// Supporting text below the group.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) SettingsGroupHeader(title!),
        SettingsGroup(entries: [for (final c in children) GroupEntry(c)]),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SettingsSizes.headerInset,
              AppSpacing.sm,
              SettingsSizes.headerInset,
              0,
            ),
            child: Text(
              footer!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// A rounded tonal container (a single cell) for custom content.
class M3Card extends StatelessWidget {
  const M3Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(M3Sizes.heroPadding),
    this.high = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool high;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: high ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(M3Sizes.heroRadius)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Tiny Space Mono tonal chip, e.g. a memory kind.
class M3Tag extends StatelessWidget {
  const M3Tag(this.label, {super.key, this.accent = false, this.mono = true});

  final String label;
  final bool accent;

  /// Space Mono for tiny metadata (ids, kinds). Off for readable words.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: M3Sizes.chipHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        color: accent
            ? p.accent.withValues(alpha: M3Sizes.tagAlpha)
            : scheme.surfaceContainerHighest,
      ),
      child: Center(
        // Shrink-wrap both axes: a trailing slot hands us the row's full
        // height, which would otherwise stretch the pill into a tall capsule.
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style:
              (mono
                      ? AppTextStyles.caption
                      : Theme.of(context).textTheme.labelMedium!)
                  .copyWith(color: accent ? p.accent : scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Dot-matrix usage bar: lit dots in the accent over dim dots.
class M3DotBar extends StatelessWidget {
  const M3DotBar({super.key, required this.fraction, this.color});

  final double fraction;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: M3Sizes.dotBarHeight,
    child: DotMeter(fraction: fraction, litColor: color),
  );
}

/// Centered empty state: tonal icon, title, hint and an optional action.
class M3Empty extends StatelessWidget {
  const M3Empty({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
    this.mascot,
  });

  final AppIconData icon;

  /// Shows sparky in this state instead of the icon.
  final MascotState? mascot;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: [
          if (mascot != null)
            Mascot(state: mascot!, size: MascotSizes.large)
          else
            Container(
              width: M3Sizes.emptyIcon,
              height: M3Sizes.emptyIcon,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest,
              ),
              child: Center(
                child: AppIcon(
                  icon,
                  size: AppIconSize.lg,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Text(title, textAlign: TextAlign.center, style: tt.titleMedium),
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Opens a Material 3 modal bottom sheet (drag handle, large top radius,
/// scoped theme). [builder] runs under the M3 theme.
Future<T?> showM3Sheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  bool useRootNavigator = false,
}) {
  final base = AppTheme.settings(Theme.of(context));
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useRootNavigator: useRootNavigator,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: base.colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(M3Sizes.sheetRadius),
      ),
    ),
    builder: (ctx) => Theme(
      data: base,
      child: Builder(builder: builder),
    ),
  );
}

/// Sheet title line.
class M3SheetTitle extends StatelessWidget {
  const M3SheetTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.titleLarge),
          if (subtitle != null)
            Text(
              subtitle!,
              style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// One lazily built cell of a grouped list: big radius at the group's ends,
/// small between, as [SettingsGroup] draws it. Use inside slivers that build
/// rows on demand.
class M3Cell extends StatelessWidget {
  const M3Cell({
    super.key,
    required this.index,
    required this.count,
    required this.child,
    this.selected = false,
  });

  final int index, count;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Radius r(bool outer) => Radius.circular(
      outer ? SettingsSizes.groupOuterRadius : SettingsSizes.groupInnerRadius,
    );
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : SettingsSizes.groupGap),
      child: Material(
        color: selected
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: r(index == 0),
            bottom: r(index == count - 1),
          ),
        ),
        child: CardChrome(child: child),
      ),
    );
  }
}

/// Body of a typical action sheet: optional title and a grouped run of rows.
class M3ActionSheet extends StatelessWidget {
  const M3ActionSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.rows,
  });

  final String? title;
  final String? subtitle;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) M3SheetTitle(title!, subtitle: subtitle),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: SettingsGroup(
              entries: [for (final r in rows) GroupEntry(r)],
            ),
          ),
        ],
      ),
    ),
  );
}

/// "FORK FROM HERE" -> "Fork from here". Strings that already carry
/// lowercase letters are returned unchanged.
String sentenceCase(String s) {
  if (s.isEmpty || s != s.toUpperCase()) return s;
  final lower = s.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}
