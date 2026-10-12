import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_fonts.dart';
import '../constants/app_sizes.dart';
import 'app_palette.dart';
import 'app_text_styles.dart';

abstract final class AppTheme {
  static ThemeData get dark => _build(AppPalette.dark);
  static ThemeData get light => _build(AppPalette.light);

  static ThemeData _build(AppPalette p) {
    final text = AppTextTheme.from(p);
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    return ThemeData(
      brightness: brightness,
      fontFamily: AppFonts.body,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      extensions: [p, text],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.textPrimary,
        onPrimary: p.textInverse,
        secondary: p.accent,
        onSecondary: AppColors.white,
        surface: p.surface,
        onSurface: p.textPrimary,
        error: p.error,
        onError: AppColors.white,
        outline: p.border,
      ),
      textTheme: TextTheme(
        displayLarge: text.display,
        headlineMedium: text.headline,
        titleMedium: text.title,
        bodyLarge: text.body,
        bodyMedium: text.body,
        bodySmall: text.bodySmall,
        labelLarge: text.label,
        labelSmall: text.caption,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AppSizes.appBarHeight,
        titleTextStyle: text.label,
      ),
      dividerTheme: DividerThemeData(
        color: p.border,
        thickness: AppBorder.thin,
        space: AppBorder.thin,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceRaised,
        hintStyle: text.body.copyWith(color: p.textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: _outline(p.border),
        enabledBorder: _outline(p.border),
        focusedBorder: _outline(p.textPrimary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.textPrimary,
          foregroundColor: p.textInverse,
          disabledBackgroundColor: p.disabled,
          minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
          textStyle: text.button,
          shape: const StadiumBorder(),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.borderStrong,
        selectionHandleColor: p.accent,
      ),
    );
  }

  /// The Material 3 variant used by Settings: the app palette mapped onto
  /// surfaceContainer levels, M3 type scale in the regular font, and M3
  /// component themes (switch, slider, segmented button, search bar). Derived
  /// from [base] so the rest of the app is unaffected.
  static ThemeData settings(ThemeData base) {
    final p = base.extension<AppPalette>()!;
    final text = base.extension<AppTextTheme>()!;
    final dark = p.isDark;
    final scheme = base.colorScheme.copyWith(
      primary: p.textPrimary,
      onPrimary: p.textInverse,
      primaryContainer: p.surfaceHigh,
      onPrimaryContainer: p.textPrimary,
      secondary: p.accent,
      secondaryContainer: dark ? p.surfaceHigh : p.surfaceRaised,
      onSecondaryContainer: p.textPrimary,
      surface: p.background,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: dark ? p.surfaceRaised : p.surface,
      surfaceContainerHigh: dark ? p.surfaceHigh : p.surfaceRaised,
      surfaceContainerHighest: dark ? p.border : p.surfaceRaised,
      outline: p.borderStrong,
      outlineVariant: p.border,
      error: p.error,
      onError: AppColors.white,
    );
    TextStyle weight(TextStyle s, double w) =>
        s.copyWith(fontVariations: [FontVariation.weight(w)]);
    final type = ThemeData(
      brightness: base.brightness,
      fontFamily: AppFonts.body,
    ).textTheme.apply(bodyColor: p.textPrimary, displayColor: p.textPrimary);
    final textTheme = type.copyWith(
      headlineMedium: weight(type.headlineMedium!, 600),
      headlineSmall: weight(type.headlineSmall!, 600),
      titleLarge: weight(type.titleLarge!, 600),
      titleMedium: weight(type.titleMedium!, 500),
      titleSmall: weight(type.titleSmall!, 500),
      labelLarge: weight(type.labelLarge!, 500),
      labelMedium: weight(type.labelMedium!, 500),
    );
    final onSurface = scheme.onSurface;
    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: [p, text.readable()],
      splashFactory: InkRipple.splashFactory,
      splashColor: onSurface.withValues(alpha: 0.08),
      highlightColor: onSurface.withValues(alpha: 0.04),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // No titleTextStyle: large app bars then use the M3 defaults
        // (headlineMedium expanded, titleLarge collapsed).
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium!.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xxs,
        ),
        minVerticalPadding: AppSpacing.md,
        horizontalTitleGap: AppSpacing.lg,
        minLeadingWidth: 40,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.white
              : p.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? p.accent
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.transparent
              : p.borderStrong,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.textSecondary,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: p.accent,
        activeTickMarkColor: AppColors.white,
        inactiveTickMarkColor: p.textTertiary,
        valueIndicatorColor: p.textPrimary,
        valueIndicatorTextStyle: textTheme.labelLarge!.copyWith(
          color: p.textInverse,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: p.textPrimary,
          selectedBackgroundColor: p.textPrimary,
          selectedForegroundColor: p.textInverse,
          side: BorderSide(color: p.borderStrong),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(textTheme.bodyLarge),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyLarge!.copyWith(color: scheme.onSurfaceVariant),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  static OutlineInputBorder _outline(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.field),
    borderSide: BorderSide(color: color, width: AppBorder.thin),
  );
}
