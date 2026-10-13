import 'dart:ui' show BlendMode;

/// The animated dot-matrix backdrop (assistant overlay): a Nothing-style grid
/// of round dots over a see-through veil, with a red "energy" layer driven by
/// a spring field (see `lib/core/motion/spring_field.dart`). The field is
/// kicked by the opening wave, touches, the microphone and the thinking
/// waves; what the springs do is what you see.
abstract final class DotMatrixSizes {
  /// Distance between dot centres, in dp.
  static const spacing = 12.0;

  /// Radius of a resting (ink) dot.
  static const baseRadius = 1.3;

  /// Radius of a red dot at the lowest step, at energy 1 and at the hottest
  /// step (energy [energyMax]).
  static const energyMinRadius = 1.35;
  static const energyFullRadius = 2.55;
  static const energyMaxRadius = 3.1;

  /// Energy is drawn in this many size/colour steps (one batched draw call
  /// each).
  static const energyLevels = 18;

  /// Energy below this is not drawn (a resting dot shows instead).
  static const energyFloor = 0.07;

  /// The hottest step: springs overshoot past 1 into the white-hot core.
  static const energyMax = 1.45;

  /// Red dot opacity at the lowest step (it reaches 1 at energy 1).
  static const energyMinAlphaDark = 0.24;
  static const energyMinAlphaLight = 0.4;

  /// Ink dot opacity at the top and the bottom of the screen.
  static const inkTopAlphaLight = 0.0;
  static const inkBottomAlphaLight = 0.16;
  static const inkTopAlphaDark = 0.0;
  static const inkBottomAlphaDark = 0.22;

  /// Where (share of height) the ink dots start to show.
  static const inkFadeStart = 0.18;

  /// Ink dot opacity is drawn in this many steps (one draw call each).
  static const inkLevels = 12;

  /// The veil: clear at the top, denser towards the pill (like Gemini's).
  static const veilStops = [0.0, 0.42, 1.0];
  static const veilMidLight = 0.30;
  static const veilEndLight = 0.86;
  static const veilMidDark = 0.3;
  static const veilEndDark = 0.9;

  /// The soft red haze under the bottom dots.
  static const hazeHeight = 260.0;
  static const hazeAlphaLight = 0.09;
  static const hazeAlphaDark = 0.2;

  // ---- bloom ---------------------------------------------------------------

  /// The soft glow sprite (a radial gradient), rendered once at this size
  /// (px) and scaled per dot.
  static const bloomSprite = 64.0;

  /// The sprite's gradient: opacity at these stops from centre to edge.
  static const bloomStops = [0.0, 0.22, 0.55, 1.0];
  static const bloomProfile = [1.0, 0.55, 0.16, 0.0];

  /// Dots above this energy get a halo, its radius growing to the max.
  static const bloomFloor = 0.42;
  static const bloomMinRadius = 7.0;
  static const bloomMaxRadius = 15.0;

  /// Halo opacity at full energy.
  static const bloomAlphaLight = 0.16;
  static const bloomAlphaDark = 0.26;

  /// The aurora: one big halo per column along the bottom edge, as bright as
  /// that column's energy.
  static const auroraRows = 4;
  static const auroraRadius = 90.0;
  static const auroraRise = 30.0;
  static const auroraAlphaLight = 0.07;
  static const auroraAlphaDark = 0.16;

  /// How the halos mix: added light on dark, multiplied ink on light (red
  /// on white stays crisp and never washes out).
  static const bloomBlendDark = BlendMode.plus;
  static const bloomBlendLight = BlendMode.multiply;

  // ---- idle glow (sum of sines along the bottom edge) ----------------------

  /// Height (dp) over which the bottom glow fades out.
  static const glowHeight = 150.0;

  /// How much the glow height swells with the breathing.
  static const glowSwell = 0.6;

  /// Peak energy of the idle glow right after opening, and at rest.
  static const idleStrength = 1.0;
  static const idleRest = 0.8;

  /// Spatial frequencies (radians per dp) and speeds (radians per second).
  static const breathK1 = 0.011;
  static const breathK2 = 0.027;
  static const breathK3 = 0.0045;
  static const breathW1 = 0.9;
  static const breathW2 = 1.55;
  static const breathW3 = 0.5;
  static const breathPhase = 1.7;

  /// Weights of the three sines (they sum to 0.5 around a 0.5 mean, so the
  /// breathing stays in 0..1).
  static const breathA1 = 0.24;
  static const breathA2 = 0.16;
  static const breathA3 = 0.1;

  /// The quietest column keeps this share of the glow.
  static const breathFloor = 0.2;

  /// Glow strength dips by this share while the thinking waves run.
  static const busyDim = 0.35;

  /// Rows beyond this many glow heights have no target (skipped).
  static const falloffReach = 2.2;

  // ---- open wave (an impulse front) -----------------------------------------

  /// The front rises to this share of the height (from the bottom).
  static const openReach = 0.62;

  /// The front is an ellipse centred under the bottom edge: horizontal
  /// distances count this much (lower = flatter, wider front).
  static const openAspect = 1.15;

  /// Velocity kick (energy per second) given to a dot as the front passes,
  /// at the bottom and at the top of its reach.
  static const openKick = 27.0;
  static const openKickTop = 0.22;

  /// The glow fills in this far (dp) behind the front.
  static const openGate = 160.0;

  // ---- thinking / streaming: travelling waves that interfere --------------

