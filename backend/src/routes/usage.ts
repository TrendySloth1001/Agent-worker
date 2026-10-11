import { Router } from "express";
import { config } from "../config.js";
import { getProviderUsage, getUsageSummary, type ProviderUsage } from "../db/usage.js";
import { MODELS, cooldownUntil, type ProviderId } from "../models.js";
import { kbStats } from "../retrieval/search.js";
import { getGithubInfo } from "../usage/github.js";
import { keyHint } from "../usage/keyHint.js";
import { getOpenRouterKeyInfo } from "../usage/openrouterKey.js";
import { rateSnapshots } from "../usage/rateLimits.js";
import { limitsFor, usageFor } from "../auth/limits.js";

export const usageRouter = Router();

function nextUtcMidnight() {
  const d = new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1)).toISOString();
}

function nextUtcMonth() {
  const d = new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1)).toISOString();
}

type Quota = {
  /** What `used`/`limit` count. */
  unit: "requests";
  period: "day" | "month" | "minute";
  used: number | null;
  limit: number | null;
  remaining: number | null;
  resetsAt: string | null;
  /** official: the provider reported it; tracked: counted by this server. */
  source: "official" | "tracked";
  /** True when the limit applies to each model separately. */
  perModel: boolean;
  /** Refills continuously over the period instead of at a fixed time. */
  rolling?: boolean;
};

/** One published free-plan limit. `value` null means the provider does not publish it. */
type Limit = { label: string; value: number | null; unit: "requests" | "tokens" | "concurrent"; per: "minute" | "day" | "month" | "request"; scope: "account" | "model" };

type ProviderDef = {
  id: ProviderId;
  name: string;
  key: () => string | undefined;
  plan: string;
  limits: Limit[];
  /** Where the limits come from, shown under them. */
  limitsSource: string;
};

// Published free-plan limits (verified Sept/Oct 2026; Groq confirmed by its response headers).
const PROVIDERS: ProviderDef[] = [
  {
    id: "groq",
    name: "Groq",
    key: () => config.groqApiKey,
    plan: "Free tier, no card",
    limits: [
      { label: "Requests per day", value: 1000, unit: "requests", per: "day", scope: "model" },
      { label: "Requests per minute", value: 30, unit: "requests", per: "minute", scope: "model" },
      { label: "Tokens per minute", value: 8000, unit: "tokens", per: "minute", scope: "model" },
      { label: "Tokens per day", value: 200000, unit: "tokens", per: "day", scope: "model" },
    ],
    limitsSource: "Groq console, confirmed by live response headers",
  },
  {
    id: "nvidia",
    name: "NVIDIA",
    key: () => config.nvidiaApiKey,
    plan: "Developer program, free endpoints",
    limits: [
      { label: "Requests per minute", value: 40, unit: "requests", per: "minute", scope: "account" },
      { label: "Requests per day", value: null, unit: "requests", per: "day", scope: "account" },
    ],
    limitsSource: "build.nvidia.com, approximate; no daily cap published",
  },
  {
    id: "ollama",
    name: "Ollama Cloud",
    key: () => config.ollamaApiKey,
    plan: "Free plan, monthly credit",
    limits: [
      { label: "Requests at once", value: 1, unit: "concurrent", per: "request", scope: "account" },
      { label: "Monthly credit", value: null, unit: "requests", per: "month", scope: "account" },
    ],
    limitsSource: "ollama.com/pricing; credit amount is not published",
  },
  {
    id: "openrouter",
    name: "OpenRouter",
    key: () => config.openrouterApiKey,
    plan: "Free models, no credits bought",
    limits: [
      { label: "Requests per day", value: 50, unit: "requests", per: "day", scope: "account" },
      { label: "Requests per minute", value: 20, unit: "requests", per: "minute", scope: "account" },
    ],
    limitsSource: "OpenRouter docs; 1,000/day after a one-time $10 top-up",
  },
];

