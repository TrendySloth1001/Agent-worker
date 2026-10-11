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

  static OutlineInputBorder _outline(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.pill),
    borderSide: BorderSide(color: color, width: AppBorder.thin),
  );
}
