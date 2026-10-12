/// The animated dot-matrix backdrop (assistant overlay): a Nothing-style grid
/// of round dots over a see-through veil, with a red "energy" layer that
/// rises on open, breathes along the bottom edge, shimmers while thinking and
/// follows the microphone while listening.
abstract final class DotMatrixSizes {
  /// Distance between dot centres, in dp.
  static const spacing = 12.0;

  /// Radius of a resting (ink) dot.
  static const baseRadius = 1.3;

  /// Radius of a red dot at zero and at full energy.
  static const energyMinRadius = 1.4;
  static const energyMaxRadius = 2.6;

  /// Energy is drawn in this many size/brightness steps (one batched draw
  /// call each).
  static const energyLevels = 10;

  /// Energy below this is not drawn at all (a resting dot shows instead).
  static const energyFloor = 0.06;

  /// Red dot opacity at the lowest and the highest step.
  static const energyMinAlpha = 0.22;
  static const energyMaxAlpha = 1.0;

  /// Ink dot opacity at the top and the bottom of the screen.
  static const inkTopAlphaLight = 0.0;
  static const inkBottomAlphaLight = 0.16;
  static const inkTopAlphaDark = 0.0;
  static const inkBottomAlphaDark = 0.22;

  /// Where (share of height) the ink dots start to show.
  static const inkFadeStart = 0.18;

  /// The veil: clear at the top, denser towards the pill (like Gemini's).
  static const veilStops = [0.0, 0.42, 1.0];
  static const veilMidLight = 0.30;
  static const veilEndLight = 0.86;
  static const veilMidDark = 0.3;
  static const veilEndDark = 0.9;

  /// The soft red haze under the bottom dots.
  static const hazeHeight = 220.0;
  static const hazeAlphaLight = 0.10;
  static const hazeAlphaDark = 0.16;

  // ---- idle breathing (sum of sines along the bottom edge) ----------------

  /// Height (dp) over which the bottom glow fades out.
  static const glowHeight = 130.0;

  /// How much the glow height swells with the wave.
  static const glowSwell = 0.6;

  /// Peak energy of the idle glow.
  static const idleStrength = 0.8;

  /// Spatial frequencies (radians per dp) and speeds (radians per second).
  static const breathK1 = 0.011;
  static const breathK2 = 0.027;
  static const breathK3 = 0.0045;
  static const breathW1 = 0.9;
  static const breathW2 = 1.55;
  static const breathW3 = 0.5;
  static const breathPhase = 1.7;

  /// Weights of the three sines (they sum to 0.5 around a 0.5 mean, so the
  /// wave stays in 0..1).
  static const breathA1 = 0.24;
  static const breathA2 = 0.16;
  static const breathA3 = 0.1;

  /// The quietest column keeps this share of the glow.
  static const breathFloor = 0.15;

  /// Glow strength dips by this share while a shimmer runs over it.
  static const busyDim = 0.3;

  /// Gaussian falloff is cut where it fades out (in glow heights).
  static const falloffReach = 1.8;

  // ---- open wave -----------------------------------------------------------

  /// Thickness (dp) of the rising wavefront.
  static const waveWidth = 40.0;

  /// The front is ahead in the middle: edges lag by this many dp.
  static const waveCurve = 70.0;

  /// The front stops this share of the height from the top.
  static const waveTop = 0.5;

  /// Peak energy of the wavefront.
  static const waveStrength = 0.9;

  /// How the wavefront fades as it rises: (1 - progress) ^ this.
  static const waveFadePower = 1.1;

  // ---- thinking / streaming shimmer ---------------------------------------

  /// Width (dp) of the travelling shimmer packet.
  static const shimmerWidth = 80.0;

  /// Height (dp) of the rows the shimmer runs along.
  static const shimmerHeight = 220.0;
  static const thinkingStrength = 0.95;
  static const streamingStrength = 0.6;

  /// Rows fade from the bottom over this share of [shimmerHeight].
  static const shimmerFalloff = 0.6;

  /// The packet starts and ends this many widths off screen.
  static const shimmerOffscreen = 2.0;

  // ---- listening -----------------------------------------------------------

  /// Extra glow height (dp) at full microphone level.
  static const listenLift = 170.0;
  static const listenStrength = 0.9;

  /// Gentle pulse when no level comes in (radians per second).
  static const listenPulseSpeed = 3.2;
  static const listenPulseDepth = 0.25;

  /// Louder columns rise between these shares of the lift.
  static const listenLiftMin = 0.75;
  static const listenLiftSpread = 0.5;

  /// Ink dot opacity is drawn in this many steps (one draw call each).
  static const inkLevels = 12;

  /// A long gap between frames (app hidden) counts as one step this long (s).
  static const maxFrameStep = 0.1;
}

abstract final class DotMatrixDurations {
  /// The red wave rising on open; short so the overlay feels instant.
  static const open = Duration(milliseconds: 560);

  /// One left-to-right shimmer pass while thinking / streaming.
  static const thinkingPass = Duration(milliseconds: 1500);
  static const streamingPass = Duration(milliseconds: 2400);

  /// How quickly the layers cross-fade when the state changes.
  static const blend = Duration(milliseconds: 260);

  /// Smoothing of the microphone level.
  static const level = Duration(milliseconds: 90);
}
