/// Strings, sizes and limits for the structure widgets (compare, progress,
/// tree) and the sortable table.
abstract final class StructLang {
  static const compare = 'compare';
  static const progress = 'progress';
  static const tree = 'tree';
}

abstract final class StructStrings {
  static const compare = 'COMPARE';
  static const progress = 'PROGRESS';
  static const tree = 'TREE';
  static const pick = 'BEST PICK';
  static const expandAll = 'EXPAND ALL';
  static const collapseAll = 'COLLAPSE';
  static const galleryTitle = 'Widget gallery';
}

abstract final class StructLimits {
  static const options = 5;
  static const points = 8;
  static const bars = 16;
  static const treeNodes = 80;
  static const treeDepth = 6;
  static const ratingMax = 10;
  static const sortableMinRows = 3;
}

abstract final class StructSizes {
  static const pad = 12.0;
  static const gap = 8.0;
  static const barHeight = 10.0;
  static const barSegments = 24;
  static const barGap = 2.0;
  static const ratingDot = 10.0;
  static const ratingGap = 4.0;
  static const valueWidth = 56.0;
  static const treeIndent = 18.0;
  static const treeRowHeight = 34.0;
  static const treeDot = 5.0;
  static const treeStroke = 1.0;
  static const markSize = 14.0;
  static const pickBorder = 1.5;
  static const sortIcon = 12.0;
}
