/// Owner telemetry payloads (`/admin/telemetry/*`). Parsing is lenient:
/// missing or mistyped fields become null/zero instead of throwing.
library;

int _i(Object? v) => v is num ? v.toInt() : 0;
int? _ni(Object? v) => v is num ? v.toInt() : null;
double _d(Object? v) => v is num ? v.toDouble() : 0;
String? _s(Object? v) => v is String ? v : null;
DateTime? _t(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _m(Object? v) =>
    v is Map<String, dynamic> ? v : const <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) => [
  if (v is List)
    for (final x in v)
      if (x is Map<String, dynamic>) x,
];

/// Counts, tokens and latency for one slice (total, provider, model, ...).
class TelemetryAgg {
  const TelemetryAgg({
    this.requests = 0,
    this.ok = 0,
    this.failed = 0,
    this.unknown = 0,
    this.failureRate = 0,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.units = 0,
    this.latencyAvg,
    this.latencyP50,
    this.latencyP95,
    this.ttftAvg,
    this.ttftP50,
    this.lastAt,
  });

  factory TelemetryAgg.fromJson(Map<String, dynamic> j) => TelemetryAgg(
    requests: _i(j['requests']),
    ok: _i(j['ok']),
    failed: _i(j['failed']),
    unknown: _i(j['unknown']),
    failureRate: _d(j['failureRate']),
    tokensIn: _i(j['tokensIn']),
    tokensOut: _i(j['tokensOut']),
    units: _i(j['units']),
    latencyAvg: _ni(j['latencyAvg']),
    latencyP50: _ni(j['latencyP50']),
    latencyP95: _ni(j['latencyP95']),
    ttftAvg: _ni(j['ttftAvg']),
    ttftP50: _ni(j['ttftP50']),
    lastAt: _t(j['lastAt']),
  );

  /// [unknown]: legacy rows with ok=false but neither a status nor an error.
  final int requests, ok, failed, unknown, tokensIn, tokensOut, units;
  final double failureRate;
  final int? latencyAvg, latencyP50, latencyP95, ttftAvg, ttftP50;
  final DateTime? lastAt;

  int get tokens => tokensIn + tokensOut;
}

class TelemetryLastError {
  const TelemetryLastError({
    required this.at,
    this.code,
    this.status,
    this.message,
    this.kind,
  });

  static TelemetryLastError? fromJson(Object? raw) {
    final j = _m(raw);
    final at = _t(j['at']);
    if (at == null) return null;
    return TelemetryLastError(
      at: at,
      code: _s(j['code']),
      status: _ni(j['status']),
      message: _s(j['message']),
      kind: _s(j['kind']),
    );
  }

  final DateTime at;
  final String? code, message, kind;
  final int? status;
}

/// Latest provider rate-limit headers for a model (Groq reports them).
class TelemetryRateLimit {
  const TelemetryRateLimit({
    this.limitRequests,
    this.remainingRequests,
    this.limitTokens,
    this.remainingTokens,
    this.resetsAt,
  });

  static TelemetryRateLimit? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return TelemetryRateLimit(
      limitRequests: _ni(raw['limitRequests']),
      remainingRequests: _ni(raw['remainingRequests']),
      limitTokens: _ni(raw['limitTokens']),
      remainingTokens: _ni(raw['remainingTokens']),
      resetsAt: _t(raw['resetsAt']),
    );
  }

  final int? limitRequests, remainingRequests, limitTokens, remainingTokens;
  final DateTime? resetsAt;
}

class ModelTelemetry {
  ModelTelemetry({
    required this.id,
    required this.provider,
    required this.model,
    required this.name,
    required this.agg,
    required this.failuresByCode,
    required this.inRegistry,
    this.kinds = const [],
    this.lastError,
    this.cooldownEnds,
    this.rateLimit,
  });

