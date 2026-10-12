/// Sparky, the dot-matrix mascot (drawn in code, no asset files).
abstract final class MascotGrid {
  static const cols = 17;
  static const rows = 15;

  /// One loop of every animation, in seconds.
  static const loopSeconds = 4.0;

  /// Dot radius as a share of the cell size.
  static const dotRadius = 0.36;

  /// Alpha of unlit dots outside / inside the head.
  static const faintOutside = 0.4;
  static const faintInside = 0.85;

  /// Frame shown when motion is reduced (seconds into the loop).
  static const stillAt = 0.0;
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
  static const github = 'Sparky with a code branch';
}
