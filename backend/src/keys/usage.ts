import { db, isDbUp, Prisma } from "../db/prisma.js";
import { memoryEvents, type TelemetryEvent } from "../db/usage.js";

/**
 * A user's own usage on THEIR keys: chat calls recorded with key_source = 'user'
 * for that user. Nothing here ever reads another user's or the server's rows.
 */

export const USAGE_DAYS = [7, 30] as const;

/** One (day, provider, model) bucket. */
export type UsageRow = { day: string; provider: string; model: string; requests: number; errors: number; promptTokens: number; completionTokens: number; latencySumMs: number; latencyCount: number };

export type KeyUsage = {
  days: number;
  totals: { requests: number; errors: number; promptTokens: number; completionTokens: number; tokens: number; avgLatencyMs: number | null };
  byDay: Array<{ day: string; requests: number; tokens: number; errors: number }>;
  byProvider: Array<{ provider: string; requests: number; tokens: number; errors: number; avgLatencyMs: number | null }>;
  byModel: Array<{ provider: string; model: string; requests: number; tokens: number; errors: number; avgLatencyMs: number | null }>;
};

/** Whether [e] is a chat call the given user made on their own key. */
export const isUserKeyEvent = (e: Pick<TelemetryEvent, "userId" | "kind" | "keySource">, userId: string): boolean => e.userId === userId && e.keySource === "user" && e.kind === "chat";

const avg = (sum: number, n: number): number | null => (n > 0 ? Math.round(sum / n) : null);

/** Folds buckets into totals / per-day (every day of the window present) / per-provider / per-model. */
export function aggregateKeyUsage(rows: UsageRow[], days: number, now = new Date()): KeyUsage {
  const out: KeyUsage = { days, totals: { requests: 0, errors: 0, promptTokens: 0, completionTokens: 0, tokens: 0, avgLatencyMs: null }, byDay: [], byProvider: [], byModel: [] };
  const byDay = new Map<string, { requests: number; tokens: number; errors: number }>();
  for (let i = days - 1; i >= 0; i--) byDay.set(new Date(now.getTime() - i * 86_400_000).toISOString().slice(0, 10), { requests: 0, tokens: 0, errors: 0 });
  const prov = new Map<string, { requests: number; tokens: number; errors: number; ls: number; ln: number }>();
  const model = new Map<string, { provider: string; model: string; requests: number; tokens: number; errors: number; ls: number; ln: number }>();
  let ls = 0;
  let ln = 0;
  for (const r of rows) {
    const tokens = r.promptTokens + r.completionTokens;
    out.totals.requests += r.requests;
    out.totals.errors += r.errors;
    out.totals.promptTokens += r.promptTokens;
    out.totals.completionTokens += r.completionTokens;
    ls += r.latencySumMs;
    ln += r.latencyCount;
    const d = byDay.get(r.day);
    if (d) {
      d.requests += r.requests;
      d.tokens += tokens;
      d.errors += r.errors;
    }
    const p = prov.get(r.provider) ?? { requests: 0, tokens: 0, errors: 0, ls: 0, ln: 0 };
    Object.assign(p, { requests: p.requests + r.requests, tokens: p.tokens + tokens, errors: p.errors + r.errors, ls: p.ls + r.latencySumMs, ln: p.ln + r.latencyCount });
    prov.set(r.provider, p);
    const mk = `${r.provider}:${r.model}`;
    const m = model.get(mk) ?? { provider: r.provider, model: r.model, requests: 0, tokens: 0, errors: 0, ls: 0, ln: 0 };
    Object.assign(m, { requests: m.requests + r.requests, tokens: m.tokens + tokens, errors: m.errors + r.errors, ls: m.ls + r.latencySumMs, ln: m.ln + r.latencyCount });
    model.set(mk, m);
  }
  out.totals.tokens = out.totals.promptTokens + out.totals.completionTokens;
  out.totals.avgLatencyMs = avg(ls, ln);
  out.byDay = [...byDay].map(([day, v]) => ({ day, ...v }));
  out.byProvider = [...prov].map(([provider, v]) => ({ provider, requests: v.requests, tokens: v.tokens, errors: v.errors, avgLatencyMs: avg(v.ls, v.ln) })).sort((a, b) => b.requests - a.requests);
  out.byModel = [...model.values()].map((v) => ({ provider: v.provider, model: v.model, requests: v.requests, tokens: v.tokens, errors: v.errors, avgLatencyMs: avg(v.ls, v.ln) })).sort((a, b) => b.requests - a.requests);
  return out;
}

/** Buckets in-memory events (used while the database is down). */
export function bucketEvents(events: TelemetryEvent[], userId: string, since: Date): UsageRow[] {
  const map = new Map<string, UsageRow>();
  for (const e of events) {
    if (!isUserKeyEvent(e, userId) || new Date(e.ts) < since) continue;
    const day = e.ts.slice(0, 10);
    const k = `${day}|${e.provider}|${e.model ?? ""}`;
    const r = map.get(k) ?? { day, provider: e.provider, model: e.model ?? "", requests: 0, errors: 0, promptTokens: 0, completionTokens: 0, latencySumMs: 0, latencyCount: 0 };
    r.requests++;
    if (!e.ok) r.errors++;
    r.promptTokens += e.promptTokens ?? 0;
    r.completionTokens += e.completionTokens ?? 0;
    if (e.latencyMs !== null) {
      r.latencySumMs += e.latencyMs;
      r.latencyCount++;
    }
    map.set(k, r);
  }
  return [...map.values()];
}

/** The caller's own key usage over the last [days] days (UTC). */
export async function userKeyUsage(userId: string, days: number): Promise<KeyUsage> {
  const now = new Date();
  const since = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - (days - 1)));
  if (!isDbUp()) return aggregateKeyUsage(bucketEvents(memoryEvents(), userId, since), days, now);
  type R = { day: string; provider: string; model: string | null; requests: number; errors: number; pt: bigint; ct: bigint; ls: bigint; ln: number };
  const rows = await db().$queryRaw<R[]>(Prisma.sql`
    SELECT to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day, provider, model,
           count(*)::int AS requests,
           count(*) FILTER (WHERE NOT ok)::int AS errors,
           coalesce(sum(prompt_tokens),0)::bigint AS pt,
           coalesce(sum(completion_tokens),0)::bigint AS ct,
           coalesce(sum(latency_ms) FILTER (WHERE latency_ms IS NOT NULL),0)::bigint AS ls,
           count(latency_ms)::int AS ln
      FROM usage_events
     WHERE user_id = ${userId}::uuid AND key_source = 'user' AND kind = 'chat' AND ts >= ${since}
     GROUP BY 1, 2, 3`);
  return aggregateKeyUsage(
    rows.map((r) => ({ day: r.day, provider: r.provider, model: r.model ?? "", requests: r.requests, errors: r.errors, promptTokens: Number(r.pt), completionTokens: Number(r.ct), latencySumMs: Number(r.ls), latencyCount: r.ln })),
    days,
    now,
  );
}
