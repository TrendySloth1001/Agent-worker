import { Prisma } from "../db/prisma.js";
import type { Db, Tx } from "../db/prisma.js";
import type { TelemetryEvent } from "../db/usage.js";

/**
 * Owner telemetry over usage_events: totals, breakdowns, bucketed series and
 * the raw event log. Every query takes the client so tests can run it inside
 * a rolled-back transaction. "kind" in this API is the purpose label
 * (title, table-draft, web-search, ...), falling back to the raw kind column.
 */

export type Client = Db | Tx;

export const WINDOWS = { "1h": "1 hour", "24h": "24 hours", "7d": "7 days", "30d": "30 days" } as const;
export type Window = keyof typeof WINDOWS;
export const BUCKETS = { "1m": "1 minute", "5m": "5 minutes", "1h": "1 hour" } as const;
export type Bucket = keyof typeof BUCKETS;
const BUCKET_SECONDS: Record<Bucket, number> = { "1m": 60, "5m": 300, "1h": 3600 };
const WINDOW_SECONDS: Record<Window, number> = { "1h": 3600, "24h": 86_400, "7d": 604_800, "30d": 2_592_000 };
const MAX_POINTS = 1500;

export type Filters = { model?: string; provider?: string; kind?: string; ok?: boolean; userId?: string };

const LABEL = Prisma.sql`coalesce(purpose, kind)`;
// Older rows stored some models with their provider prefix ("groq:openai/gpt-oss-20b").
const MODEL = Prisma.sql`(CASE WHEN model LIKE provider || ':%' THEN substr(model, length(provider) + 2) ELSE model END)`;
const TOKENS = Prisma.sql`coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)`;

function conditions(f: Filters): Prisma.Sql[] {
  const c: Prisma.Sql[] = [];
  if (f.model) c.push(Prisma.sql`${MODEL} = ${f.model}`);
  if (f.provider) c.push(Prisma.sql`provider = ${f.provider}`);
  if (f.kind) c.push(Prisma.sql`(${LABEL} = ${f.kind} OR kind = ${f.kind})`);
  if (f.ok !== undefined) c.push(Prisma.sql`ok = ${f.ok}`);
  if (f.userId) c.push(Prisma.sql`user_id = ${f.userId}::uuid`);
  return c;
}

function whereWindow(w: Window, f: Filters): Prisma.Sql {
  return Prisma.join([Prisma.sql`ts >= now() - ${WINDOWS[w]}::interval`, ...conditions(f)], " AND ");
}

/** The finest bucket that keeps the series under MAX_POINTS. */
export function bucketFor(w: Window, wanted?: Bucket): Bucket {
  const order: Bucket[] = ["1m", "5m", "1h"];
  const def: Bucket = w === "1h" ? "1m" : w === "24h" ? "5m" : "1h";
  let b = wanted ?? def;
  while (WINDOW_SECONDS[w] / BUCKET_SECONDS[b] > MAX_POINTS && b !== "1h") b = order[order.indexOf(b) + 1];
  return b;
}

const n = (v: unknown): number => (v === null || v === undefined ? 0 : Number(v));
const nn = (v: unknown): number | null => (v === null || v === undefined ? null : Math.round(Number(v)));
const iso = (v: Date | null | undefined) => (v ? new Date(v).toISOString() : null);

// One aggregate row shape shared by totals and every breakdown.
const AGG = Prisma.sql`
  count(*)::int AS requests,
  count(*) FILTER (WHERE ok)::int AS ok,
  count(*) FILTER (WHERE NOT ok)::int AS failed,
  coalesce(sum(prompt_tokens),0)::bigint AS tokens_in,
  coalesce(sum(completion_tokens),0)::bigint AS tokens_out,
  coalesce(sum(count),0)::bigint AS units,
  avg(latency_ms) AS lat_avg,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_ms) AS lat_p50,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms) AS lat_p95,
  avg(ttft_ms) AS ttft_avg,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY ttft_ms) AS ttft_p50,
  max(ts) AS last_at`;

