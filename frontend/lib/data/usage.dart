int? _int(Object? v) => v is num ? v.toInt() : null;

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

/// Health of one provider as reported by the server. Unknown values map to
/// [unknown] so a newer backend never breaks the screen.
enum ProviderStatus {
  ok,
  limited,
  exhausted,
  missing,
  unknown;

  static ProviderStatus parse(Object? v) =>
      ProviderStatus.values.where((s) => s.name == v).firstOrNull ?? unknown;
}

/// Window a quota counts over.
enum QuotaPeriod {
  minute,
  day,
  month,
  unknown;

  static QuotaPeriod parse(Object? v) =>
      QuotaPeriod.values.where((s) => s.name == v).firstOrNull ?? unknown;
}

class ProviderQuota {
  const ProviderQuota({
    this.period = QuotaPeriod.unknown,
    this.used,
    this.limit,
    this.remaining,
    this.resetsAt,
    this.official = false,
    this.perModel = false,
    this.rolling = false,
  });

  final QuotaPeriod period;
  final int? used, limit, remaining;
  final DateTime? resetsAt;

  /// True when the number comes from the provider, false when counted by us.
  final bool official;
  final bool perModel, rolling;

  /// 0..1, or null when no limit is known (never invent one).
  double? get fraction {
    final l = limit;
    final u = used ?? (remaining != null && l != null ? l - remaining! : null);
    if (l == null || l <= 0 || u == null) return null;
    return (u / l).clamp(0.0, 1.0);
  }

  factory ProviderQuota.fromJson(Map<String, dynamic> j) => ProviderQuota(
    period: QuotaPeriod.parse(j['period']),
    used: _int(j['used']),
    limit: _int(j['limit']),
    remaining: _int(j['remaining']),
    resetsAt: _date(j['resetsAt']),
    official: j['source'] == 'official',
    perModel: j['perModel'] == true,
    rolling: j['rolling'] == true,
  );
}

/// One published plan limit, e.g. "Requests per day": 1000 per model.
class PlanLimit {
  const PlanLimit({required this.label, this.value, this.perModel = false});

  final String label;

  /// Null when the provider does not publish a number.
  final int? value;
  final bool perModel;

  static PlanLimit? parse(Object? v) {
    if (v is! Map) return null;
    final j = _map(v);
    final label = _str(j['label']);
    if (label == null) return null;
    return PlanLimit(
      label: label,
      value: _int(j['value']),
      perModel: j['scope'] == 'model',
    );
  }
}

/// Expected daily totals across the models we route to.
class Capacity {
  const Capacity({this.requestsPerDay, this.tokensPerDay});

  final int? requestsPerDay, tokensPerDay;

  factory Capacity.fromJson(Object? v) {
    final j = _map(v);
    return Capacity(
      requestsPerDay: _int(j['requestsPerDay']),
      tokensPerDay: _int(j['tokensPerDay']),
    );
  }
}

/// Live tokens-per-minute window reported by the provider.
class TokensWindow {
  const TokensWindow({this.limit, this.remaining});

  final int? limit, remaining;

  double? get usedFraction {
    final l = limit, r = remaining;
    if (l == null || l <= 0 || r == null) return null;
    return ((l - r) / l).clamp(0.0, 1.0);
  }

  static TokensWindow? parse(Object? v) {
    if (v is! Map) return null;
    final j = _map(v);
    return TokensWindow(
      limit: _int(j['limit']),
      remaining: _int(j['remaining']),
    );
  }
}

class RequestTotals {
  const RequestTotals({this.requests, this.tokens, this.failures});

  final int? requests, tokens, failures;

  factory RequestTotals.fromJson(Object? v) {
    final j = _map(v);
    return RequestTotals(
      requests: _int(j['requests']),
      tokens: _int(j['tokens']),
      failures: _int(j['failures']),
    );
  }
}

