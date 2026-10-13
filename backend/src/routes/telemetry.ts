import { Router } from "express";
import { z } from "zod";
import { requireOwner } from "../auth/context.js";
import { db, isDbUp } from "../db/prisma.js";
import { memoryEvents, usageEvents, type TelemetryEvent } from "../db/usage.js";
import { MODELS, cooldownUntil } from "../models.js";
import { rateSnapshots } from "../usage/rateLimits.js";
import { quotaSnapshot } from "../llm/quota.js";
import { AppError } from "../util/errors.js";
import { openSse } from "../util/sse.js";
import { BUCKETS, WINDOWS, bucketFor, events, overview, timeseries, type Bucket, type Filters, type Window } from "../telemetry/queries.js";

/** Owner-only telemetry: every model call, minute by minute. Mounted at /admin/telemetry. */
export const telemetryRouter = Router();
telemetryRouter.use(requireOwner);

const windowSchema = z.enum(Object.keys(WINDOWS) as [Window, ...Window[]]).default("24h");
const filterSchema = {
  model: z.string().max(200).optional(),
  provider: z.string().max(40).optional(),
  kind: z.string().max(40).optional(),
  user: z.string().uuid().optional(),
};
const toFilters = (q: { model?: string; provider?: string; kind?: string; user?: string; ok?: boolean }): Filters => ({
  model: q.model || undefined,
  provider: q.provider || undefined,
  kind: q.kind || undefined,
  userId: q.user || undefined,
  ok: q.ok,
});

function needDb() {
  if (!isDbUp()) throw new AppError(503, "unavailable", "Database unavailable", true);
}

telemetryRouter.get("/overview", async (req, res) => {
  const q = z.object({ window: windowSchema, ...filterSchema }).parse(req.query);
  needDb();
  const data = await overview(db(), q.window, toFilters(q));

  // Every registry model appears, used or not, with its live router state.
  const now = Date.now();
  const byId = new Map(data.models.map((m) => [`${m.provider}:${m.model}`, m]));
  const live = (id: string) => {
    const until = cooldownUntil(id);
    const snap = rateSnapshots(id).find(([k]) => k === id)?.[1] ?? null;
    return { cooldownUntil: until ? new Date(until).toISOString() : null, cooldownMs: until ? until - now : 0, rateLimit: snap };
  };
  const registry = MODELS.map((m) => ({ id: m.id, name: m.name, inRegistry: true, ...live(m.id) }));
  const models = [
    ...MODELS.filter((m) => !q.provider || m.provider === q.provider)
      .filter((m) => !q.model || m.id.slice(m.provider.length + 1) === q.model)
      .filter(() => !q.kind && !q.user)
      .filter((m) => !byId.has(m.id))
      .map((m) => ({ ...emptyModel(m.provider, m.id.slice(m.provider.length + 1)) })),
    ...data.models,
  ]
    .map((m) => {
      const id = `${m.provider}:${m.model ?? ""}`;
      const reg = registry.find((r) => r.id === id);
      return { ...m, id, name: reg?.name ?? m.model ?? "(no model)", inRegistry: !!reg, ...live(id) };
    })
    .sort((a, b) => b.requests - a.requests || a.id.localeCompare(b.id));

  // Exhausted provider/model quotas, e.g. "Ollama: quota exhausted until 1 Nov".
  res.json({ ...data, models, quota: quotaSnapshot() });
});

function emptyModel(provider: string, model: string) {
  return {
    provider,
    model,
    requests: 0,
    ok: 0,
    failed: 0,
    unknown: 0,
    failureRate: 0,
    kinds: [] as string[],
    tokensIn: 0,
    tokensOut: 0,
    units: 0,
    latencyAvg: null,
    latencyP50: null,
    latencyP95: null,
    ttftAvg: null,
    ttftP50: null,
    lastAt: null,
    failuresByCode: {},
    lastError: null,
  };
}

telemetryRouter.get("/timeseries", async (req, res) => {
  const q = z
    .object({ window: windowSchema, bucket: z.enum(Object.keys(BUCKETS) as [Bucket, ...Bucket[]]).optional(), ...filterSchema })
    .parse(req.query);
  needDb();
  res.json(await timeseries(db(), q.window, bucketFor(q.window, q.bucket), toFilters(q)));
});

const boolParam = z.enum(["true", "false"]).transform((v) => v === "true");

telemetryRouter.get("/events", async (req, res) => {
  const q = z
    .object({
      limit: z.coerce.number().int().min(1).max(500).default(100),
      before: z.string().regex(/^\d{1,19}$/).optional(),
      ok: boolParam.optional(),
      ...filterSchema,
    })
    .parse(req.query);
  const f = toFilters(q);
  if (!isDbUp()) {
    // Database down: whatever this process kept in memory.
    const list = memoryEvents()
      .filter((e) => (f.model ? e.model === f.model : true) && (f.provider ? e.provider === f.provider : true) && (f.kind ? e.purpose === f.kind || e.kind === f.kind : true) && (f.ok === undefined ? true : e.ok === f.ok))
      .slice(-q.limit)
      .reverse()
      .map((e) => ({ ...e, userEmail: null }));
    res.json({ events: list, nextBefore: null, degraded: true });
    return;
  }
  res.json(await events(db(), q.limit, q.before ? BigInt(q.before) : null, f));
});

// Emails for live events, so the stream shows who triggered a call.
const emails = new Map<string, string | null>();
async function emailOf(id: string | null): Promise<string | null> {
  if (!id) return null;
  if (emails.has(id)) return emails.get(id)!;
  const u = isDbUp() ? await db().user.findUnique({ where: { id }, select: { email: true } }).catch(() => null) : null;
  if (emails.size > 500) emails.clear();
  emails.set(id, u?.email ?? null);
  return u?.email ?? null;
}

/** Pushes each new event as it is stored (`event: usage`). */
telemetryRouter.get("/stream", (req, res) => {
  const sse = openSse(res);
  sse.send("hello", { at: new Date().toISOString() });
  const onEvent = (e: TelemetryEvent) => {
    void emailOf(e.userId).then((userEmail) => sse.send("usage", { ...e, userEmail }));
  };
  usageEvents.on("event", onEvent);
  req.on("close", () => {
    usageEvents.off("event", onEvent);
    sse.end();
  });
});
