import { AsyncLocalStorage } from "node:async_hooks";
import { EventEmitter } from "node:events";
import { db, isDbUp, Prisma } from "./prisma.js";
import { currentUser } from "../auth/context.js";
import { activeUserKey } from "../keys/store.js";

export type UsageKind = "chat" | "embed" | "search" | "fetch" | "transcribe" | "github" | "turn";
type Event = {
  provider: "ollama" | "openrouter" | "groq" | "nvidia" | "github" | "web";
  model?: string;
  kind: UsageKind;
  ok: boolean;
  status?: number;
  latencyMs?: number;
  count?: number;
  promptTokens?: number | null;
  completionTokens?: number | null;
  /** Overrides the ambient purpose (see withTelemetry). */
  purpose?: string;
  errorCode?: string;
  errorMessage?: string;
  ttftMs?: number | null;
  attempt?: number;
  /** Whose provider key paid for the call. Default: the caller's own key if a chat call used one, else the server. */
  keySource?: "user" | "server";
};

/** A recorded event as the telemetry API returns it. */
export type TelemetryEvent = {
  id: string;
  ts: string;
  provider: string;
  model: string | null;
  kind: string;
  purpose: string;
  ok: boolean;
  status: number | null;
  errorCode: string | null;
  errorMessage: string | null;
  latencyMs: number | null;
  ttftMs: number | null;
  count: number;
  promptTokens: number | null;
  completionTokens: number | null;
  attempt: number | null;
  userId: string | null;
  requestId: string | null;
  conversationId: string | null;
  keySource?: "user" | "server" | null;
};

// ---- ambient context ---------------------------------------------------------

/** Upstream calls made while serving one chat turn (see recordTurnSummary). */
export type TurnCounters = { llmCalls: number; auxLlmCalls: number; embedCalls: number; searches: number; fetches: number; promptTokens: number; completionTokens: number };
export const newTurnCounters = (): TurnCounters => ({ llmCalls: 0, auxLlmCalls: 0, embedCalls: 0, searches: 0, fetches: 0, promptTokens: 0, completionTokens: 0 });

/** Purposes of the calls that write the answer itself; every other chat call is auxiliary. */
const MAIN_PURPOSES = new Set(["chat", "table-chair"]);

/** Adds one recorded event to a turn's counters. */
export function tally(t: TurnCounters, kind: UsageKind, purpose: string, promptTokens?: number | null, completionTokens?: number | null): void {
  if (kind === "chat") {
    t.llmCalls++;
    if (!MAIN_PURPOSES.has(purpose)) t.auxLlmCalls++;
    t.promptTokens += promptTokens ?? 0;
    t.completionTokens += completionTokens ?? 0;
  } else if (kind === "embed") t.embedCalls++;
  else if (kind === "search") t.searches++;
  else if (kind === "fetch") t.fetches++;
}

type Ctx = { purpose?: string; requestId?: string; conversationId?: string; turn?: TurnCounters };
const ctx = new AsyncLocalStorage<Ctx>();

/** Runs [fn] with extra telemetry context (purpose, request/conversation id) for every event it records. */
export function withTelemetry<T>(patch: Ctx, fn: () => T): T {
  return ctx.run({ ...ctx.getStore(), ...patch }, fn);
}

/** Express middleware: one telemetry scope per request, with a fresh request id. */
export function telemetryScope(_req: unknown, _res: unknown, next: () => void): void {
  ctx.run({ requestId: Math.random().toString(36).slice(2, 10) }, next);
}

/** Updates the current request's scope in place (e.g. the chat route's own request id). */
export function setTelemetry(patch: Ctx): void {
  const s = ctx.getStore();
  if (s) Object.assign(s, patch);
}

// Keys, bearer tokens and long hex/base64 runs never reach the table.
export function scrub(msg: string | undefined | null): string | null {
  if (!msg) return null;
  return msg
    .replace(/(bearer|authorization|api[_-]?key|access[_-]?token|secret|password)([\s:=]+)\S+/gi, "$1$2[redacted]")
    .replace(/\b(sk|gsk|nvapi|ghp|gho|github_pat|or)[-_][A-Za-z0-9_-]{8,}/g, "[redacted]")
    .replace(/[A-Za-z0-9_\-]{32,}/g, "[redacted]")
    // Upstream errors sometimes quote the request ("invalid input: \"<user text>\""): long quoted runs are user content, not telemetry.
    .replace(/"[^"]{24,}"|'[^']{24,}'|`[^`]{24,}`/g, "[quoted text removed]")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 300);
}

// ---- recording ---------------------------------------------------------------

type Row = Omit<TelemetryEvent, "id" | "ts"> & { ts: Date };

/** New events after they are stored (or kept in memory when the DB is down). */
export const usageEvents = new EventEmitter();
usageEvents.setMaxListeners(50);