class ProviderUsage {
  const ProviderUsage({
    required this.id,
    required this.name,
    this.configured = false,
    this.keyHint,
    this.status = ProviderStatus.unknown,
    this.plan,
    this.models = const [],
    this.coolingModels = 0,
    this.quota,
    this.today = const RequestTotals(),
    this.month = const RequestTotals(),
    this.lastLimitHitAt,
    this.limits = const [],
    this.limitsSource,
    this.capacity = const Capacity(),
    this.tokensWindow,
  });

  final String id, name;
  final bool configured;

  /// Masked key from the server, e.g. `gsk_…uBwv`. Never the full key.
  final String? keyHint;
  final ProviderStatus status;
  final String? plan;
  final List<String> models;
  final int coolingModels;
  final ProviderQuota? quota;
  final RequestTotals today, month;
  final DateTime? lastLimitHitAt;
  final List<PlanLimit> limits;
  final String? limitsSource;
  final Capacity capacity;
  final TokensWindow? tokensWindow;

  /// Configured and able to serve requests right now.
  bool get active =>
      configured &&
      (status == ProviderStatus.ok || status == ProviderStatus.limited);

  factory ProviderUsage.fromJson(Map<String, dynamic> j) {
    final id = _str(j['id']) ?? '';
    return ProviderUsage(
      id: id,
      name: _str(j['name']) ?? id.toUpperCase(),
      configured: j['configured'] == true,
      keyHint: _str(j['keyHint']),
      status: ProviderStatus.parse(j['status']),
      plan: _str(j['plan']),
      models: [
        for (final m in (j['models'] is List ? j['models'] as List : const []))
          if (m is String) m,
      ],
      coolingModels: _int(j['coolingModels']) ?? 0,
      quota: j['quota'] is Map
          ? ProviderQuota.fromJson(_map(j['quota']))
          : null,
      today: RequestTotals.fromJson(j['today']),
      month: RequestTotals.fromJson(j['month']),
      lastLimitHitAt: _date(j['lastLimitHitAt']),
      limits: [
        for (final l in (j['limits'] is List ? j['limits'] as List : const []))
          ?PlanLimit.parse(l),
      ],
      limitsSource: _str(j['limitsSource']),
      capacity: Capacity.fromJson(j['capacity']),
      tokensWindow: TokensWindow.parse(j['tokensWindow']),
    );
  }
}

class GithubService {
  const GithubService({
    this.configured = false,
    this.keyHint,
    this.purpose,
    this.login,
    this.limit,
    this.remaining,
    this.resetsAt,
    this.error,
    this.limitLabel,
  });

  final bool configured;
  final String? keyHint, purpose, login, error, limitLabel;
  final int? limit, remaining;
  final DateTime? resetsAt;

  double? get usedFraction {
    final l = limit, r = remaining;
    if (l == null || l <= 0 || r == null) return null;
    return ((l - r) / l).clamp(0.0, 1.0);
  }

  factory GithubService.fromJson(Map<String, dynamic> j) => GithubService(
    configured: j['configured'] == true,
    keyHint: _str(j['keyHint']),
    purpose: _str(j['purpose']),
    login: _str(j['login']),
    limit: _int(j['limit']),
    remaining: _int(j['remaining']),
    resetsAt: _date(j['resetsAt']),
    error: _str(j['error']),
    limitLabel: _str(j['limitLabel']),
  );
}

class EmbeddingsService {
  const EmbeddingsService({
    this.provider,
    this.model,
    this.dimensions,
    this.requestsToday,
    this.textsToday,
    this.limitLabel,
  });

  final String? provider, model, limitLabel;
  final int? dimensions, requestsToday, textsToday;

  factory EmbeddingsService.fromJson(Map<String, dynamic> j) {
    final today = _map(j['today']);
    return EmbeddingsService(
      provider: _str(j['provider']),
      model: _str(j['model']),
      dimensions: _int(j['dimensions']),
      requestsToday: _int(today['requests']),
      textsToday: _int(today['texts']),
      limitLabel: _str(j['limitLabel']),
    );
  }
}

