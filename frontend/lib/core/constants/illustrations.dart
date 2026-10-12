import 'package:flutter/painting.dart';

/// Hand-drawn Open Peeps and Open Doodles illustrations (both CC0, Pablo
/// Stanley). Credits: assets/illustrations/CREDITS.md.
abstract final class IllustrationAssets {
  static const _dir = 'assets/illustrations';
  static const login = '$_dir/login.svg';
  static const hello = '$_dir/hello.svg';
  static const github = '$_dir/github.svg';
  static const emptyKnowledge = '$_dir/empty_knowledge.svg';
  static const emptyHistory = '$_dir/empty_history.svg';

  // Home rotation.
  static const homeChat = '$_dir/home_chat.svg';
  static const homeCode = '$_dir/home_code.svg';
  static const homeRead = '$_dir/home_read.svg';
  static const homeThink = '$_dir/home_think.svg';
  static const homeCoffee = '$_dir/home_coffee.svg';
  static const homeDream = '$_dir/home_dream.svg';

  // GitHub rotation.
  static const githubBranches = '$_dir/github_branches.svg';
  static const githubCode = '$_dir/github_code.svg';

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

  /// Rotating slots are this many times wider than tall, so wide scenes
  /// shrink a little instead of overpowering the upright ones.
  static const rotatingAspect = 1.6;

  /// Idle float: how far the art drifts up and down, in logical pixels.
  static const float = 3.0;

  /// Scale an incoming scene starts from, and how far it rises (fraction of
  /// the slot height).
  static const swapScale = 0.96;
  static const swapRise = 0.03;
}

abstract final class IllustrationDurations {
  static const entrance = Duration(milliseconds: 450);

  /// Collapse/expand when the keyboard opens on the auth screens.
  static const resize = Duration(milliseconds: 200);

  /// How long each scene of a rotating illustration stays up.
  static const rotateEvery = Duration(milliseconds: 4500);

  /// Cross-fade between two scenes.
  static const swap = Duration(milliseconds: 700);

  /// One idle float, up and back down.
  static const floatCycle = Duration(milliseconds: 3600);
}

/// Starter prompts under HELLO on an empty chat (text: AppStrings).
abstract final class EmptyChatSuggestions {
  static const chipHeight = 36.0;

  /// Below this much free height the prompts hide too, leaving HELLO.
  static const hiddenBelow = 220.0;
}
