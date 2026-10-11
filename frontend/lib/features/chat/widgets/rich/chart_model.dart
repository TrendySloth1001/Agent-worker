import 'dart:convert';
import 'dart:math' as math;

import '../../../../core/constants/widget_chart.dart';

enum ChartKind { bar, line, area, pie, donut, scatter, radar }

class ChartSeries {
  const ChartSeries(this.name, this.values, this.points);
  final String name;

  /// Category values (null = missing) for bar/line/area/radar/pie.
  final List<double?> values;

  /// Scatter points.
  final List<({double x, double y})> points;
}

class ChartSlice {
  const ChartSlice(this.label, this.value);
  final String label;
  final double value;
}

class ChartSpec {
  const ChartSpec({
    required this.kind,
    required this.title,
    required this.labels,
    required this.series,
    required this.slices,
    required this.unit,
    required this.xLabel,
    required this.yLabel,
  });

  final ChartKind kind;
  final String title;
  final List<String> labels;
  final List<ChartSeries> series;
  final List<ChartSlice> slices;
  final String unit;
  final String xLabel;
  final String yLabel;

  bool get isPie => kind == ChartKind.pie || kind == ChartKind.donut;
  bool get isScatter => kind == ChartKind.scatter;
  bool get isCartesian =>
      kind == ChartKind.bar || kind == ChartKind.line || kind == ChartKind.area;