  factory ModelTelemetry.fromJson(Map<String, dynamic> j, DateTime fetchedAt) {
    final ms = _i(j['cooldownMs']);
    return ModelTelemetry(
      id: _s(j['id']) ?? '',
      provider: _s(j['provider']) ?? '',
      model: _s(j['model']),
      name: _s(j['name']) ?? _s(j['model']) ?? '',
      agg: TelemetryAgg.fromJson(j),
      failuresByCode: {
        for (final e in _m(j['failuresByCode']).entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      },
      inRegistry: j['inRegistry'] == true,
      kinds: [
        if (j['kinds'] is List)
          for (final k in j['kinds'] as List)
            if (k is String) k,
      ],
      lastError: TelemetryLastError.fromJson(j['lastError']),
      // Server clock may differ: anchor the countdown to the local fetch time.
      cooldownEnds: ms > 0 ? fetchedAt.add(Duration(milliseconds: ms)) : null,
      rateLimit: TelemetryRateLimit.fromJson(j['rateLimit']),
    );
  }

  final String id, provider, name;
  final String? model;
  final TelemetryAgg agg;
  final Map<String, int> failuresByCode;
  final bool inRegistry;

  /// Raw call kinds seen (search, fetch, ...): names model-less rows.
  final List<String> kinds;
  final TelemetryLastError? lastError;
  final DateTime? cooldownEnds;
  final TelemetryRateLimit? rateLimit;

  Duration? cooldownLeft(DateTime now) {
    final end = cooldownEnds;
    if (end == null || !end.isAfter(now)) return null;
    return end.difference(now);
  }
}

class NamedAgg {
  const NamedAgg(this.name, this.agg, [this.spark = const []]);
  final String name;
  final TelemetryAgg agg;

  /// Requests per bucket across the window (providers only).
  final List<double> spark;
}

/// Chat turns: how many extra calls a message costs and how fast it starts.
class TurnTelemetry {
  const TurnTelemetry({
    required this.turns,
    required this.auxCalls,
    required this.auxAvg,
    required this.auxMax,
    this.ttftAvg,
    this.ttftP50,
    this.latencyP50,
  });

  static TurnTelemetry? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final turns = _i(raw['turns']);
    if (turns == 0) return null;
    return TurnTelemetry(
      turns: turns,
      auxCalls: _i(raw['auxCalls']),
      auxAvg: _d(raw['auxAvg']),
      auxMax: _i(raw['auxMax']),
      ttftAvg: _ni(raw['ttftAvg']),
      ttftP50: _ni(raw['ttftP50']),
      latencyP50: _ni(raw['latencyP50']),
    );
  }

  final int turns, auxCalls, auxMax;
  final double auxAvg;
  final int? ttftAvg, ttftP50, latencyP50;
}

class UserTelemetry {
  const UserTelemetry({
    this.userId,
    this.email,
    this.name,
    this.role,
    required this.window,
    required this.todayRequests,
    required this.todayTokens,
    required this.todayFailed,
  });

  factory UserTelemetry.fromJson(Map<String, dynamic> j) {
    final today = _m(j['today']);
    return UserTelemetry(
      userId: _s(j['userId']),
      email: _s(j['email']),
      name: _s(j['name']),
      role: _s(j['role']),
      window: TelemetryAgg.fromJson(_m(j['window'])),
      todayRequests: _i(today['requests']),
      todayTokens: _i(today['tokens']),
      todayFailed: _i(today['failed']),
    );
  }

  final String? userId, email, name, role;
  final TelemetryAgg window;
  final int todayRequests, todayTokens, todayFailed;
}

class TopError {
  const TopError({
    required this.provider,
    this.model,
    this.code,
    this.message,
    required this.count,
    this.lastAt,
  });

  factory TopError.fromJson(Map<String, dynamic> j) => TopError(
    provider: _s(j['provider']) ?? '',
    model: _s(j['model']),
    code: _s(j['code']),
    message: _s(j['message']),
    count: _i(j['count']),
    lastAt: _t(j['lastAt']),
  );

