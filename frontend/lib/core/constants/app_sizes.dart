/// Spacing follows a 4pt grid.
abstract final class AppSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  static const screenPadding = lg;
}

abstract final class AppRadius {
  static const none = 0.0;
  static const sm = 4.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

abstract final class AppFontSize {
  static const caption = 11.0;
  static const label = 12.0;
  static const bodySmall = 14.0;
  static const body = 16.0;
  static const title = 20.0;
  static const metric = 24.0;
  static const headline = 28.0;
  static const display = 40.0;
  static const displayLarge = 56.0;
}

abstract final class AppBorder {
  static const thin = 1.0;
  static const thick = 1.5;
}

abstract final class AppIconSize {
  /// Hugeicons stroke; thinner than the 1.5 default to match the light UI.
  static const stroke = 1.3;

  /// Hugeicons fill their whole box; Material glyphs used about 80% of it.
  /// Drawing at this fraction keeps the old visual weight and layout.
  static const optical = 0.8;
  static const xs = 12.0;
  static const sm = 16.0;
  static const md = 20.0;
  static const lg = 24.0;
  static const empty = 28.0;
}

abstract final class AppSizes {
  // Inline icons in replies, relative to the surrounding text size.
  static const inlineIconScale = 1.2;
  static const inlineIconCacheSize = 400;

  // Images and source chips under replies
  static const imageStripHeight = 132.0;
  static const imageThumbWidth = 176.0;
  static const sourceChipHeight = 30.0;
  static const favicon = 14.0;
  static const sourceChipMaxWidth = 180.0;
  static const sourceCardFavicon = 28.0;
  static const sourceCardSnippetLines = 8;
  static const imageMaxZoom = 5.0;

  static const buttonHeight = 48.0;
  static const inputHeight = 52.0;
  static const appBarHeight = 56.0;
  static const dot = 6.0;
  static const sendButton = 34.0;
  static const thinkingDot = 5.0;

  // Floating UI
  static const topBar = 32.0;
  static const glassBlur = 20.0;
  static const dotGridSpacing = 18.0;
  static const dotGridRadius = 1.0;
  static const scrollButtonThreshold = 300.0;

  /// Room kept clear under the floating top bar and input.
  static const topInset = topBar + AppSpacing.xl;
  static const bottomInset = 80.0;
  static const maxBubbleWidthFactor = 0.8;

  // Shared by settings and chat features
  static const codeHeaderHeight = 28.0;
  static const chipHeight = 24.0;
  static const quotaDot = 6.0;
  static const quotaDotGap = 3.0;
  static const mermaidMinHeight = 120.0;
  static const mermaidMaxInlineHeight = 360.0;
  static const sourceRowHeight = 40.0;
  static const rowHeight = 52.0;
  static const drawerWidthFactor = 0.85;
  static const drawerMaxWidth = 340.0;
  static const drawerButtonHeight = 40.0;
  static const toggleWidth = 40.0;
  static const toggleHeight = 22.0;
  static const toggleKnob = 14.0;
  static const segmentHeight = 36.0;
  static const statusDot = 8.0;
  static const quotaDotCount = 20;
  static const sheetHandleWidth = 32.0;
  static const browserIcon = 32.0;
  static const browserRowHeight = 52.0;
  static const checkBox = 16.0;
  static const chipHorizontalPadding = 10.0;
  static const citeMinTap = 24.0;
  static const mermaidPlaceholderHeight = 72.0;
  static const mermaidViewerMinScale = 1.0;
  static const codeMaxHighlightChars = 20000;
  static const maxLiveDiagrams = 3;
  static const maxHistoryMessages = 40;
  static const maxHistoryChars = 58000;
  static const kbLimitDefault = 20;
  static const kbLimitMax = 100;
  static const kbLimitStep = 10;

  // Personalization field limits (match the backend contract)
  static const profileNameMax = 60;
  static const profileRoleMax = 80;
  static const profileAboutMax = 600;
  static const profileLanguageMax = 40;
  static const profileInstructionsMax = 1500;
  static const profileSignatureMax = 300;
  static const profileEditorLines = 6;
  static const profileValueMaxChars = 40;
  static const stepperButton = 32.0;

  // Settings screen
  static const keyLabelWidth = 72.0;
  static const providerSkeletonHeight = 148.0;
  static const statusStripSkeletonHeight = 128.0;
  static const skeletonBar = 12.0;
  static const skeletonCards = 3;
  static const skeletonBarFactor = 0.4;
  static const statusRing = 1.5;
  static const retryButtonHeight = 36.0;

  // Attachments
  static const attachThumb = 56.0;
  static const attachChipWidth = 150.0;
  static const attachProgress = 2.0;
  static const attachRemove = 20.0;
  static const attachGridMax = 120.0;
  static const attachGridColumns = 3;
  static const attachGap = 6.0;
  static const attachCardWidth = 220.0;
  static const attachBadge = 22.0;
  static const attachCacheWidth = 240;
  static const sheetOptionHeight = 52.0;
  static const attachCountHeight = 18.0;
  static const previewControlsHeight = 56.0;
  static const previewPlayButton = 44.0;
  static const previewAudioIcon = 72.0;
  static const previewTranscriptMax = 220.0;
  static const previewSeekThumb = 6.0;
  static const previewSeekTrack = 2.0;
  static const previewSearchHeight = 40.0;
  static const previewPdfMaxScale = 6.0;
}

/// Unit boundaries for compact number and time formatting.
abstract final class AppUnits {
  static const thousand = 1000;
  static const million = 1000000;
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const copiedFeedback = Duration(milliseconds: 1500);
  static const streamThrottle = Duration(milliseconds: 40);
  static const kbPoll = Duration(seconds: 2);
  static const usageTimeout = Duration(seconds: 10);
  static const streamIdle = Duration(seconds: 45);
  static const streamTick = Duration(milliseconds: 600);
  static const kbRequestTimeout = Duration(seconds: 20);
  static const diagramTimeout = Duration(seconds: 10);

  /// Saving may also name the chat with a model, so it gets longer.
  static const conversationTimeout = Duration(seconds: 40);
  static const mergeTimeout = Duration(seconds: 60);
  static const imageFade = Duration(milliseconds: 200);
  static const iconFetchTimeout = Duration(seconds: 8);
  static const searchDebounce = Duration(milliseconds: 300);
}

/// Fork and merge UI.
abstract final class LineageSizes {
  /// Collapsed briefing height before SHOW SUMMARY.
  static const summaryPeek = 96.0;
  static const chipMaxWidth = 200.0;
  static const pickerHeightFactor = 0.7;
  static const progress = 16.0;
}

/// Round Table panel and header.
abstract final class TableSizes {
  static const statusDot = 6.0;
  static const statusIcon = 14.0;
  static const draftPeekLines = 4;
  static const summaryLines = 1;
  static const pulse = Duration(milliseconds: 900);
  static const pulseMinOpacity = 0.25;
}
