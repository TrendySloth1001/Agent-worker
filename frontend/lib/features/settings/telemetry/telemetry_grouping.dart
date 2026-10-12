import '../../../core/constants/m3_copy.dart';
import '../../../data/telemetry.dart';
import 'telemetry_format.dart';

/// A model shown once, whichever providers served it. Model-less rows (web
/// search, page fetches, ...) are named by what they did.
class ModelGroup {
  ModelGroup({
    required this.key,
    required this.name,
    required this.parts,
    required this.agg,
  });

  final String key, name;
  final List<ModelTelemetry> parts;
  final TelemetryAgg agg;

  /// Providers that served it, busiest first.
  List<String> get providers => [
    for (final p in {for (final m in parts) m.provider}) p,
  ];

  Map<String, int> get failuresByCode {
    final out = <String, int>{};
    for (final m in parts) {
      m.failuresByCode.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }

  TelemetryLastError? get lastError {
    TelemetryLastError? best;
    for (final m in parts) {
      final e = m.lastError;
      if (e != null && (best == null || e.at.isAfter(best.at))) best = e;
    }
    return best;
  }

  /// Longest remaining cooldown among the providers, if any is cooling down.
  Duration? cooldownLeft(DateTime now) {
    Duration? best;
    for (final m in parts) {
      final left = m.cooldownLeft(now);
      if (left != null && (best == null || left > best)) best = left;
    }
    return best;
  }
}

/// Name for a row without a model, by the kinds of call it made.
String modelLessName(ModelTelemetry m) {
  final k = m.kinds;
  if (k.contains('search')) return TelemetryCopy.webSearch;
  if (k.contains('fetch')) return TelemetryCopy.pageFetch;
  if (k.contains('embed')) return TelemetryCopy.embeddings;
  if (k.contains('transcribe')) return TelemetryCopy.transcription;
  if (k.contains('github')) return TelemetryCopy.github;
  return TelemetryCopy.other;
}

/// Request-weighted mean of a per-model latency figure.
int? _weighted(
  Iterable<ModelTelemetry> parts,
  int? Function(TelemetryAgg) pick,
) {
  var sum = 0.0, weight = 0;
  for (final m in parts) {
    final v = pick(m.agg);
    if (v == null || m.agg.requests == 0) continue;
    sum += v * m.agg.requests;
    weight += m.agg.requests;
  }
  return weight == 0 ? null : (sum / weight).round();
}

TelemetryAgg mergeAgg(List<ModelTelemetry> parts) {
  var requests = 0, ok = 0, failed = 0, unknown = 0, ti = 0, to = 0, units = 0;
  DateTime? last;
  int? p95;
  for (final m in parts) {
    final a = m.agg;
    requests += a.requests;
    ok += a.ok;
    failed += a.failed;
    unknown += a.unknown;
    ti += a.tokensIn;
    to += a.tokensOut;
    units += a.units;
    if (a.lastAt != null && (last == null || a.lastAt!.isAfter(last))) {
      last = a.lastAt;
    }
    if (a.latencyP95 != null && (p95 == null || a.latencyP95! > p95)) {
      p95 = a.latencyP95;
    }
  }
  return TelemetryAgg(
    requests: requests,
    ok: ok,
    failed: failed,
    unknown: unknown,
    failureRate: requests == 0 ? 0 : failed / requests,
    tokensIn: ti,
    tokensOut: to,
    units: units,
    latencyAvg: _weighted(parts, (a) => a.latencyAvg),
    latencyP50: _weighted(parts, (a) => a.latencyP50),
    latencyP95: p95,
    ttftAvg: _weighted(parts, (a) => a.ttftAvg),
    ttftP50: _weighted(parts, (a) => a.ttftP50),
    lastAt: last,
  );
}

/// One group per model, busiest first. Models with no calls are dropped
/// (`hidden` counts them).
({List<ModelGroup> groups, int hidden}) groupModels(
  List<ModelTelemetry> models,
) {
  final byKey = <String, List<ModelTelemetry>>{};
  for (final m in models) {
    final key = m.model == null ? 'none:${modelLessName(m)}' : m.model!;
    byKey.putIfAbsent(key, () => []).add(m);
  }
  final groups = <ModelGroup>[];
  var hidden = 0;
  byKey.forEach((key, parts) {
    parts.sort((a, b) => b.agg.requests.compareTo(a.agg.requests));
    final agg = mergeAgg(parts);
    if (agg.requests == 0) {
      hidden++;
      return;
    }
    final first = parts.first;
    final name = first.model == null
        ? modelLessName(first)
        : parts
              .map((m) => m.name)
              .firstWhere((n) => n.isNotEmpty, orElse: () => key);
    groups.add(ModelGroup(key: key, name: name, parts: parts, agg: agg));
  });
  groups.sort((a, b) => b.agg.requests.compareTo(a.agg.requests));
  return (groups: groups, hidden: hidden);
}

/// Failures of one code on one model, with the distinct messages seen.
class ErrorGroup {
  ErrorGroup({required this.code, required this.model});

  final String code, model;
  int count = 0;
  DateTime? lastAt;
  final Map<String, int> messages = {};
}

List<ErrorGroup> groupErrors(List<TopError> errors) {
  final byKey = <String, ErrorGroup>{};
  for (final e in errors) {
    final code = e.code ?? 'error';
    final model = e.model ?? providerLabel(e.provider);
    final g = byKey.putIfAbsent(
      '$code\u0000$model',
      () => ErrorGroup(code: code, model: model),
    );
    g.count += e.count;
    final at = e.lastAt;
    if (at != null && (g.lastAt == null || at.isAfter(g.lastAt!))) {
      g.lastAt = at;
    }
    final msg = e.message;
    if (msg != null && msg.isNotEmpty) {
      g.messages[msg] = (g.messages[msg] ?? 0) + e.count;
    }
  }
  return byKey.values.toList()..sort((a, b) => b.count.compareTo(a.count));
}
