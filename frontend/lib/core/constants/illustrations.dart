import 'package:flutter/painting.dart';

/// Hand-drawn Open Peeps illustrations (CC0, Pablo Stanley).
/// Credits: assets/illustrations/CREDITS.md.
abstract final class IllustrationAssets {
  static const _dir = 'assets/illustrations';
  static const login = '$_dir/login.svg';
  static const hello = '$_dir/hello.svg';
  static const github = '$_dir/github.svg';
  static const emptyKnowledge = '$_dir/empty_knowledge.svg';
  static const emptyHistory = '$_dir/empty_history.svg';

  /// Placeholder colors the SVGs are authored with; swapped per theme.
  static const ink = Color(0xFF000000);
  static const paper = Color(0xFFFFFFFF);
}

abstract final class IllustrationSizes {
  /// Fallback when no height is given.
  static const defaultHeight = 160.0;

  // Auth screens: shrink, then hide, as the screen gets shorter.
  static const login = 132.0;
  static const loginCompact = 92.0;
  static const loginCompactBelow = 720.0;
  static const loginHiddenBelow = 560.0;

  // Empty chat: hidden when the space between top bar and input is short
  // (e.g. with the keyboard open).
  static const hello = 168.0;
  static const helloHiddenBelow = 420.0;

  static const github = 120.0;
  static const emptyKnowledge = 140.0;
  static const emptyHistory = 120.0;

  /// Entrance rise, in logical pixels.
  static const rise = 8.0;
}

abstract final class IllustrationDurations {
  static const entrance = Duration(milliseconds: 450);

  /// Collapse/expand when the keyboard opens on the auth screens.
  static const resize = Duration(milliseconds: 200);
}

/// Starter prompts under HELLO on an empty chat (text: AppStrings).
abstract final class EmptyChatSuggestions {
  static const chipHeight = 36.0;

  /// Below this much free height the prompts hide too, leaving HELLO.
  static const hiddenBelow = 220.0;
}
