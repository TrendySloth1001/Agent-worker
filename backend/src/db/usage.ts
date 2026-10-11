import { db, isDbUp, Prisma } from "./prisma.js";

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
  try {
    db()
      .usageEvent.create({
        data: {
          provider: e.provider,
          model: e.model ?? null,
          kind: e.kind,
          ok: e.ok,
          status: e.status ?? null,
          latencyMs: e.latencyMs ?? null,
          count: e.count ?? 1,
          promptTokens: e.promptTokens ?? null,
          completionTokens: e.completionTokens ?? null,
        },
        select: { id: true },
      })
      .catch(() => {});
  } catch {
    /* database just went down */
  }
}

// Start of the current UTC day / month, as SQL fragments (no user input).
const DAY_START = Prisma.sql`date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'`;
const MONTH_START = Prisma.sql`date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'`;

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
    // Raw: single-pass FILTER aggregates over the UTC day/month.
    const [o, e, s] = await Promise.all([
      db().$queryRaw<Array<{ tr: number; tt: bigint; mr: number; mt: bigint; hit: Date | null }>>`
        SELECT
           count(*) FILTER (WHERE ts >= ${DAY_START})::int AS tr,
           coalesce(sum(coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)) FILTER (WHERE ts >= ${DAY_START}),0)::bigint AS tt,
           count(*)::int AS mr,
           coalesce(sum(coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)),0)::bigint AS mt,
           max(ts) FILTER (WHERE status IN (402,429)) AS hit
         FROM usage_events WHERE provider='ollama' AND kind='chat' AND ts >= ${MONTH_START}`,
      db().$queryRaw<Array<{ r: number; t: number }>>`
        SELECT count(*)::int AS r, coalesce(sum(count),0)::int AS t FROM usage_events WHERE kind='embed' AND ts >= ${DAY_START}`,
      db().$queryRaw<Array<{ d: number; m: number }>>`
        SELECT count(*) FILTER (WHERE ts >= ${DAY_START})::int AS d, count(*)::int AS m FROM usage_events WHERE kind IN ('search','fetch') AND ts >= ${MONTH_START}`,
    ]);
    const o0 = o[0];
    return {
      ollama: {
        todayRequests: o0.tr,
        todayTokens: Number(o0.tt),
        monthRequests: o0.mr,
        monthTokens: Number(o0.mt),
        lastLimitHitAt: o0.hit ? new Date(o0.hit).toISOString() : null,
      },
      embeddings: { todayRequests: e[0].r, todayTexts: e[0].t },
      search: { today: s[0].d, month: s[0].m },
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
  const rows = await db().$queryRaw<Array<{ provider: string; tr: number; tt: bigint; mr: number; mt: bigint; tf: number; hit: Date | null }>>`
    SELECT provider,
       count(*) FILTER (WHERE ts >= ${DAY_START})::int AS tr,
       coalesce(sum(coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)) FILTER (WHERE ts >= ${DAY_START}),0)::bigint AS tt,
       count(*)::int AS mr,
       coalesce(sum(coalesce(prompt_tokens,0)+coalesce(completion_tokens,0)),0)::bigint AS mt,
       count(*) FILTER (WHERE ts >= ${DAY_START} AND NOT ok)::int AS tf,
       max(ts) FILTER (WHERE status IN (402,429)) AS hit
     FROM usage_events WHERE kind='chat' AND ts >= ${MONTH_START} GROUP BY provider`;
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
