import '../../../core/constants/app_strings.dart';
import '../../../core/constants/telemetry.dart';
import '../format.dart';

const _msPerSecond = 1000;
const _percent = 100;

/// 340 -> 340MS, 1530 -> 1.5S, 21577 -> 22S.
String ms(int? v) {
  if (v == null) return AppStrings.dash;
  if (v < _msPerSecond) return '$v${TelemetryStrings.ms}';
  final s = v / _msPerSecond;
  return '${s >= 10 ? s.round() : s.toStringAsFixed(1)}${TelemetryStrings.seconds}';
}

/// 0.1091 -> 10.9%.
String pct(double rate) {
  final v = rate * _percent;
  final s = v == 0 || v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
  return '$s${TelemetryStrings.percent}';
}

String two(int v) => v.toString().padLeft(2, '0');

/// Local wall-clock time, 14:03:27.
String clock(DateTime t) => '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

/// Axis label: 14:03, or 10/11 for day-sized buckets.
String axisTime(DateTime t, String bucket) =>
    bucket == TelemetryBuckets.hour && t.hour == 0
    ? '${two(t.day)}/${two(t.month)}'
    : '${two(t.hour)}:${two(t.minute)}';

/// 3:07 for a cooldown countdown, 1H 2M once it is long.
String countdown(Duration d) {
  if (d.inHours >= 1) return span(d);
  return '${d.inMinutes}:${two(d.inSeconds % 60)}';
}

/// Tokens in / out: 1.2K / 340.
String inOut(int a, int b) =>
    '${compact(a)}${TelemetryStrings.slash}${compact(b)}';

/// Display name of a provider id.
String providerLabel(String id) => id.toUpperCase();

/// Purpose labels arrive kebab-cased: table-draft -> TABLE DRAFT.
String kindLabel(String k) => k.replaceAll('-', ' ').toUpperCase();
