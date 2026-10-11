/// Sizes for rich reply rendering: citation chips, timeline lists, tables and
/// callouts.
abstract final class MdSizes {
  // ==highlight== background strength.
  static const markAlpha = 0.28;

  // Section headings: h1/h2 large with a rule above, h3+ smaller.
  static const h2FontSize = 21.0;
  static const h3FontSize = 18.0;
  static const headingGap = 28.0;
  static const headingIconScale = 0.85;

  // Icon that opens a line: drawn in a circular avatar.
  static const iconAvatarScale = 1.75;
  static const iconAvatarGlyphScale = 0.95;

  // Inline citation chip
  static const citeFavicon = 12.0;
  static const citeChipHeight = 18.0;
  static const citeChipMaxWidth = 140.0;
  static const citeNameMaxChars = 18;

  /// Second-level labels that belong to the TLD (bbc.co.uk -> bbc).
  static const citeTldSecondLevel = {
    'co',
    'com',
    'org',
    'net',
    'gov',
    'edu',
    'ac',
  };

  // Timeline lists
  static const tlMarker = 12.0;

  /// Markers when items lead with an icon.
  static const tlIconMarker = 20.0;
  static const tlIconMarkerNested = 16.0;

  // Inline images placed by the model.
  static const imageMaxHeight = 240.0;
  static const imagePlaceholderHeight = 160.0;
  static const tlMarkerNested = 8.0;

  // Picture lists: a thumbnail beside each item, stacked on narrow screens.
  static const mediaThumbWidth = 120.0;
  static const mediaThumbAspect = 4 / 3;
  static const mediaStackBelow = 360.0;
  static const mediaStackedHeight = 160.0;
  static const tlMarkerOrdered = 18.0;
  static const tlMarkerOrderedNested = 16.0;
  static const tlCheckbox = 14.0;
  static const tlGutterGap = 10.0;
  static const tlSpine = 1.5;
  static const tlSpineNested = 1.0;
  static const tlMarkerStroke = 1.5;
  static const tlCurveRadius = 8.0;
  static const tlItemGap = 4.0;
  static const tlMarkerRadius = 2.0;
  static const tlDiamondTurns = 0.125;
  static const tlDiamondScale = 0.72;

  // Tables
  static const tableMinColumn = 96.0;
  static const tableMaxColumn = 240.0;
  static const tableMaxMathColumn = 360.0;
  static const tableCharWidth = 7.5;
  static const tableCellVertical = 10.0;
  static const tableCodeFontSize = 12.0;

  // Math
  static const mathInlineScale = 1.0;
  static const mathDisplayScale = 1.15;
  static const tableMathMinScale = 0.75;

  // Callouts
  static const calloutBar = 2.0;

  // Evidence sheet
  static const evidenceBar = 2.0;
  static const evidenceMeterDots = 5;
  static const evidenceMeterDot = 6.0;
  static const evidenceMeterGap = 3.0;
  static const evidenceStrongScore = 0.65;
  static const evidencePartialScore = 0.45;
  static const evidenceMaxItems = 4;
}