  /// Parses [source]; returns null when it is not a drawable chart.
  static ChartSpec? parse(String source) {
    final map = _decode(source);
    if (map == null) return null;
    try {
      return _build(map);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decode(String source) {
    var s = source.trim();
    final a = s.indexOf('{');
    final b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    s = s.substring(a, b + 1);
    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      // Tolerate trailing commas.
      try {
        final fixed = s.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
        final v = jsonDecode(fixed);
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }
  }

  static double? _num(dynamic v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) {
      final d = double.tryParse(v.trim().replaceAll(',', ''));
      return d != null && d.isFinite ? d : null;
    }
    return null;
  }

  static String _str(dynamic v) => v == null ? '' : v.toString().trim();

  static ChartKind _kind(String t) => switch (t.toLowerCase().trim()) {
    'bar' || 'column' || 'columns' || 'histogram' => ChartKind.bar,
    'line' || 'spline' => ChartKind.line,
    'area' => ChartKind.area,
    'pie' => ChartKind.pie,
    'donut' || 'doughnut' || 'ring' => ChartKind.donut,
    'scatter' || 'xy' || 'bubble' => ChartKind.scatter,
    'radar' || 'spider' || 'polar' => ChartKind.radar,
    _ => ChartKind.bar,
  };

  static ChartSpec? _build(Map<String, dynamic> m) {
    final kind = _kind(_str(m['type']));
    final labels = <String>[
      if (m['x'] is List)
        for (final l in (m['x'] as List).take(ChartSizes.maxPoints)) _str(l),
    ];
    final rawSeries = m['series'] is List ? m['series'] as List : const [];
    final series = <ChartSeries>[];
    for (final s in rawSeries.take(ChartSizes.maxSeries)) {
      if (s is! Map) continue;
      final name = _str(s['name']).isEmpty
          ? '${ChartStrings.seriesDefault} ${series.length + 1}'
          : _str(s['name']);
      final values = <double?>[
        if (s['data'] is List)
          for (final v in (s['data'] as List).take(ChartSizes.maxPoints))
            _num(v),
      ];
      final points = <({double x, double y})>[];
      if (s['points'] is List) {
        for (final p in (s['points'] as List).take(ChartSizes.maxPoints)) {
          if (p is List && p.length >= 2) {
            final x = _num(p[0]);
            final y = _num(p[1]);
            if (x != null && y != null) points.add((x: x, y: y));
          } else if (p is Map) {
            final x = _num(p['x']);
            final y = _num(p['y']);
            if (x != null && y != null) points.add((x: x, y: y));
          }
        }
      } else if (kind == ChartKind.scatter && values.isNotEmpty) {
        // Data given as y values only: x is the index, or numeric labels.
        for (var i = 0; i < values.length; i++) {
          final y = values[i];
          if (y == null) continue;
          final lx = i < labels.length ? _num(labels[i]) : null;
          points.add((x: lx ?? i.toDouble(), y: y));
        }
      }
      series.add(ChartSeries(name, values, points));
    }
    if (series.isEmpty) return null;

    final slices = <ChartSlice>[];
    if (kind == ChartKind.pie || kind == ChartKind.donut) {
      final one = series.length == 1 && series.first.values.length > 1;
      if (one) {
        final v = series.first.values;
        for (var i = 0; i < v.length; i++) {
          final x = v[i];
          if (x == null || x <= 0) continue;
          slices.add(ChartSlice(i < labels.length ? labels[i] : '${i + 1}', x));
        }
      } else {
        for (final s in series) {
          final x = s.values.firstWhere((e) => e != null, orElse: () => null);
          if (x == null || x <= 0) continue;
          slices.add(ChartSlice(s.name, x));
        }
      }
      slices.sort((a, b) => b.value.compareTo(a.value));
      if (slices.length > ChartSizes.maxSlices) {
        final rest = slices.sublist(ChartSizes.maxSlices - 1);
        slices.removeRange(ChartSizes.maxSlices - 1, slices.length);
        slices.add(
          ChartSlice(
            ChartStrings.other,
            rest.fold<double>(0, (a, b) => a + b.value),
          ),
        );
      }
      if (slices.isEmpty) return null;
    } else if (kind == ChartKind.scatter) {
      if (!series.any((s) => s.points.isNotEmpty)) return null;
    } else {
      if (!series.any((s) => s.values.any((v) => v != null))) return null;
      if (kind == ChartKind.radar) {
        final n = series
            .map((s) => s.values.length)
            .reduce((a, b) => a > b ? a : b);
        if (n < ChartSizes.minRadarAxes) return null;
      }
    }

    return ChartSpec(
      kind: kind,
      title: _str(m['title']),
      labels: labels,
      series: series,
      slices: slices,
      unit: _str(m['unit']),
      xLabel: _str(m['xLabel'] ?? m['xlabel']),
      yLabel: _str(m['yLabel'] ?? m['ylabel']),
    );
  }

  /// Number of categories on the shared x axis.
  int get categoryCount {
    var n = labels.length;
    for (final s in series) {
      if (s.values.length > n) n = s.values.length;
    }
    return n;
  }

  String categoryLabel(int i) =>
      i < labels.length && labels[i].isNotEmpty ? labels[i] : '${i + 1}';

  /// CSV of the underlying data.
  String toCsv() {
    String q(String s) =>
        s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    final sep = ChartStrings.csvSeparator;
    final rows = <String>[];
    if (isPie) {
      rows.add(
        [
          q(xLabel.isEmpty ? ChartStrings.xHeader : xLabel),
          q(yLabel.isEmpty ? ChartStrings.yHeader : yLabel),
        ].join(sep),
      );
      for (final s in slices) {
        rows.add([q(s.label), fmtPlain(s.value)].join(sep));
      }
    } else if (isScatter) {
      rows.add(
        ['series', ChartStrings.xHeader, ChartStrings.yHeader].join(sep),
      );
      for (final s in series) {
        for (final p in s.points) {
          rows.add([q(s.name), fmtPlain(p.x), fmtPlain(p.y)].join(sep));
        }
      }
    } else {
      rows.add([q(xLabel), for (final s in series) q(s.name)].join(sep));
      for (var i = 0; i < categoryCount; i++) {
        rows.add(
          [
            q(categoryLabel(i)),
            for (final s in series)
              i < s.values.length && s.values[i] != null
                  ? fmtPlain(s.values[i]!)
                  : '',
          ].join(sep),
        );
      }
    }
    return rows.join('\n');
  }
}

/// 1234.5 -> "1234.5", 3.0 -> "3".
String fmtPlain(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  var s = v.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Compact axis number: 1200 -> "1.2K".
String fmtCompact(double v) {
  final a = v.abs();
  String t(double x) => fmtPlain(double.parse(x.toStringAsFixed(1)));
  if (a >= 1e9) return '${t(v / 1e9)}B';
  if (a >= 1e6) return '${t(v / 1e6)}M';
  if (a >= 1e4) return '${t(v / 1e3)}K';
  if (a >= 100) return fmtPlain(v.roundToDouble());
  return fmtPlain(double.parse(v.toStringAsFixed(2)));
}

/// Value with unit for tooltips. Currency-like units go in front.
String fmtWithUnit(double v, String unit) {
  final s = fmtGrouped(v);
  if (unit.isEmpty) return s;
  if (unit.length == 1 && !RegExp(r'[a-zA-Z%°]').hasMatch(unit)) {
    return '$unit$s';
  }
  return unit == '%' || unit == '°C' || unit == '°F' || unit == '°'
      ? '$s$unit'
      : '$s $unit';
}

String fmtGrouped(double v) {
  if (v.abs() >= 1000) {
    final neg = v < 0;
    final whole = v.abs().round().toString();
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    final frac = v.abs() - v.abs().truncateToDouble();
    final f = frac > 0.005
        ? fmtPlain(double.parse(frac.toStringAsFixed(2))).substring(1)
        : '';
    return '${neg ? '-' : ''}$b$f';
  }
  return fmtPlain(double.parse(v.toStringAsFixed(2)));
}

/// "Nice" axis range covering [lo]..[hi].
({double min, double max, double step}) niceScale(
  double lo,
  double hi, {
  bool zeroBase = true,
}) {
  if (zeroBase) {
    if (lo > 0) lo = 0; // bars/areas read best from zero
    if (hi < 0) hi = 0;
  }
  if (hi == lo) hi = lo + 1;
  final raw = (hi - lo) / ChartSizes.yTicks;
  final mag = _pow10((_log10(raw)).floor());
  final norm = raw / mag;
  final step =
      (norm <= 1
          ? 1
          : norm <= 2
          ? 2
          : norm <= 2.5
          ? 2.5
          : norm <= 5
          ? 5
          : 10) *
      mag;
  final min = (lo / step).floor() * step;
  final max = (hi / step).ceil() * step;
  return (min: min, max: max, step: step);
}

double _log10(double x) => x <= 0 ? 0 : math.log(x) / math.ln10;
double _pow10(int e) {
  var r = 1.0;
  if (e >= 0) {
    for (var i = 0; i < e; i++) {
      r *= 10;
    }
  } else {
    for (var i = 0; i < -e; i++) {
      r /= 10;
    }
  }
  return r;
}