/** Expected daily capacity: per-model limits multiply by the models we route to. */
function capacity(p: ProviderDef, modelCount: number) {
  const daily = (unit: Limit["unit"]) => {
    const l = p.limits.find((x) => x.unit === unit && x.per === "day");
    if (!l || l.value === null) return null;
    return l.scope === "model" ? l.value * modelCount : l.value;
  };
  return { requestsPerDay: daily("requests"), tokensPerDay: daily("tokens") };
}

usageRouter.get("/", async (req, res) => {
  // Provider quotas and keys are the owner's business; other users see their own counts.
  const caller = req.user;
  const mine = caller ? await Promise.all([limitsFor(caller), usageFor(caller.id)]).catch(() => null) : null;
  const me = mine ? { limits: mine[0], usage: mine[1], resetsAt: nextUtcMidnight(), unlimited: mine[0] === null } : null;
  if (caller && caller.role !== "owner") {
    res.json({ providers: [], totals: {}, services: { kb: await kbStats().catch(() => null) }, me });
    return;
  }
  const [orKey, summary, perProvider, kb, github] = await Promise.all([
    getOpenRouterKeyInfo(),
    getUsageSummary().catch(() => null),
    getProviderUsage().catch(() => ({}) as Record<string, ProviderUsage>),
    kbStats().catch(() => null),
    getGithubInfo(),
  ]);
  const info = orKey.info;
  const orFree = info?.isFreeTier !== false && info?.limit !== null && info?.limit !== undefined;

  const providers = PROVIDERS.map((p) => {
    const key = p.key();
    const models = MODELS.filter((m) => m.provider === p.id);
    const usage = perProvider[p.id] ?? null;
    const cooling = models.filter((m) => cooldownUntil(m.id) !== null).length;
    let quota: Quota | null = null;

    if (p.id === "openrouter" && orFree) {
      quota = { unit: "requests", period: "day", used: info!.used, limit: info!.limit, remaining: info!.remaining, resetsAt: nextUtcMidnight(), source: "official", perModel: false };
    } else if (p.id === "groq") {
      // Groq reports quota per model in response headers; show the tightest one.
      const snaps = rateSnapshots("groq:").filter(([, s]) => s.limitRequests !== null);
      const tight = snaps.sort((a, b) => (a[1].remainingRequests ?? 0) - (b[1].remainingRequests ?? 0))[0]?.[1];
      quota = tight
        ? { unit: "requests", period: "day", used: tight.limitRequests! - (tight.remainingRequests ?? tight.limitRequests!), limit: tight.limitRequests, remaining: tight.remainingRequests, resetsAt: null, source: "official", perModel: true, rolling: true }
        : { unit: "requests", period: "day", used: usage?.todayRequests ?? 0, limit: 1000, remaining: null, resetsAt: null, source: "tracked", perModel: true, rolling: true };
    } else if (p.id === "ollama") {
      const limit = config.ollamaMonthlyBudget ?? null;
      const used = usage?.monthRequests ?? 0;
      quota = { unit: "requests", period: "month", used, limit, remaining: limit === null ? null : Math.max(0, limit - used), resetsAt: nextUtcMonth(), source: "tracked", perModel: false };
    } else if (p.id === "nvidia") {
      quota = { unit: "requests", period: "day", used: usage?.todayRequests ?? 0, limit: null, remaining: null, resetsAt: nextUtcMidnight(), source: "tracked", perModel: false };
    }

    // Live per-minute token window, when the provider reports it (Groq).
    const snap = rateSnapshots(`${p.id}:`).sort((a, b) => b[1].at.localeCompare(a[1].at))[0]?.[1];
    const tokensWindow = snap && snap.limitTokens !== null ? { limit: snap.limitTokens, remaining: snap.remainingTokens, per: "minute" as const } : null;

    const exhausted = quota?.remaining === 0;
    const status = !key ? "missing" : exhausted ? "exhausted" : cooling === models.length && models.length > 0 ? "limited" : "ok";
    return {
      id: p.id,
      name: p.name,
      configured: !!key,
      keyHint: keyHint(key),
      status,
      plan: p.plan,
      limits: p.limits,
      limitsSource: p.limitsSource,
      capacity: capacity(p, models.length),
      models: models.map((m) => m.name),
      coolingModels: cooling,
      quota,
      tokensWindow,
      today: { requests: usage?.todayRequests ?? 0, tokens: usage?.todayTokens ?? 0, failures: usage?.todayFailures ?? 0 },
      month: { requests: usage?.monthRequests ?? 0, tokens: usage?.monthTokens ?? 0 },
      lastLimitHitAt: usage?.lastLimitHitAt ?? null,
    };
  });

  const known = providers.map((p) => p.capacity.requestsPerDay).filter((n): n is number => n !== null);
  const totals = {
    requestsToday: providers.reduce((n, p) => n + p.today.requests, 0),
    tokensToday: providers.reduce((n, p) => n + p.today.tokens, 0),
    /** Sum of published daily request caps; providers without one are listed separately. */
    knownDailyRequests: known.reduce((a, b) => a + b, 0),
    uncappedProviders: providers.filter((p) => p.configured && p.capacity.requestsPerDay === null).map((p) => p.name),
  };

  res.json({
    me,
    providers,
    totals,
    services: {
      github: config.githubToken
        ? { configured: true, keyHint: keyHint(config.githubToken), purpose: "Knowledge ingestion and live GitHub cards", limitLabel: "5,000 requests per hour", ...github }
        : { configured: false, keyHint: null, purpose: "Knowledge ingestion from GitHub", limitLabel: "60 requests per hour without a token", login: null, limit: 60, remaining: null, resetsAt: null, error: null },
      embeddings: {
        provider: config.embeddingProvider,
        model: config.embeddingModel,
        dimensions: config.embeddingDimensions,
        limitLabel: config.embeddingProvider === "nvidia" ? "About 40 requests per minute, no daily cap" : "Shares OpenRouter's 50 requests per day",
        today: summary ? { requests: summary.embeddings.todayRequests, texts: summary.embeddings.todayTexts } : null,
      },
      search: { provider: "ollama", limitLabel: "Included in the Ollama account; no separate cap published", ...(summary ? { today: summary.search.today, month: summary.search.month } : { today: null, month: null }) },
      kb,
    },
    // Kept for older app builds.
    openrouter: {
      source: "official",
      period: "day",
      used: orFree ? info!.used : null,
      limit: orFree ? info!.limit : null,
      remaining: orFree ? info!.remaining : null,
      resetsAt: orFree ? nextUtcMidnight() : null,
      ratePerMin: info?.isFreeTier === false ? null : 20,
      isFreeTier: info?.isFreeTier ?? null,
      fetchedAt: info?.fetchedAt ?? null,
      stale: orKey.stale,
    },
    ollama: {
      source: "tracked",
      period: "month",
      used: summary?.ollama.monthRequests ?? null,
      limit: config.ollamaMonthlyBudget ?? null,
      tokens: summary?.ollama.monthTokens ?? null,
      today: summary ? { requests: summary.ollama.todayRequests, tokens: summary.ollama.todayTokens } : null,
      budget: config.ollamaMonthlyBudget ?? null,
      lastLimitHitAt: summary?.ollama.lastLimitHitAt ?? null,
      note: "Ollama Cloud has no usage API; counted by this server",
    },
    embeddings: {
      model: config.embeddingModel,
      dimensions: config.embeddingDimensions,
      today: summary ? { requests: summary.embeddings.todayRequests, texts: summary.embeddings.todayTexts } : null,
    },
    search: summary ? { today: summary.search.today, month: summary.search.month } : null,
    kb,
  });
});
