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

  /// Logos stacked in a chip that groups several sources, and their overlap.
  static const citeStackMax = 3;
  static const citeStackStep = 8.0;
  static const monogramScale = 0.62;

  /// Longer, because the "Chat · " prefix of a past-chat source takes seven.
  static const citeChatNameMaxChars = 26;

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

  /// A one-item list has no timeline to start: a plain dot, this share of
  /// the marker box (a lone filled square read as a stray "■" glyph).
  static const tlSingleDotScale = 0.5;

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

/// Responsive markdown tables: measuring, layout choice, chrome and cards.
abstract final class MdTableSizes {
  // Cell padding and text.
  static const cellHorizontal = 12.0;
  static const cellVertical = 10.0;
  static const lineHeight = 1.4;

  /// Safety margin on measured text width (bold and variable-font drift).
  static const measureSlack = 1.06;
  static const charWidth = 7.5;

  // Column clamps (dp, padding included).
  static const minColumn = 72.0;
  static const maxColumn = 220.0;
  static const firstMaxColumn = 150.0;
  static const scrollMaxColumn = 200.0;
  static const mathMaxColumn = 360.0;
  static const fullscreenMaxColumn = 320.0;

  /// The frozen first column never takes more than this share of the width.
  static const stickyMaxShare = 0.45;

  // Layout choice.
  /// Largest overflow (share of natural width) fixed by wrapping cells.
  static const shrinkTolerance = 0.22;

  /// A value column wider than this (unwrapped) is long prose.
  static const longCell = 180.0;
  static const comparisonMinValueColumns = 2;
  static const comparisonMaxValueColumns = 3;

  /// Beyond this many times the available width, or this many columns,
  /// scrolling stops being readable and rows become cards.
  static const maxScrollFactor = 2.4;
  static const maxScrollColumns = 8;

  /// Streaming locks the layout once the table has this many body rows.
  static const streamLockRows = 2;

  // Chrome.
  static const headerHeight = 36.0;
  static const zebraAlpha = 0.55;
  static const headerRule = 1.0;
  static const fadeWidth = 28.0;
  static const stickyShadowWidth = 8.0;
  static const stickyShadowAlpha = 0.5;
  static const hintAlpha = 0.9;
  static const sortIconGap = 4.0;
  static const toggleRadius = 6.0;
  static const toggleHPad = 8.0;
  static const toggleVPad = 4.0;
  static const chromeGap = 12.0;

  // Cards.
  static const cardPadding = 14.0;
  static const cardLineGap = 6.0;
  static const cardTitleGap = 8.0;
  static const labelMaxWidth = 112.0;
  static const labelMinWidth = 56.0;
  static const labelShare = 0.38;
  static const labelGap = 12.0;

  // Full screen.
  static const fullscreenMinScale = 0.5;
  static const fullscreenMaxScale = 4.0;
  static const fullscreenMargin = 48.0;
  static const fullscreenBarHeight = 56.0;
}