// In-memory events since boot: fallback when the DB is down.
const mem: Array<Event & { ts: number }> = [];
const memRows: TelemetryEvent[] = [];
let memSeq = 0;

const FLUSH_MS = 750;
const FLUSH_MAX = 100;
let queue: Row[] = [];
let timer: NodeJS.Timeout | null = null;

export function recordUsage(e: Event): void {
  const keySource = e.keySource ?? (e.kind === "chat" && activeUserKey(e.provider) ? "user" : "server");
  mem.push({ ...e, keySource, ts: Date.now() });
  if (mem.length > 5000) mem.splice(0, mem.length - 5000);
  const c = ctx.getStore();
  const user = currentUser();
  const purpose = e.purpose ?? c?.purpose ?? defaultPurpose(e.kind);
  if (c?.turn) tally(c.turn, e.kind, purpose, e.promptTokens, e.completionTokens);
  const row: Row = {
    ts: new Date(),
    provider: e.provider,
    model: e.model ?? null,
    kind: e.kind,
    purpose,
    ok: e.ok,
    status: e.status ?? null,
    errorCode: e.ok ? null : (e.errorCode ?? errorCodeFor(e.status, e.errorMessage)).slice(0, 40),
    errorMessage: e.ok ? null : scrub(e.errorMessage),
    latencyMs: e.latencyMs ?? null,
    ttftMs: e.ttftMs ?? null,
    count: e.count ?? 1,
    promptTokens: e.promptTokens ?? null,
    completionTokens: e.completionTokens ?? null,
    attempt: e.attempt ?? null,
    userId: user?.id ?? null,
    requestId: c?.requestId ?? null,
    conversationId: c?.conversationId ?? null,
    keySource,
  };
  queue.push(row);
  if (queue.length >= FLUSH_MAX) void flush();
  else timer ??= setTimeout(() => void flush(), FLUSH_MS);
}

export type TurnSummary = TurnCounters & { msToFirstToken: number | null; totalMs: number };

/**
 * One log line per chat turn with the number of upstream calls it made, plus a
 * "turn-summary" usage row (count = auxiliary calls: LLM calls other than the
 * answer, embeddings, searches and page fetches; ttft = ms to first token) so
 * the owner can chart calls per turn next to the per-call events.
 */
export function recordTurnSummary(s: TurnSummary, logLine: (msg: string, meta: object) => void): void {
  const aux = s.auxLlmCalls + s.embedCalls + s.searches + s.fetches;
  logLine("turn cost", { ...s, auxCalls: aux });
  recordUsage({ provider: "web", model: "turn", kind: "turn", ok: true, latencyMs: s.totalMs, ttftMs: s.msToFirstToken, count: aux });
}

/** A short machine code for a failed upstream call: http_429, timeout, empty, network. */
export function errorCodeFor(status: number | undefined, message: string | undefined): string {
  if (status) return `http_${status}`;
  const m = (message ?? "").toLowerCase();
  if (/timeout|timed out|first byte|idle/.test(m)) return "timeout";
  if (/empty/.test(m)) return "empty";
  if (/abort/.test(m)) return "aborted";
  return "network";
}

function defaultPurpose(kind: UsageKind): string {
  return { chat: "chat", embed: "embedding", search: "web-search", fetch: "web-fetch", transcribe: "transcribe", github: "github", turn: "turn-summary" }[kind];
}

/** Writes the queued events in one insert, off the request path. */
export async function flush(): Promise<void> {
  if (timer) clearTimeout(timer);
  timer = null;
  const batch = queue;
  queue = [];
  if (batch.length === 0) return;
  let stored: TelemetryEvent[];
  try {
    if (!isDbUp()) throw new Error("db down");
    const rows = await db().usageEvent.createManyAndReturn({ data: batch, select: { id: true, ts: true } });
    stored = batch.map((r, i) => ({ ...r, id: String(rows[i]?.id ?? `m${++memSeq}`), ts: (rows[i]?.ts ?? r.ts).toISOString() }));
  } catch {
    stored = batch.map((r) => ({ ...r, id: `m${++memSeq}`, ts: r.ts.toISOString() }));
    memRows.push(...stored);
    if (memRows.length > 2000) memRows.splice(0, memRows.length - 2000);
  }
  for (const ev of stored) usageEvents.emit("event", ev);
}

/** Events kept in memory while the database was down (newest last). */
export function memoryEvents(): TelemetryEvent[] {
  return memRows;
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
    if (e.keySource === 'user') continue;
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
         FROM usage_events WHERE provider='ollama' AND kind='chat' AND key_source IS DISTINCT FROM 'user' AND ts >= ${MONTH_START}`,
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
      if (e.kind !== "chat" || e.ts < month || e.keySource === 'user') continue;
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
     FROM usage_events WHERE kind='chat' AND key_source IS DISTINCT FROM 'user' AND ts >= ${MONTH_START} GROUP BY provider`;
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
