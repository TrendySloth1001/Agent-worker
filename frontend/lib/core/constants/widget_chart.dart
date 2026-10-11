import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Strings for the chart widget.
abstract final class ChartStrings {
  static const title = 'CHART';
  static const table = 'TABLE';
  static const chart = 'CHART';
  static const copyData = 'COPY DATA';
  static const fullscreen = 'EXPAND';
  static const total = 'TOTAL';
  static const hint = 'TAP A POINT FOR ITS VALUE';
  static const hintPie = 'TAP A SLICE';
  static const hiddenAll = 'ALL SERIES HIDDEN, TAP A LEGEND ITEM';
  static const seriesDefault = 'Series';
  static const xHeader = 'X';
  static const yHeader = 'Y';
  static const other = 'Other';
  static const csvSeparator = ',';
  static const tooltipSeparator = ': ';
}

/// Sizes and limits for the chart widget.
abstract final class ChartSizes {
  static const captionFont = 10.0;
  static const centerFont = 26.0;
  static const rawFont = 12.0;
  static const maxSeries = 8;
  static const maxPoints = 60;
  static const maxSlices = 12;
  static const minRadarAxes = 3;

  static const height = 220.0;
  static const pieHeight = 210.0;
  static const radarHeight = 250.0;
  static const fullscreenMinHeight = 260.0;

  /// Left axis reserved width and bottom axis height.
  static const leftAxis = 42.0;
  static const bottomAxis = 26.0;

  /// Minimum horizontal room per category before the chart scrolls sideways.
  static const minSlot = 34.0;
  static const maxXLabels = 8;
  static const labelMaxChars = 8;

  static const lineWidth = 2.0;
  static const dotRadius = 3.0;
  static const scatterRadius = 5.0;
  static const barRadius = 2.0;
  static const barGroupSpace = 2.0;
  static const barMaxWidth = 22.0;
  static const areaAlpha = 0.15;
  static const gridAlpha = 0.6;
  static const sliceGap = 2.0;
  static const pieRadius = 70.0;
  static const pieSelectedExtra = 6.0;
  static const donutHole = 52.0;
  static const pieHoleSolid = 0.0;
  static const radarTicks = 4;
  static const radarFillAlpha = 0.12;

  static const legendDot = 8.0;
  static const legendHiddenAlpha = 0.35;
  static const tooltipPadH = 8.0;
  static const tooltipPadV = 4.0;
  static const readoutHeight = 18.0;
  static const tableCellPadH = 10.0;
  static const tableCellPadV = 6.0;
  static const tableMinColWidth = 72.0;
  static const yTicks = 4;
}

abstract final class ChartDurations {
  /// One-time grow-in when the chart first appears.
  static const intro = Duration(milliseconds: 600);
}

abstract final class ChartIcons {
  static const table = HugeIcons.strokeRoundedTable01;
  static const bar = HugeIcons.strokeRoundedChartColumn;
  static const line = HugeIcons.strokeRoundedChartLineData02;
  static const pie = HugeIcons.strokeRoundedPieChart;
  static const donut = HugeIcons.strokeRoundedChartRing;
  static const scatter = HugeIcons.strokeRoundedChartScatter;
  static const radar = HugeIcons.strokeRoundedChartRadar;
  static const fullscreen = AppIcons.fullscreen;
  static const back = AppIcons.back;
}
