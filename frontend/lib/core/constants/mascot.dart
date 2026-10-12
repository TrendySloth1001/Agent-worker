/// Layout and asset constants for the animated mascot (Noto Animated Emoji,
/// CC BY 4.0, see assets/mascots/LICENSE.md).
abstract final class MascotLayout {
  /// Backdrop disc diameter as a share of the widget size.
  static const discShare = 0.94;

  /// The emoji's share of the widget size.
  static const emojiShare = 0.72;

  /// Dot ring on the backdrop: dot radius and ring radius as a share of size.
  static const haloDotRadius = 0.012;
  static const haloDots = 28;
  static const haloRingShare = 0.46;

  /// Alpha of the tonal disc fill and of the halo dots.
  static const discAlpha = 0.55;
  static const haloAlpha = 0.9;

  static const crossFade = Duration(milliseconds: 320);
}

abstract final class MascotAssets {
  static const dir = 'assets/mascots';
  static const idle = '$dir/idle.json';
  static const thinking = '$dir/thinking.json';
  static const writing = '$dir/writing.json';
  static const searching = '$dir/searching.json';
  static const celebrating = '$dir/celebrating.json';
  static const sleeping = '$dir/sleeping.json';
  static const error = '$dir/error.json';
  static const offline = '$dir/offline.json';
  static const code = '$dir/code.json';
}

abstract final class MascotSizes {
  static const small = 44.0;
  static const medium = 96.0;
  static const large = 140.0;
  static const hero = 168.0;
}

abstract final class MascotStrings {
  static const idle = 'Sparky is here';
  static const thinking = 'Sparky is thinking';
  static const writing = 'Sparky is writing';
  static const searching = 'Sparky is searching';
  static const celebrating = 'Sparky is celebrating';
  static const sleeping = 'Sparky is asleep';
  static const error = 'Sparky hit a problem';
  static const offline = 'Sparky is offline';
  static const github = 'Sparky at the keyboard';
}
