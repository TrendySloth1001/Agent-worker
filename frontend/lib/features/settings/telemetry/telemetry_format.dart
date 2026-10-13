import '../../../core/constants/app_strings.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/constants/telemetry.dart';
import '../../../data/telemetry.dart';
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

/// A budget scope: "groq:openai/gpt-oss-120b" -> "Groq gpt-oss-120b", "nvidia" -> "NVIDIA".
String budgetScopeLabel(String scope) {
  final i = scope.indexOf(':');
  if (i < 0) return providerLabel(scope);
  final model = scope.substring(i + 1);
  return '${providerLabel(scope.substring(0, i))} ${model.split('/').last}';
}

String _of(int used, int? limit) =>
    limit == null ? compact(used) : '${compact(used)}/${compact(limit)}';

/// "3/30 req · 2.1K/8K tok min · 120/1K today".
String budgetLine(BudgetScope s) {
  final minute = [
    '${_of(s.minuteRequests, s.rpm)} ${TelemetryCopy.budgetReq}',
    if (s.tpm != null || s.minuteTokens > 0)
      '${_of(s.minuteTokens, s.tpm)} ${TelemetryCopy.budgetTok}',
  ].join(' · ');
  return '$minute ${TelemetryCopy.budgetMinute} · ${_of(s.dayRequests, s.rpd)} ${TelemetryCopy.budgetToday}';
}

/// Display name of a provider id: groq -> Groq, nvidia -> NVIDIA.
String providerLabel(String id) =>
    TelemetryStrings.providerNames[id] ??
    (id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}');

/// Purpose labels arrive kebab-cased: table-draft -> Table draft.
String kindLabel(String k) {
  final s = k.replaceAll('-', ' ');
  return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// 5m, 2h, 3d: a short span in lower case.
String shortSpan(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d';
  if (d.inHours >= 1) return '${d.inHours}h';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes}m';
}

/// 5m ago.
String agoShort(DateTime at, DateTime now) {
  final d = now.difference(at);
  return '${shortSpan(d.isNegative ? Duration.zero : d)} ${TelemetryCopy.ago}';
}