class SearchService {
  const SearchService({this.provider, this.today, this.month, this.limitLabel});

  final String? provider, limitLabel;
  final int? today, month;

  factory SearchService.fromJson(Map<String, dynamic> j) => SearchService(
    provider: _str(j['provider']),
    today: _int(j['today']),
    month: _int(j['month']),
    limitLabel: _str(j['limitLabel']),
  );
}

class KbStats {
  const KbStats({this.sources, this.chunks});

  final int? sources, chunks;

  factory KbStats.fromJson(Map<String, dynamic> j) =>
      KbStats(sources: _int(j['sources']), chunks: _int(j['chunks']));
}

/// Server-computed totals across providers.
class UsageTotals {
  const UsageTotals({
    this.requestsToday,
    this.tokensToday,
    this.knownDailyRequests,
    this.uncappedProviders = const [],
  });

  final int? requestsToday, tokensToday, knownDailyRequests;

  /// Providers with no published daily cap.
  final List<String> uncappedProviders;

  factory UsageTotals.fromJson(Object? v) {
    final j = _map(v);
    return UsageTotals(
      requestsToday: _int(j['requestsToday']),
      tokensToday: _int(j['tokensToday']),
      knownDailyRequests: _int(j['knownDailyRequests']),
      uncappedProviders: [
        for (final n
            in (j['uncappedProviders'] is List
                ? j['uncappedProviders'] as List
                : const []))
          if (n is String) n,
      ],
    );
  }
}

/// Parsed GET /usage. Every part may be missing.
class UsageSnapshot {
  const UsageSnapshot({
    this.providers = const [],
    this.github,
    this.embeddings,
    this.search,
    this.kb,
    this.totals = const UsageTotals(),
  });

  final UsageTotals totals;
  final List<ProviderUsage> providers;
  final GithubService? github;
  final EmbeddingsService? embeddings;
  final SearchService? search;
  final KbStats? kb;

  int get activeProviders => providers.where((p) => p.active).length;

  int get requestsToday =>
      totals.requestsToday ??
      providers.fold(0, (sum, p) => sum + (p.today.requests ?? 0));

  int get tokensToday =>
      totals.tokensToday ??
      providers.fold(0, (sum, p) => sum + (p.today.tokens ?? 0));

  /// Providers that have hit their quota.
  List<ProviderUsage> get atLimit =>
      providers.where((p) => p.status == ProviderStatus.exhausted).toList();

  factory UsageSnapshot.fromJson(Map<String, dynamic> j) {
    final s = _map(j['services']);
    return UsageSnapshot(
      totals: UsageTotals.fromJson(j['totals']),
      providers: [
        for (final p in (j['providers'] is List ? j['providers'] as List : []))
          if (p is Map) ProviderUsage.fromJson(_map(p)),
      ],
      github: s['github'] is Map
          ? GithubService.fromJson(_map(s['github']))
          : null,
      embeddings: s['embeddings'] is Map
          ? EmbeddingsService.fromJson(_map(s['embeddings']))
          : null,
      search: s['search'] is Map
          ? SearchService.fromJson(_map(s['search']))
          : null,
      kb: s['kb'] is Map ? KbStats.fromJson(_map(s['kb'])) : null,
    );
  }
}

/// Result of GET /health. [status] is null when the server is unreachable.
class HealthStatus {
  const HealthStatus(this.status, {this.db, this.embeddings});

  final String? status, db, embeddings;

  bool get online => status != null;
  bool get ok => status == 'ok';

  factory HealthStatus.fromJson(Map<String, dynamic> j) => HealthStatus(
    _str(j['status']) ?? 'ok',
    db: _str(j['db']),
    embeddings: _str(j['embeddings']),
  );
}
