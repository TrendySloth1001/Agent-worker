import 'package:flutter/material.dart';

/// Raw color ramp. Widgets never use these for semantic roles; they read
/// `context.palette` instead. Only [red] may be used directly.
abstract final class AppColors {
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const red = Color(0xFFD71921);

  // Dark
  static const darkBackground = black;
  static const darkSurface = Color(0xFF0A0A0A);
  static const darkSurfaceRaised = Color(0xFF141414);
  static const darkSurfaceHigh = Color(0xFF1F1F1F);
  static const darkGlass = Color(0xB3141414);
  static const darkDotGrid = Color(0xFF1C1C1C);
  static const darkScrim = Color(0x99000000);
  static const darkBorder = Color(0xFF2A2A2A);
  static const darkBorderStrong = Color(0xFF3D3D3D);
  static const darkTextSecondary = Color(0xFF999999);
  static const darkTextTertiary = Color(0xFF5C5C5C);
  static const darkDisabled = Color(0xFF333333);
  static const darkCode = Color(0xFF0F0F0F);
  static const darkSynKeyword = Color(0xFFFF6B6B);
  static const darkSynString = Color(0xFFB5B5B5);
  static const darkSynNumber = Color(0xFFE0E0E0);
  static const darkSynComment = Color(0xFF5C5C5C);

  // Light
  static const lightBackground = Color(0xFFF4F4F2);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceRaised = Color(0xFFEBEBE8);
  static const lightSurfaceHigh = Color(0xFFDDDDD9);
  static const lightGlass = Color(0xB3FFFFFF);
  static const lightDotGrid = Color(0xFFE2E2DE);
  static const lightScrim = Color(0x66000000);
  static const lightBorder = Color(0xFFD6D6D2);
  static const lightBorderStrong = Color(0xFFA8A8A3);
  static const lightTextPrimary = Color(0xFF0A0A0A);
  static const lightTextSecondary = Color(0xFF5E5E5A);
  static const lightTextTertiary = Color(0xFF8E8E89);
  static const lightDisabled = Color(0xFFD0D0CC);
  static const lightCode = Color(0xFFEFEFEC);
  static const lightSynKeyword = Color(0xFFB3121A);
  static const lightSynString = Color(0xFF4A4A46);
  static const lightSynNumber = Color(0xFF1A1A1A);
  static const lightSynComment = Color(0xFF8E8E89);

  /// Light tile behind images in both themes.
  static const imageBackdrop = Color(0xFFF2F2F2);
}