  final String provider;
  final String? model, code, message;
  final int count;
  final DateTime? lastAt;
}

/// One budget scope (a model, or a whole provider account): this minute and today.
class BudgetScope {
  const BudgetScope({
    required this.scope,
    required this.minuteRequests,
    required this.minuteTokens,
    required this.dayRequests,
    required this.dayTokens,
    this.rpm,
    this.tpm,
    this.rpd,
    this.tpd,
  });

  factory BudgetScope.fromJson(Map<String, dynamic> j) {
    final m = _m(j['minute']);
    final d = _m(j['day']);
    return BudgetScope(
      scope: _s(j['scope']) ?? '',
      minuteRequests: _i(m['requests']),
      minuteTokens: _i(m['tokens']),
      dayRequests: _i(d['requests']),
      dayTokens: _i(d['tokens']),
      rpm: _ni(m['rpm']),
      tpm: _ni(m['tpm']),
      rpd: _ni(d['rpd']),
      tpd: _ni(d['tpd']),
    );
  }

  final String scope;
  final int minuteRequests, minuteTokens, dayRequests, dayTokens;
  final int? rpm, tpm, rpd, tpd;
}

/// Live provider budgets: use per scope plus how often the server skipped,
/// waited, deferred aux work or capped a user instead of collecting a 429.
class TelemetryBudgets {
  const TelemetryBudgets({
    required this.scopes,
    required this.skips,
    required this.waits,
    required this.auxDeferred,
    required this.auxCacheHits,
    required this.userCaps,
  });

  static int _sum(Object? v) => v is Map
      ? v.values.fold<int>(0, (n, x) => n + (x is num ? x.toInt() : 0))
      : 0;

  static TelemetryBudgets? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return TelemetryBudgets(
      scopes: [for (final s in _l(raw['scopes'])) BudgetScope.fromJson(s)],
      skips: _l(raw['skips']).fold<int>(0, (n, s) => n + _i(s['count'])),
      waits: _i(_m(raw['waits'])['count']),
      auxDeferred: _sum(raw['auxDeferred']),
      auxCacheHits: _sum(raw['auxCacheHits']),
      userCaps: _sum(raw['userCaps']),
    );
  }

  final List<BudgetScope> scopes;
  final int skips, waits, auxDeferred, auxCacheHits, userCaps;
}

class TelemetryOverview {
  const TelemetryOverview({
    required this.window,
    required this.totals,
    required this.providers,
    required this.models,
    required this.kinds,
    required this.users,
    required this.topErrors,
    this.turns,
    this.budgets,
  });

  factory TelemetryOverview.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    return TelemetryOverview(
      window: _s(j['window']) ?? '',
      totals: TelemetryAgg.fromJson(_m(j['totals'])),
      providers: [
        for (final p in _l(j['providers']))
          NamedAgg(_s(p['provider']) ?? '', TelemetryAgg.fromJson(p), [
            if (p['spark'] is List)
              for (final v in p['spark'] as List)
                if (v is num) v.toDouble(),
          ]),
      ],
      models: [
        for (final m in _l(j['models'])) ModelTelemetry.fromJson(m, now),
      ],
      kinds: [
        for (final k in _l(j['kinds']))
          NamedAgg(_s(k['kind']) ?? '', TelemetryAgg.fromJson(k)),
      ],
      users: [for (final u in _l(j['users'])) UserTelemetry.fromJson(u)],
      topErrors: [for (final e in _l(j['topErrors'])) TopError.fromJson(e)],
      turns: TurnTelemetry.fromJson(j['turns']),
      budgets: TelemetryBudgets.fromJson(j['budgets']),
    );
  }

  final String window;
  final TelemetryAgg totals;
  final List<NamedAgg> providers, kinds;
  final List<ModelTelemetry> models;
  final List<UserTelemetry> users;
  final List<TopError> topErrors;
  final TurnTelemetry? turns;
  final TelemetryBudgets? budgets;
}