type AggRow = {
  requests: number;
  ok: number;
  failed: number;
  tokens_in: bigint;
  tokens_out: bigint;
  units: bigint;
  lat_avg: unknown;
  lat_p50: unknown;
  lat_p95: unknown;
  ttft_avg: unknown;
  ttft_p50: unknown;
  last_at: Date | null;
};

export type Agg = {
  requests: number;
  ok: number;
  failed: number;
  failureRate: number;
  tokensIn: number;
  tokensOut: number;
  /** Texts embedded etc. (the count column). */
  units: number;
  latencyAvg: number | null;
  latencyP50: number | null;
  latencyP95: number | null;
  ttftAvg: number | null;
  ttftP50: number | null;
  lastAt: string | null;
};

function agg(r: AggRow | undefined): Agg {
  const requests = n(r?.requests);
  const failed = n(r?.failed);
  return {
    requests,
    ok: n(r?.ok),
    failed,
    failureRate: requests ? Math.round((failed / requests) * 10_000) / 10_000 : 0,
    tokensIn: n(r?.tokens_in),
    tokensOut: n(r?.tokens_out),
    units: n(r?.units),
    latencyAvg: nn(r?.lat_avg),
    latencyP50: nn(r?.lat_p50),
    latencyP95: nn(r?.lat_p95),
    ttftAvg: nn(r?.ttft_avg),
    ttftP50: nn(r?.ttft_p50),
    lastAt: iso(r?.last_at),
  };
}

export type ModelAgg = Agg & {
  provider: string;
  model: string | null;
  failuresByCode: Record<string, number>;
  lastError: { at: string; code: string | null; status: number | null; message: string | null; kind: string } | null;
};

export type UserAgg = { userId: string | null; email: string | null; name: string | null; role: string | null; window: Agg; today: { requests: number; tokens: number; failed: number } };

export type Overview = {
  window: Window;
  generatedAt: string;
  totals: Agg;
  providers: Array<Agg & { provider: string }>;
  models: ModelAgg[];
  kinds: Array<Agg & { kind: string }>;
  users: UserAgg[];
  topErrors: Array<{ provider: string; model: string | null; code: string | null; message: string | null; count: number; lastAt: string }>;
};

