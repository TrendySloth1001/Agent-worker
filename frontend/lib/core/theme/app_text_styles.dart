import 'package:flutter/material.dart';

import '../constants/app_fonts.dart';
import '../constants/app_sizes.dart';
import 'app_palette.dart';

/// Color-free style bases. Colors are applied by [AppTextTheme].
abstract final class AppTextStyles {
  // Big type uses the regular face (Space Grotesk) in bold: no pixel font.
  static const displayLarge = TextStyle(
    fontFamily: AppFonts.body,
    letterSpacing: -1,
    fontSize: AppFontSize.displayLarge,
    fontVariations: [FontVariation.weight(700)],
    height: 1.0,
  );

  static const display = TextStyle(
    fontFamily: AppFonts.body,
    letterSpacing: -0.5,
    fontSize: AppFontSize.display,
    fontVariations: [FontVariation.weight(700)],
    height: 1.0,
  );

  static const headline = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: AppFontSize.headline,
    fontVariations: [FontVariation.weight(700)],
    height: 1.1,
  );

  /// Big figures in data cards: body face, heavier weight.
  static const metric = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: AppFontSize.metric,
    fontVariations: [FontVariation.weight(600)],
    height: 1.15,
  );

  static const title = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: AppFontSize.title,
    fontVariations: [FontVariation.weight(500)],
    height: 1.3,
  );

  static const body = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: AppFontSize.body,
    fontVariations: [FontVariation.weight(400)],
    height: 1.5,
  );

  static const bodySmall = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: AppFontSize.bodySmall,
    fontVariations: [FontVariation.weight(400)],
    height: 1.45,
  );

  static const label = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: AppFontSize.label,
    letterSpacing: 1.2,
    height: 1.3,
  );

  static const caption = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: AppFontSize.caption,
    letterSpacing: 1.0,
    height: 1.3,
  );

  static const button = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: AppFontSize.label,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
  );

  static const code = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: AppFontSize.bodySmall,
    height: 1.45,
  );
}

/// Text styles with colors applied for the active theme.
class AppTextTheme extends ThemeExtension<AppTextTheme> {
  const AppTextTheme({
    required this.display,
    required this.headline,
    required this.metric,
    required this.title,
    required this.body,
    required this.bodySmall,
    required this.label,
    required this.caption,
    required this.button,
    required this.code,
  });

  factory AppTextTheme.from(AppPalette p) => AppTextTheme(
    display: AppTextStyles.displayLarge.copyWith(color: p.textPrimary),
    headline: AppTextStyles.headline.copyWith(color: p.textPrimary),
    metric: AppTextStyles.metric.copyWith(color: p.textPrimary),
    title: AppTextStyles.title.copyWith(color: p.textPrimary),
    body: AppTextStyles.body.copyWith(color: p.textPrimary),
    bodySmall: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
    label: AppTextStyles.label.copyWith(color: p.textPrimary),
    caption: AppTextStyles.caption.copyWith(color: p.textTertiary),
    button: AppTextStyles.button.copyWith(color: p.textInverse),
    code: AppTextStyles.code.copyWith(color: p.synPlain),
  );

  final TextStyle display,
      headline,
      metric,
      title,
      body,
      bodySmall,
      label,
      caption,
      button,
      code;

  @override
  AppTextTheme copyWith() => this;

  @override
  AppTextTheme lerp(ThemeExtension<AppTextTheme>? other, double t) {
    if (other is! AppTextTheme) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTextTheme(
      display: l(display, other.display),
      headline: l(headline, other.headline),
      metric: l(metric, other.metric),
      title: l(title, other.title),
      body: l(body, other.body),
      bodySmall: l(bodySmall, other.bodySmall),
      label: l(label, other.label),
      caption: l(caption, other.caption),
      button: l(button, other.button),
      code: l(code, other.code),
    );
  }
}
