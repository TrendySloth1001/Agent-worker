import 'package:hugeicons/hugeicons.dart';

import 'app_sizes.dart';

/// "Circle to search" in the assistant overlay: copy.
abstract final class CircleStrings {
  static const chip = 'Circle to search';
  static const hint = 'Circle or tap anything to search';
  static const hintAgain = 'Circle something else to search again';
  static const cancel = 'Back to sparky';
  static const reading = 'Cutting out your selection…';
  static const selection = 'SELECTION';

  /// The question sent for a selection (web search on).
  static const searchPrompt = 'What is this? Search the web for it.';
  static const explainPrompt = 'Explain what this is, simply.';
  static String translatePrompt(String language) =>
      'Translate the text in this into $language. Only give the '
      'translation and a one-line note if something is ambiguous.';
  static const translateFallback = 'English';

  // Quick action chips under a circle answer.
  static const search = 'Search';
  static const explain = 'Explain';
  static const translate = 'Translate';
  static const copyText = 'Copy text';
  static const copiedText = 'Copied';
  static const ask = 'Ask…';
  static const reselect = 'Re-select';
  static const askHint = 'Ask about the selection';

  // Not possible here.
  static const needsScreenshot =
      'Circle to search needs the screenshot. Turn on "Use screenshot" in '
      'the assistant settings.';
  static const needsSession =
      'Circle to search works over other apps: hold the power button, then '
      'tap Circle to search or long-press the pill.';
  static const cropFailed = "Couldn't cut that out — try again";
  static const screenFailed = "Couldn't read the screen — try again";
  static const nothingSelected = 'Draw around something to search it.';

  /// The capture of the selection is blank (a protected window, or the
  /// screenshot came back empty): shown in place of the thumbnail.
  static const blankCapture = 'No picture';
  static const blankCaptureNote =
      "Couldn't capture this area. The app may block screenshots.";

  /// Said as the answer when nothing readable could be taken from the selection.
  static const blankAnswer =
      "I couldn't capture anything readable from that selection. The app may "
      'block screenshots; try selecting text you can copy, or share it as text.';

  /// A question about a blank capture that still has its text.
  static String textOnly(String prompt, String text) =>
      '$prompt\n\nThe selection could not be captured as a picture. This is '
      'its text:\n"""\n$text\n"""';
}

abstract final class CircleSizes {
  /// Stroke of the drawn selection and its glow.
  static const stroke = 4.0;
  static const glow = 14.0;
  static const glowBlur = 10.0;
  static const glowAlpha = 0.45;

  /// A tap selects a square this wide around the finger (logical px).
  static const tapSize = 120.0;

  /// A stroke shorter than this (logical px) counts as a tap.
  static const tapSlop = 12.0;

  /// Padding around the selection's bounding box (logical px).
  static const padding = 16.0;

  /// The dim over the frozen screenshot outside the selection.
  static const dimLight = 0.38;
  static const dimDark = 0.55;

  /// The dot grid over the dim (Nothing dot aesthetic).
  static const dotSpacing = 14.0;
  static const dotRadius = 1.1;
  static const dotAlpha = 0.18;

  /// Corner radius of the highlighted selection.
  static const selectionRadius = AppRadius.lg;

  /// The hint bubble at the top.
  static const hintHeight = 40.0;

  /// The thumbnail of the selection in the answer sheet.
  static const thumb = 56.0;

  /// A cut-out is blank when no sampled pixel is brighter than this (0-255);
  /// sampled on a grid this many points a side.
  static const blankLuma = 10;
  static const blankGrid = 24;

  /// Fade under the chips where the answer scrolls out of view.
  static const topFade = 20.0;

  /// JPEG quality of the cut-out sent to the model.
  static const jpegQuality = 88;

  /// The smallest selection (image px) worth sending.
  static const minCropSide = 24;

  /// A text node counts as selected when this share of it is inside the
  /// selection, or when it covers this share of the selection (a word
  /// circled inside a paragraph).
  static const nodeShare = 0.3;
  static const selectionShare = 0.5;

  /// Text of a selection sent with it.
  static const maxSelectionChars = 2000;

  /// Points closer than this (logical px) are merged while drawing.
  static const minPointGap = 2.0;

  /// A selection is at least this wide and tall (logical px), so a straight
  /// line or a thin underline still selects a sensible region.
  static const minSelection = 96.0;
}

abstract final class CircleConfig {
  static const cropName = 'selection.jpg';
  static const cropPrefix = 'circle-';

  /// Strokes drawn within this pause (after lifting the finger) are one
  /// selection; the cut-out starts once the user pauses this long.
  static const strokeMerge = Duration(milliseconds: 600);

  /// The longest the cut-out may take before a friendly retry.
  static const cropTimeout = Duration(seconds: 4);

  /// The longest reading the frozen screen may take.
  static const screenTimeout = Duration(seconds: 4);
}

abstract final class CircleIcons {
  static const circle = HugeIcons.strokeRoundedSearchArea;
  static const search = HugeIcons.strokeRoundedSearch01;
  static const explain = HugeIcons.strokeRoundedBulb;
  static const translate = HugeIcons.strokeRoundedTranslate;
  static const copy = HugeIcons.strokeRoundedTextSelection;
  static const ask = HugeIcons.strokeRoundedMessageQuestion;
  static const reselect = HugeIcons.strokeRoundedCircleArrowReload01;
}