export async function overview(c: Client, w: Window, f: Filters = {}): Promise<Overview> {
  const where = whereWindow(w, f);
  const [totals, providers, models, codes, lastErrors, kinds, users, today, errors] = await Promise.all([
    c.$queryRaw<AggRow[]>`SELECT ${AGG} FROM usage_events WHERE ${where}`,
    c.$queryRaw<Array<AggRow & { provider: string }>>`SELECT provider, ${AGG} FROM usage_events WHERE ${where} GROUP BY provider ORDER BY count(*) DESC`,
    c.$queryRaw<Array<AggRow & { provider: string; model: string | null }>>`
      SELECT provider, ${MODEL} AS model, ${AGG} FROM usage_events WHERE ${where} GROUP BY 1, 2 ORDER BY count(*) DESC`,
    c.$queryRaw<Array<{ provider: string; model: string | null; code: string; c: number }>>`
      SELECT provider, ${MODEL} AS model, coalesce(error_code, 'http_' || status, 'error') AS code, count(*)::int AS c
        FROM usage_events WHERE ${where} AND NOT ok GROUP BY 1, 2, 3`,
    c.$queryRaw<Array<{ provider: string; model: string | null; ts: Date; error_code: string | null; status: number | null; error_message: string | null; label: string }>>`
      SELECT DISTINCT ON (provider, ${MODEL}) provider, ${MODEL} AS model, ts, error_code, status, error_message, ${LABEL} AS label
        FROM usage_events WHERE ${where} AND NOT ok ORDER BY provider, ${MODEL}, ts DESC`,
    c.$queryRaw<Array<AggRow & { label: string }>>`SELECT ${LABEL} AS label, ${AGG} FROM usage_events WHERE ${where} GROUP BY 1 ORDER BY count(*) DESC`,
    c.$queryRaw<Array<AggRow & { user_id: string | null; email: string | null; name: string | null; role: string | null }>>`
      SELECT e.user_id, u.email::text AS email, u.name, u.role, ${AGG}
        FROM usage_events e LEFT JOIN users u ON u.id = e.user_id
       WHERE ${where} GROUP BY e.user_id, u.email, u.name, u.role ORDER BY count(*) DESC LIMIT 100`,
    c.$queryRaw<Array<{ user_id: string | null; r: number; t: bigint; f: number }>>`
      SELECT user_id, count(*)::int AS r, coalesce(sum(${TOKENS}),0)::bigint AS t, count(*) FILTER (WHERE NOT ok)::int AS f
        FROM usage_events
       WHERE ${Prisma.join([Prisma.sql`ts >= date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'`, ...conditions(f)], " AND ")}
       GROUP BY user_id`,
    c.$queryRaw<Array<{ provider: string; model: string | null; code: string | null; msg: string | null; c: number; last: Date }>>`
      SELECT provider, ${MODEL} AS model, coalesce(error_code, 'http_' || status, 'error') AS code, left(error_message, 160) AS msg, count(*)::int AS c, max(ts) AS last
        FROM usage_events WHERE ${where} AND NOT ok GROUP BY 1, 2, 3, 4 ORDER BY c DESC, last DESC LIMIT 20`,
  ]);

  const key = (p: string, m: string | null) => `${p}\u0000${m ?? ""}`;
  const codeMap = new Map<string, Record<string, number>>();
  for (const r of codes) {
    const k = key(r.provider, r.model);
    const m = codeMap.get(k) ?? {};
    m[r.code] = r.c;
    codeMap.set(k, m);
  }
  const lastMap = new Map(lastErrors.map((r) => [key(r.provider, r.model), r]));
  const todayMap = new Map(today.map((r) => [r.user_id ?? "", r]));

  return {
    window: w,
    generatedAt: new Date().toISOString(),
    totals: agg(totals[0]),
    providers: providers.map((r) => ({ provider: r.provider, ...agg(r) })),
    models: models.map((r) => {
      const le = lastMap.get(key(r.provider, r.model));
      return {
        provider: r.provider,
        model: r.model,
        ...agg(r),
        failuresByCode: codeMap.get(key(r.provider, r.model)) ?? {},
        lastError: le ? { at: iso(le.ts)!, code: le.error_code, status: le.status, message: le.error_message, kind: le.label } : null,
      };
    }),
    kinds: kinds.map((r) => ({ kind: r.label, ...agg(r) })),
    users: users.map((r) => {
      const t = todayMap.get(r.user_id ?? "");
      return { userId: r.user_id, email: r.email, name: r.name, role: r.role, window: agg(r), today: { requests: n(t?.r), tokens: n(t?.t), failed: n(t?.f) } };
    }),
    topErrors: errors.map((r) => ({ provider: r.provider, model: r.model, code: r.code, message: r.msg, count: r.c, lastAt: iso(r.last)! })),
  };
}

export type Point = { t: string; requests: number; failed: number; tokensIn: number; tokensOut: number; latencyP50: number | null; ttftP50: number | null };

/** Gap-filled bucket series (empty buckets are zeros) from now - window to now. */
export async function timeseries(c: Client, w: Window, b: Bucket, f: Filters = {}): Promise<{ window: Window; bucket: Bucket; points: Point[] }> {
  const step = BUCKETS[b];
  const where = whereWindow(w, f);
  const rows = await c.$queryRaw<Array<{ t: Date; r: number; f: number; ti: bigint; to: bigint; p50: unknown; tt: unknown }>>`
    WITH s AS (
      SELECT generate_series(
        date_bin(${step}::interval, now() - ${WINDOWS[w]}::interval, TIMESTAMPTZ '2000-01-01'),
        date_bin(${step}::interval, now(), TIMESTAMPTZ '2000-01-01'),
        ${step}::interval) AS t
    ), e AS (
      SELECT date_bin(${step}::interval, ts, TIMESTAMPTZ '2000-01-01') AS t,
             count(*)::int AS r,
             count(*) FILTER (WHERE NOT ok)::int AS f,
             coalesce(sum(prompt_tokens),0)::bigint AS ti,
             coalesce(sum(completion_tokens),0)::bigint AS "to",
             percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_ms) AS p50,
             percentile_cont(0.5) WITHIN GROUP (ORDER BY ttft_ms) AS tt
        FROM usage_events WHERE ${where} GROUP BY 1
    )
    SELECT s.t, coalesce(e.r,0)::int AS r, coalesce(e.f,0)::int AS f, coalesce(e.ti,0)::bigint AS ti, coalesce(e."to",0)::bigint AS "to", e.p50, e.tt
      FROM s LEFT JOIN e ON e.t = s.t ORDER BY s.t`;
  return {
    window: w,
    bucket: b,
    points: rows.map((r) => ({ t: iso(r.t)!, requests: n(r.r), failed: n(r.f), tokensIn: n(r.ti), tokensOut: n(r.to), latencyP50: nn(r.p50), ttftP50: nn(r.tt) })),
  };
}

type EventRow = {
  id: bigint;
  ts: Date;
  provider: string;
  model: string | null;
  kind: string;
  purpose: string | null;
  ok: boolean;
  status: number | null;
  error_code: string | null;
  error_message: string | null;
  latency_ms: number | null;
  ttft_ms: number | null;
  count: number;
  prompt_tokens: number | null;
  completion_tokens: number | null;
  attempt: number | null;
  user_id: string | null;
  request_id: string | null;
  conversation_id: string | null;
  email: string | null;
};

export type EventWithUser = TelemetryEvent & { userEmail: string | null };

/** Newest first; `before` is an event id cursor. */
export async function events(c: Client, limit: number, before: bigint | null, f: Filters = {}): Promise<{ events: EventWithUser[]; nextBefore: string | null }> {
  // The filter columns exist only on usage_events, so they need no alias.
  const where = Prisma.join([Prisma.sql`TRUE`, ...(before !== null ? [Prisma.sql`e.id < ${before}`] : []), ...conditions(f)], " AND ");
  const rows = await c.$queryRaw<EventRow[]>`
    SELECT e.id, e.ts, e.provider, ${MODEL} AS model, e.kind, e.purpose, e.ok, e.status, e.error_code, e.error_message, e.latency_ms, e.ttft_ms,
           e.count, e.prompt_tokens, e.completion_tokens, e.attempt, e.user_id, e.request_id, e.conversation_id, u.email::text AS email
      FROM usage_events e LEFT JOIN users u ON u.id = e.user_id
     WHERE ${where} ORDER BY e.id DESC LIMIT ${limit}`;
  const list = rows.map(toEvent);
  return { events: list, nextBefore: rows.length === limit ? list[list.length - 1].id : null };
}

function toEvent(r: EventRow): EventWithUser {
  return {
    id: String(r.id),
    ts: iso(r.ts)!,
    provider: r.provider,
    model: r.model,
    kind: r.kind,
    purpose: r.purpose ?? r.kind,
    ok: r.ok,
    status: r.status,
    errorCode: r.error_code,
    errorMessage: r.error_message,
    latencyMs: r.latency_ms,
    ttftMs: r.ttft_ms,
    count: r.count,
    promptTokens: r.prompt_tokens,
    completionTokens: r.completion_tokens,
    attempt: r.attempt,
    userId: r.user_id,
    requestId: r.request_id,
    conversationId: r.conversation_id,
    userEmail: r.email,
  };
}
