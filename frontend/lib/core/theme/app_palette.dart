import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_fonts.dart';
import 'app_text_styles.dart';

/// Semantic color roles, resolved per theme.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHigh,
    required this.glass,
    required this.dotGrid,
    required this.scrim,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.userBubble,
    required this.userBubbleText,
    required this.imageBackdrop,
    required this.aiBubble,
    required this.accent,
    required this.error,
    required this.disabled,
    required this.codeBackground,
    required this.synKeyword,
    required this.synString,
    required this.synNumber,
    required this.synComment,
    required this.synPlain,
    required this.isDark,
  });

  final Color background, surface, surfaceRaised, surfaceHigh, glass;
  final Color dotGrid, scrim;
  final Color border, borderStrong;
  final Color textPrimary, textSecondary, textTertiary, textInverse;
  final Color userBubble, userBubbleText, aiBubble;

  /// Behind images: diagrams are often transparent line art.
  final Color imageBackdrop;
  final Color accent, error, disabled;
  final Color codeBackground;
  final Color synKeyword, synString, synNumber, synComment, synPlain;
  final bool isDark;

  static const dark = AppPalette(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceRaised: AppColors.darkSurfaceRaised,
    surfaceHigh: AppColors.darkSurfaceHigh,
    glass: AppColors.darkGlass,
    dotGrid: AppColors.darkDotGrid,
    scrim: AppColors.darkScrim,
    border: AppColors.darkBorder,
    borderStrong: AppColors.darkBorderStrong,
    textPrimary: AppColors.white,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    textInverse: AppColors.black,
    userBubble: AppColors.white,
    userBubbleText: AppColors.black,
    imageBackdrop: AppColors.imageBackdrop,
    aiBubble: AppColors.darkSurfaceRaised,
    accent: AppColors.red,
    error: AppColors.red,
    disabled: AppColors.darkDisabled,
    codeBackground: AppColors.darkCode,
    synKeyword: AppColors.darkSynKeyword,
    synString: AppColors.darkSynString,
    synNumber: AppColors.darkSynNumber,
    synComment: AppColors.darkSynComment,
    synPlain: AppColors.white,
    isDark: true,
  );

  static const light = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceRaised: AppColors.lightSurfaceRaised,
    surfaceHigh: AppColors.lightSurfaceHigh,
    glass: AppColors.lightGlass,
    dotGrid: AppColors.lightDotGrid,
    scrim: AppColors.lightScrim,
    border: AppColors.lightBorder,
    borderStrong: AppColors.lightBorderStrong,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    textInverse: AppColors.white,
    userBubble: AppColors.lightTextPrimary,
    userBubbleText: AppColors.white,
    imageBackdrop: AppColors.imageBackdrop,
    aiBubble: AppColors.lightSurfaceRaised,
    accent: AppColors.red,
    error: AppColors.red,
    disabled: AppColors.lightDisabled,
    codeBackground: AppColors.lightCode,
    synKeyword: AppColors.lightSynKeyword,
    synString: AppColors.lightSynString,
    synNumber: AppColors.lightSynNumber,
    synComment: AppColors.lightSynComment,
    synPlain: AppColors.lightTextPrimary,
    isDark: false,
  );

  static String _hex(Color c) {
    final v = c.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  /// Hex strings for Mermaid's `themeVariables`.
  Map<String, String> mermaidVars() => {
    'background': _hex(background),
    'primaryColor': _hex(surfaceRaised),
    'primaryBorderColor': _hex(borderStrong),
    'lineColor': _hex(textSecondary),
    'textColor': _hex(textPrimary),
    'fontFamily': AppFonts.body,
  };

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      glass: l(glass, other.glass),
      dotGrid: l(dotGrid, other.dotGrid),
      scrim: l(scrim, other.scrim),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      textInverse: l(textInverse, other.textInverse),
      userBubble: l(userBubble, other.userBubble),
      userBubbleText: l(userBubbleText, other.userBubbleText),
      imageBackdrop: l(imageBackdrop, other.imageBackdrop),
      aiBubble: l(aiBubble, other.aiBubble),
      accent: l(accent, other.accent),
      error: l(error, other.error),
      disabled: l(disabled, other.disabled),
      codeBackground: l(codeBackground, other.codeBackground),
      synKeyword: l(synKeyword, other.synKeyword),
      synString: l(synString, other.synString),
      synNumber: l(synNumber, other.synNumber),
      synComment: l(synComment, other.synComment),
      synPlain: l(synPlain, other.synPlain),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  AppTextTheme get text => Theme.of(this).extension<AppTextTheme>()!;
}