  /// Two waves: spatial frequencies along x and up the rows (radians per
  /// dp) and speeds (radians per second); they run in opposite directions.
  static const thinkK1 = 0.034;
  static const thinkD1 = 0.022;
  static const thinkW1 = 5.2;
  static const thinkK2 = 0.019;
  static const thinkD2 = -0.03;
  static const thinkW2 = 3.4;

  /// A bright packet sweeps left to right on top of the interference.
  static const sweepWidth = 90.0;
  static const sweepOffscreen = 1.5;
  static const sweepFloor = 0.5;

  /// Height (dp) the waves fade out over.
  static const thinkHeight = 210.0;
  static const thinkingStrength = 1.7;
  static const streamingStrength = 0.9;

  // ---- listening -----------------------------------------------------------

  /// Extra glow height (dp) at full microphone level.
  static const listenLift = 190.0;
  static const listenStrength = 1.05;

  /// Gentle pulse when no level comes in (radians per second).
  static const listenPulseSpeed = 3.2;
  static const listenPulseDepth = 0.25;

  /// Louder columns rise between these shares of the lift.
  static const listenLiftMin = 0.75;
  static const listenLiftSpread = 0.5;

  /// Turbulence: random kicks along the bottom rows, per frame at 60 fps,
  /// scaled by the level.
  static const turbulenceKicks = 5;
  static const turbulenceRows = 3;
  static const turbulenceKick = 5.0;

  // ---- touch ---------------------------------------------------------------

  /// A press kicks the dots under the finger (energy per second at the
  /// centre, Gaussian radius in cells).
  static const touchKick = 38.0;
  static const touchSigma = 1.2;

  /// Dragging kicks along the path, scaled by distance moved per event
  /// (full kick at this many dp), with a smaller radius.
  static const dragKick = 12.0;
  static const dragFull = 18.0;
  static const dragSigma = 1.1;

  /// Pending touches between two frames (extra ones are dropped).
  static const touchQueue = 16;

  /// A long gap between frames (app hidden) counts as one step this long (s).
  static const maxFrameStep = 0.1;

  /// A gap longer than this (s) is a resume (the app was hidden or stalled):
  /// the field lands at rest on its targets instead of playing on.
  static const resumeGap = 0.25;

  /// The still (reduced motion) frame shows the glow at this time (s): a
  /// lively phase of the breathing.
  static const stillTime = 2.6;
}

/// The springs of the backdrop's field.
abstract final class DotMatrixPhysics {
  /// One swing of a dot (s) and its damping ratio: low enough that kicks
  /// ring and overshoot, high enough that they settle in about a second.
  static const period = 0.46;
  static const damping = 0.24;

  /// Neighbour coupling of the glow (cells per second): a little, so the
  /// open front's kicks blend into a band instead of single dots.
  static const waveSpeed = 7.0;

  /// The ripple membrane: loose springs (period s, damping ratio) and strong
  /// coupling (cells per second), so energy travels instead of ringing in
  /// place.
  static const ripplePeriod = 1.8;
  static const rippleDamping = 0.2;
  static const rippleSpeed = 20.0;

  /// A ripple's height (either sign) counts this much as energy.
  static const rippleGain = 1.0;

  /// Fixed integration step (s) and the most steps per frame.
  static const timestep = 1 / 120;
  static const maxSubsteps = 12;

  /// No dot goes past this energy, whatever the input.
  static const limit = 2.0;

  /// Mode cross-fades are springs too: period (s) and damping ratio.
  static const blendPeriod = 0.5;
  static const blendDamping = 0.8;

  /// Below this field motion (sum of squared velocities) and with nothing
  /// going on, the backdrop runs at the calm frame rate.
  static const calmKinetic = 0.5;
}

/// The colour ramp of the energy layer, all derived from the palette's
/// accent: deep red → orange-red → (dark only) a white-hot core.
abstract final class DotMatrixColors {
  /// Energy (share of the steps) where the red starts warming up and where
  /// it is fully hot.
  static const warmStart = 0.5;
  static const hotStart = 0.78;

  /// The hot colour: the accent with its hue turned towards orange
  /// (degrees), lighter and fully saturated.
  static const hotHueShift = 16.0;
  static const hotLightnessDark = 0.6;
  static const hotLightnessLight = 0.5;

  /// The white-hot core on dark: how far the hottest step mixes towards the
  /// ink (white). Light mode keeps the hot red (white would vanish).
  static const coreMixDark = 0.4;
  static const coreMixLight = 0.0;

  /// Entries of the colour lookup table used for the halos.
  static const lutSize = 64;
}

abstract final class DotMatrixDurations {
  /// The open front's time constant: it covers 1 - 1/e of its reach in
  /// this long, then slows down (decelerating, like a thrown wave).
  static const openTau = Duration(milliseconds: 210);

  /// After this long the open wave is over (the glow gate opens fully).
  static const open = Duration(milliseconds: 900);

  /// The idle glow calms from its open strength to rest over this long.
  static const idleSettle = Duration(milliseconds: 2200);

  /// One left-to-right sweep while thinking / streaming.
  static const thinkingPass = Duration(milliseconds: 1500);
  static const streamingPass = Duration(milliseconds: 2400);

  /// Smoothing of the microphone level.
  static const level = Duration(milliseconds: 90);

  /// Frame pacing: never faster than 60 fps; 30 fps once idle and calm.
  static const frame = Duration(microseconds: 16667);
  static const calmFrame = Duration(microseconds: 33333);

  /// Ticks may come this much early (vsync jitter) and still count.
  static const frameSlack = Duration(milliseconds: 3);
}