class SeriesPoint {
  const SeriesPoint({
    required this.t,
    required this.requests,
    required this.failed,
    required this.tokensIn,
    required this.tokensOut,
    this.latencyP50,
    this.ttftP50,
  });

  factory SeriesPoint.fromJson(Map<String, dynamic> j) => SeriesPoint(
    t: _t(j['t']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    requests: _i(j['requests']),
    failed: _i(j['failed']),
    tokensIn: _i(j['tokensIn']),
    tokensOut: _i(j['tokensOut']),
    latencyP50: _ni(j['latencyP50']),
    ttftP50: _ni(j['ttftP50']),
  );

  final DateTime t;
  final int requests, failed, tokensIn, tokensOut;
  final int? latencyP50, ttftP50;
}

class TelemetrySeries {
  const TelemetrySeries({required this.bucket, required this.points});

  factory TelemetrySeries.fromJson(Map<String, dynamic> j) => TelemetrySeries(
    bucket: _s(j['bucket']) ?? '',
    points: [for (final p in _l(j['points'])) SeriesPoint.fromJson(p)],
  );

  final String bucket;
  final List<SeriesPoint> points;
}

/// One recorded call: the minute-to-minute log.
class TelemetryEvent {
  const TelemetryEvent({
    required this.id,
    required this.ts,
    required this.provider,
    this.model,
    required this.kind,
    required this.purpose,
    required this.ok,
    this.status,
    this.errorCode,
    this.errorMessage,
    this.latencyMs,
    this.ttftMs,
    this.count = 1,
    this.promptTokens,
    this.completionTokens,
    this.attempt,
    this.userId,
    this.userEmail,
    this.requestId,
    this.conversationId,
  });

  factory TelemetryEvent.fromJson(Map<String, dynamic> j) => TelemetryEvent(
    id: '${j['id'] ?? ''}',
    ts: _t(j['ts']) ?? DateTime.now(),
    provider: _s(j['provider']) ?? '',
    model: _s(j['model']),
    kind: _s(j['kind']) ?? '',
    purpose: _s(j['purpose']) ?? _s(j['kind']) ?? '',
    ok: j['ok'] == true,
    status: _ni(j['status']),
    errorCode: _s(j['errorCode']),
    errorMessage: _s(j['errorMessage']),
    latencyMs: _ni(j['latencyMs']),
    ttftMs: _ni(j['ttftMs']),
    count: _ni(j['count']) ?? 1,
    promptTokens: _ni(j['promptTokens']),
    completionTokens: _ni(j['completionTokens']),
    attempt: _ni(j['attempt']),
    userId: _s(j['userId']),
    userEmail: _s(j['userEmail']),
    requestId: _s(j['requestId']),
    conversationId: _s(j['conversationId']),
  );

  final String id, provider, kind, purpose;
  final DateTime ts;
  final String? model, errorCode, errorMessage, userId, userEmail;
  final String? requestId, conversationId;
  final bool ok;
  final int? status, latencyMs, ttftMs, promptTokens, completionTokens;
  final int? attempt;
  final int count;

  int get tokens => (promptTokens ?? 0) + (completionTokens ?? 0);

  /// Failed only with a status >= 400 or an error code; ok=false without
  /// either is a legacy row of unknown outcome.
  bool get failed => (status ?? 0) >= 400 || errorCode != null;
  bool get unknown => !ok && !failed;

  /// Numeric id for ordering; events kept in memory server-side have none.
  int get order => int.tryParse(id) ?? 0;
}

class EventsPage {
  const EventsPage(this.events, this.nextBefore);

  factory EventsPage.fromJson(Map<String, dynamic> j) => EventsPage([
    for (final e in _l(j['events'])) TelemetryEvent.fromJson(e),
  ], _s(j['nextBefore']));

  final List<TelemetryEvent> events;
  final String? nextBefore;
}
