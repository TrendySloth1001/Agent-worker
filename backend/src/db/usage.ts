import { isDbUp, query } from "./pool.js";

export type UsageKind = "chat" | "embed" | "search" | "fetch" | "transcribe";
type Event = {
  provider: "ollama" | "openrouter" | "groq" | "nvidia";
  model?: string;
  kind: UsageKind;
  ok: boolean;
  status?: number;
  latencyMs?: number;
  count?: number;
  promptTokens?: number | null;
  completionTokens?: number | null;
};

// In-memory counters since boot: fallback when the DB is down.
const mem: Array<Event & { ts: number }> = [];

export function recordUsage(e: Event): void {
  mem.push({ ...e, ts: Date.now() });
  if (mem.length > 5000) mem.splice(0, mem.length - 5000);
  if (!isDbUp()) return;
  query(
    `INSERT INTO usage_events (provider, model, kind, ok, status, latency_ms, count, prompt_tokens, completion_tokens)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [e.provider, e.model ?? null, e.kind, e.ok, e.status ?? null, e.latencyMs ?? null, e.count ?? 1, e.promptTokens ?? null, e.completionTokens ?? null],
  ).catch(() => {});
}

type Summary = {
  ollama: { todayRequests: number; todayTokens: number; monthRequests: number; monthTokens: number; lastLimitHitAt: string | null };
  embeddings: { todayRequests: number; todayTexts: number };
  search: { today: number; month: number };
};

function fromMemory(): Summary {
  const now = new Date();
  const day = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const month = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1);
  const s: Summary = {
    ollama: { todayRequests: 0, todayTokens: 0, monthRequests: 0, monthTokens: 0, lastLimitHitAt: null },
    embeddings: { todayRequests: 0, todayTexts: 0 },
    search: { today: 0, month: 0 },
  };
  for (const e of mem) {
    const tokens = (e.promptTokens ?? 0) + (e.completionTokens ?? 0);
    const today = e.ts >= day;
    const thisMonth = e.ts >= month;
    if (e.provider === "ollama" && e.kind === "chat") {
      if (thisMonth) (s.ollama.monthRequests++, (s.ollama.monthTokens += tokens));
      if (today) (s.ollama.todayRequests++, (s.ollama.todayTokens += tokens));
      if (e.status === 402 || e.status === 429) s.ollama.lastLimitHitAt = new Date(e.ts).toISOString();
    } else if (e.kind === "embed" && today) {
      s.embeddings.todayRequests++;
      s.embeddings.todayTexts += e.count ?? 1;
    } else if (e.kind === "search" || e.kind === "fetch") {
      if (thisMonth) s.search.month++;
      if (today) s.search.today++;
    }
  }
  return s;
}

export async function getUsageSummary(): Promise<Summary> {
  if (!isDbUp()) return fromMemory();
  try {
    const day = "date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'";
    const month = "date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'";
    const [o, e, s] = await Promise.all([
      query(
        `SELECT
           count(*) FILTER (WHERE ts >= ${day})::int AS tr,
           coalesce(sum(coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)) FILTER (WHERE ts >= ${day}),0)::bigint AS tt,
           count(*)::int AS mr,
           coalesce(sum(coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)),0)::bigint AS mt,
           max(ts) FILTER (WHERE status IN (402,429)) AS hit
         FROM usage_events WHERE provider='ollama' AND kind='chat' AND ts >= ${month}`,
      ),
      query(
        `SELECT count(*)::int AS r, coalesce(sum(count),0)::int AS t FROM usage_events WHERE kind='embed' AND ts >= ${day}`,
      ),
      query(
        `SELECT count(*) FILTER (WHERE ts >= ${day})::int AS d, count(*)::int AS m FROM usage_events WHERE kind IN ('search','fetch') AND ts >= ${month}`,
      ),
    ]);
    const o0 = o.rows[0];
    return {
      ollama: {
        todayRequests: o0.tr,
        todayTokens: Number(o0.tt),
        monthRequests: o0.mr,
        monthTokens: Number(o0.mt),
        lastLimitHitAt: o0.hit ? new Date(o0.hit).toISOString() : null,
      },
      embeddings: { todayRequests: e.rows[0].r, todayTexts: e.rows[0].t },
      search: { today: s.rows[0].d, month: s.rows[0].m },
    };
  } catch {
    return fromMemory();
  }
}

export type ProviderUsage = {
  todayRequests: number;
  todayTokens: number;
  monthRequests: number;
  monthTokens: number;
  todayFailures: number;
  lastLimitHitAt: string | null;
};

const emptyUsage = (): ProviderUsage => ({
  todayRequests: 0,
  todayTokens: 0,
  monthRequests: 0,
  monthTokens: 0,
  todayFailures: 0,
  lastLimitHitAt: null,
});

/** Chat requests this server sent to each provider, today and this month (UTC). */
export async function getProviderUsage(): Promise<Record<string, ProviderUsage>> {
  const out: Record<string, ProviderUsage> = {};
  const now = new Date();
  const day = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const month = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1);
  if (!isDbUp()) {
    for (const e of mem) {
      if (e.kind !== "chat" || e.ts < month) continue;
      const u = (out[e.provider] ??= emptyUsage());
      const tokens = (e.promptTokens ?? 0) + (e.completionTokens ?? 0);
      u.monthRequests++;
      u.monthTokens += tokens;
      if (e.ts >= day) {
        u.todayRequests++;
        u.todayTokens += tokens;
        if (!e.ok) u.todayFailures++;
      }
      if (e.status === 402 || e.status === 429) u.lastLimitHitAt = new Date(e.ts).toISOString();
    }
    return out;
  }
  const dayExpr = "date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'";
  const monthExpr = "date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'";
  const { rows } = await query(
    `SELECT provider,
       count(*) FILTER (WHERE ts >= ${dayExpr})::int AS tr,
       coalesce(sum(coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)) FILTER (WHERE ts >= ${dayExpr}),0)::bigint AS tt,
       count(*)::int AS mr,
       coalesce(sum(coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)),0)::bigint AS mt,
       count(*) FILTER (WHERE ts >= ${dayExpr} AND NOT ok)::int AS tf,
       max(ts) FILTER (WHERE status IN (402,429)) AS hit
     FROM usage_events WHERE kind='chat' AND ts >= ${monthExpr} GROUP BY provider`,
  );
  for (const r of rows) {
    out[r.provider] = {
      todayRequests: r.tr,
      todayTokens: Number(r.tt),
      monthRequests: r.mr,
      monthTokens: Number(r.mt),
      todayFailures: r.tf,
      lastLimitHitAt: r.hit ? new Date(r.hit).toISOString() : null,
    };
  }
  return out;
}
