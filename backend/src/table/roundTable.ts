import { MODELS } from "../models.js";
import type { Message } from "../providers.js";
import { ask } from "../llm/ask.js";
import { pickCandidates, preferForPrompt } from "../llm/router.js";
import { check as budgetCheck } from "../llm/budget.js";
import { slotsFor } from "../llm/slots.js";
import { log } from "../util/logger.js";
import { CHAIR_PROMPT, DRAFT_NO_SOURCES, DRAFT_PROMPT, seatResearchIntro } from "../prompts/table.js";
import { expectedMs, recordLatency, type StepKind } from "./latency.js";
import { computeSupport, type SupportItem } from "./support.js";

// ---- configuration ---------------------------------------------------------

/**
 * Two drafting seats; seat A also chairs. Models are picked per seat from
 * these families, best first, preferring different providers and the ones
 * with headroom (minute budget, free slot) right now.
 */
const FAMILIES: Record<SeatId, string[]> = {
  // Ollama serves Nemotron Ultra ~2.5x faster than NVIDIA's endpoint (measured).
  A: [
    "ollama:nemotron-3-ultra",
    "nvidia:nvidia/nemotron-3-ultra-550b-a55b",
    "nvidia:nvidia/nemotron-3-super-120b-a12b",
    "ollama:nemotron-3-super",
    "openrouter:nvidia/nemotron-3-ultra-550b-a55b:free",
    "openrouter:nvidia/nemotron-3-super-120b-a12b:free",
  ],
  B: ["groq:openai/gpt-oss-120b", "ollama:gpt-oss:120b", "nvidia:z-ai/glm-5.3-flash", "ollama:gemma4:31b", "groq:qwen/qwen3.8-27b", "openrouter:google/gemma-4-31b-it:free"],
};
const SEAT_IDS = ["A", "B"] as const;
// Concurrent requests per provider (mirrors llm/router.ts): seats prefer a
// provider with a free slot so drafts run in parallel, not in line.
const PROVIDER_SLOTS: Record<string, number> = { ollama: 1, openrouter: 2, groq: 3, nvidia: 2 };

// Short drafts: the chair only needs the substance of each, and every token
// counts against the providers' per-minute windows.
const DRAFT_MS = 30_000;
const DRAFT_TOKENS = 700;
const DRAFT_MAX_CHARS = 2_400;
const BUDGET_MS = 60_000;
const MIN_CHAIR_MS = 6_000;
const QUORUM = 2;
const SUMMARY_MAX = 160;
const TRANSCRIPT_DRAFT_MAX = 2_400;
// ETA: floor for a step that is already over its usual time.
const MIN_LEFT_MS = 2_000;

// ---- types -----------------------------------------------------------------

export type SeatId = (typeof SEAT_IDS)[number];
export type SeatStatus = "working" | "done" | "failed" | "agreed" | "disputed";
export type TablePhase = "researching" | "seating" | "drafting" | "checking" | "reviewing" | "synthesizing" | "done";
export type ReviewPoint = { seat: string; kind: "error" | "disagree" | "missing"; claim: string; detail: string; sources: string[] };
export type TableSeat = {
  seat: SeatId;
  model: string;
  name: string;
  status: "done" | "failed";
  summary: string;
  draft: string;
  /** Citation tags the draft cites, in order. */
  sources: string[];
  /** What this seat searched the web for. */
  queries: string[];
};
export type TableReview = { seat: SeatId; model: string; verdict: "agree" | "minor" | "major" | "unknown"; points: ReviewPoint[] };
export type TableTranscript = {
  seats: TableSeat[];
  reviews: TableReview[];
  consensus: "agreed" | "resolved" | "disputed";
  unresolved: string[];
  chair: string;
  calls: number;
  ms: number;
  /** Which seats' drafts back each sentence of the answer. */
  support?: SupportItem[];
};
export type TableEvent = {
  phase: TablePhase;
  seats?: { seat: SeatId; model: string; name: string; queries?: string[] }[];
  seat?: SeatId;
  model?: string;
  status?: SeatStatus;
  summary?: string;
  points?: ReviewPoint[];
  conflicts?: string[];
  transcript?: TableTranscript;
  /** Since the request started. */
  elapsedMs?: number;
  /** Estimated time until the answer is complete. */
  etaMs?: number;
};

type Plan = { seat: SeatId; models: string[] };
type Draft = { seat: SeatId; model: string; text: string };

export type TableInput = {
  /** Conversation turns as sent to the model (images included). */
  history: Message[];
  /** Sources block shared by every seat, or null. */
  context: string | null;
  question: string;
  /** Extra system lines for drafts (date, language). */
  preamble: string;
  promptChars: number;
  /** Vision models available for this request; set when it has images. */
  vision: string[] | null;
  signal: AbortSignal;
  emit: (e: TableEvent) => void;
  /** Per-seat web research: the queries, results only that seat sees, and every tag it may cite. */
  research?: SeatResearchInput[];
  /** When the request started, for elapsed time. */
  startedAt?: number;
};

export type SeatResearchInput = { seat: SeatId; queries: string[]; items: { id: string; title: string; url: string; text: string }[]; tags: string[] };

export type TableRun = {
  /** System message for the chair, appended after the normal prompt. */
  chairMessage: Message;
  /** Candidates for the chair's streamed answer. */
  candidates: string[];
  /** Finishes the transcript once the chair answered ([answer]: its text, for the support map). */
  finish(chair: string, chairCalls: number, unresolved: string[], answer?: string): TableTranscript;
};

// ---- helpers ---------------------------------------------------------------

const nameOf = (id: string) => MODELS.find((m) => m.id === id)?.name ?? id.slice(id.indexOf(":") + 1);
const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1).trimEnd()}…` : s);

/** Greetings, thanks and very short turns are not worth a table. */
export function isTrivialTurn(text: string): boolean {
  const t = text.trim();
  if (!t) return true;
  if (/^(hi|hii+|hello|hey|heya|yo|sup|thanks|thank you|thx|ty|ok|okay|k|cool|nice|great|bye|good (morning|afternoon|evening|night)|gm|gn)\b[\s!.?,:)]*\w{0,10}[\s!.?)]*$/i.test(t)) return true;
  return t.length < 15 && !t.includes("?");
}

function summaryOf(draft: string): string {
  const line = draft.split("\n").find((l) => /tl;?dr/i.test(l)) ?? draft.split("\n").find((l) => l.trim()) ?? "";
  return clip(line.replace(/^[\s*_#>-]*tl;?dr[\s*_]*:?[\s*_]*/i, "").replace(/\*\*/g, "").trim(), SUMMARY_MAX);
}

/**
 * The last balanced {...} object in `raw` that parses and has `key`. Models
 * sometimes echo the schema template or wrap the JSON in prose or fences.
 */
export function parseJson(raw: string, key: string): any {
  let found: any = undefined;
  for (let start = raw.indexOf("{"); start >= 0; start = raw.indexOf("{", start + 1)) {
    let depth = 0;
    let inString = false;
    for (let i = start; i < raw.length; i++) {
      const ch = raw[i];
      if (inString) {
        if (ch === "\\") i++;
        else if (ch === '"') inString = false;
      } else if (ch === '"') inString = true;
      else if (ch === "{") depth++;
      else if (ch === "}" && --depth === 0) {
        try {
          const obj = JSON.parse(raw.slice(start, i + 1));
          if (obj && typeof obj === "object" && key in obj) found = obj;
        } catch {
          /* not this one */
        }
        break;
      }
    }
  }
  if (found === undefined) throw new Error("no JSON");
  return found;
}

function draftsBlock(drafts: Draft[]): string {
  return drafts.map((d) => `### Draft ${d.seat} (${nameOf(d.model)})\n${d.text.trim()}`).join("\n\n");
}

/** Removes citation tags that are not in `valid` (models copy example tags or invent them). */
const stripTags = (text: string, valid: Set<string>) =>
  text.replace(/[\[【]([KWDC]\d+)[\]】]/g, (m, tag: string) => (valid.has(tag) ? m : "")).replace(/ +([.,;:])/g, "$1");

/** Tags a text cites, first use first. */
const citedTags = (text: string) => [...new Set([...text.matchAll(/\[([KWDGC]\d+)\]/g)].map((m) => m[1]))];

/** A seat's own search results as a system message for its draft. */
function researchMessage(r: SeatResearchInput): Message | null {
  if (r.items.length === 0) return null;
  const safe = (t: string) => t.replace(/<\/web_results>/gi, "<\\/web_results>");
  const items = r.items.map((i) => `[${i.id}] ${i.title} - ${i.url}\n${safe(i.text)}`).join("\n\n");
  return { role: "system", content: `${seatResearchIntro(r.queries)}\n<web_results>\n${items}\n</web_results>` };
}

/** Whole-table estimate before seating, from the usual first models. */
export function initialEtaMs(withResearch: boolean): number {
  const seatMax = Math.max(...SEAT_IDS.map((s) => expectedMs("draft", FAMILIES[s][0])));
  return (withResearch ? expectedMs("research", "plan") + expectedMs("research", "search") : 0) + seatMax + expectedMs("chair", FAMILIES.A[0]);
}

const providerOf = (id: string) => id.slice(0, id.indexOf(":"));

export type TableDeps = {
  ask: typeof ask;
  candidates: () => Promise<string[]>;
  /** Whether a call of about [tokens] fits [id] right now (minute budget, free slot). */
  headroom: (id: string, tokens: number) => boolean;
};

export const defaultTableDeps: TableDeps = {
  ask,
  candidates: () => pickCandidates(undefined),
  headroom: (id, tokens) => budgetCheck(id, tokens).ok && (slotsFor(id)?.available ?? true),
};

/**
 * Seats one model per seat on DIFFERENT providers where possible, preferring
 * models with headroom right now (so the two drafts never queue behind each
 * other or hit the same per-minute window). Each seat gets one fallback from
 * yet another provider.
 */
export async function seat(promptChars: number, vision: string[] | null, deps: TableDeps = defaultTableDeps): Promise<Plan[]> {
  if (vision) {
    // Images: every seat must see them, so the seats come from the vision list.
    return vision.slice(0, SEAT_IDS.length).map((id, i) => ({ seat: SEAT_IDS[i], models: [id] }));
  }
  const avail = preferForPrompt(await deps.candidates(), promptChars);
  const need = Math.ceil(promptChars / 3.5) + DRAFT_TOKENS;
  const used = new Set<string>();
  const load = new Map<string, number>();
  const usedProviders = new Set<string>();
  const hasSlot = (id: string) => (load.get(providerOf(id)) ?? 0) < (PROVIDER_SLOTS[providerOf(id)] ?? 1);
  const plans: Plan[] = [];
  for (const s of SEAT_IDS) {
    const open = [...FAMILIES[s].filter((id) => avail.includes(id)), ...avail.filter((id) => !FAMILIES[s].includes(id))].filter((id) => !used.has(id));
    // Best first: a new provider with headroom, then any with headroom, then a new provider, then the rest.
    const rank = (id: string) => (deps.headroom(id, need) && hasSlot(id) ? 0 : 2) + (usedProviders.has(providerOf(id)) ? 1 : 0);
    const family = open.map((id, i) => ({ id, i, r: rank(id) })).sort((a, b) => a.r - b.r || a.i - b.i).map((x) => x.id);
    if (family.length === 0) continue;
    const primary = family[0];
    const fallback = family.find((id) => id !== primary && providerOf(id) !== providerOf(primary));
    used.add(primary);
    usedProviders.add(providerOf(primary));
    load.set(providerOf(primary), (load.get(providerOf(primary)) ?? 0) + 1);
    plans.push({ seat: s, models: fallback ? [primary, fallback] : [primary] });
  }
  // A fallback must not be another seat's primary.
  for (const p of plans) p.models = [p.models[0], ...p.models.slice(1).filter((id) => !plans.some((o) => o !== p && o.models[0] === id))];
  return plans;
}

/** Strips the chair's trailing <unresolved>…</unresolved> block from the stream and keeps its text. */
export class UnresolvedFilter {
  private held = "";
  private captured: string | null = null;
  private static readonly OPEN = "<unresolved>";

  push(chunk: string): string {
    if (this.captured !== null) {
      this.captured += chunk;
      return "";
    }
    const s = this.held + chunk;
    this.held = "";
    const at = s.indexOf(UnresolvedFilter.OPEN);
    if (at >= 0) {
      this.captured = s.slice(at + UnresolvedFilter.OPEN.length);
      return s.slice(0, at);
    }
    // Hold back a possible partial "<unresolved" at the end.
    const lt = s.lastIndexOf("<");
    if (lt >= 0 && UnresolvedFilter.OPEN.startsWith(s.slice(lt))) {
      this.held = s.slice(lt);
      return s.slice(0, lt);
    }
    return s;
  }

  flush(): string {
    const rest = this.held;
    this.held = "";
    return rest;
  }

  reset(): void {
    this.held = "";
    this.captured = null;
  }

  /** Bullets from the captured block, without "none"-style entries. */
  items(): string[] {
    if (this.captured === null) return [];
    const body = this.captured.split("</unresolved>")[0];
    return body
      .split("\n")
      .map((l) => l.replace(/^\s*(?:[-*•]|\d+[.)])\s*/, "").trim())
      .filter((l) => l && !/^(none|nothing|n\/a|-|no (open|unresolved) questions?)\.?$/i.test(l))
      .map((l) => clip(l, 240))
      .slice(0, 8);
  }
}

// ---- the table ---------------------------------------------------------------

/**
 * Round 1: two independent short drafts from models on different providers.
 * Round 2: the chair (streamed by the caller with the returned message and
 * candidates) compares the drafts, settles disagreements against the sources
 * and writes the answer; there is no separate judge or review step. Returns
 * null when fewer than two drafts came back or anything unexpected failed
 * (the caller then answers the normal way, the turn never fails because of
 * the table).
 */
export async function runRoundTable(input: TableInput, deps: TableDeps = defaultTableDeps): Promise<TableRun | null> {
  try {
    return await runTable(input, deps);
  } catch (e) {
    if (input.signal.aborted) throw e;
    log.warn("round table failed, answering normally", { message: (e as Error).message?.slice(0, 160) });
    return null;
  }
}

async function runTable(input: TableInput, deps: TableDeps): Promise<TableRun | null> {
  const started = Date.now();
  const deadline = started + BUDGET_MS;
  const { signal } = input;
  let calls = 0;

  // ---- progress estimate ----------------------------------------------------
  const t0 = input.startedAt ?? started;
  let phase: TablePhase = "seating";
  let phaseAt = Date.now();
  let seatModels: string[] = [];
  let chairModel: string = FAMILIES.A[0];
  const inFlight = new Map<SeatId, { model: string; at: number }>();
  const seatMax = () => (seatModels.length ? Math.max(...seatModels.map((m) => expectedMs("draft", m))) : expectedMs("draft"));
  const draftLeft = () => {
    const now = Date.now();
    const left = inFlight.size ? Math.max(...[...inFlight.values()].map((w) => expectedMs("draft", w.model) - (now - w.at))) : seatMax() - (now - phaseAt);
    return Math.max(left, MIN_LEFT_MS);
  };
  const etaMs = (): number => {
    const chair = expectedMs("chair", chairModel);
    switch (phase) {
      case "seating":
        return seatMax() + chair;
      case "drafting":
        return draftLeft() + chair;
      case "synthesizing":
        return chair;
      default:
        return 0;
    }
  };
  const emit = (e: TableEvent) => {
    if (e.phase !== phase) {
      phase = e.phase;
      phaseAt = Date.now();
      inFlight.clear();
    }
    if (e.seat && e.model && e.status === "working") inFlight.set(e.seat, { model: e.model, at: Date.now() });
    else if (e.seat && e.status) inFlight.delete(e.seat);
    input.emit({ ...e, elapsedMs: Date.now() - t0, etaMs: Math.round(etaMs()) });
  };

  const research = new Map((input.research ?? []).map((r) => [r.seat, r]));
  const plans = await seat(input.promptChars, input.vision, deps);
  if (plans.length < QUORUM) return null;
  seatModels = plans.map((p) => p.models[0]);
  chairModel = plans.find((p) => p.seat === "A")?.models[0] ?? seatModels[0];
  emit({ phase: "seating", seats: plans.map((p) => ({ seat: p.seat, model: p.models[0], name: nameOf(p.models[0]), queries: research.get(p.seat)?.queries ?? [] })) });

  // ---- round 1: drafts ----------------------------------------------------
  emit({ phase: "drafting" });
  const tags = new Set([...(input.context ?? "").matchAll(/^\[([KWDC]\d+)\]/gm)].map((m) => m[1]));
  const seats: TableSeat[] = [];
  const drafts: Draft[] = [];
  await Promise.allSettled(
    plans.map(async (p) => {
      // Each seat sees the shared sources plus its own research.
      const own = research.get(p.seat);
      const valid = new Set([...tags, ...(own?.tags ?? [])]);
      const ownMsg = own ? researchMessage(own) : null;
      const draftPrompt = valid.size > 0 ? DRAFT_PROMPT : `${DRAFT_PROMPT} ${DRAFT_NO_SOURCES}`;
      const draftMsgs: Message[] = [
        { role: "system", content: `${draftPrompt}\n\n${input.preamble}`.trim() },
        ...(input.context ? [{ role: "system" as const, content: input.context }] : []),
        ...(ownMsg ? [ownMsg] : []),
        ...input.history,
      ];
      const queries = own?.queries ?? [];
      for (const model of p.models) {
        const left = deadline - Date.now() - MIN_CHAIR_MS;
        if (left < 5_000 || signal.aborted) break;
        emit({ phase: "drafting", seat: p.seat, model, status: "working" });
        calls++;
        const at = Date.now();
        try {
          const raw = await deps.ask(model, draftMsgs, { timeoutMs: Math.min(DRAFT_MS, left), maxTokens: DRAFT_TOKENS, maxChars: DRAFT_MAX_CHARS, signal, purpose: "table-draft" });
          recordLatency("draft", model, Date.now() - at);
          const text = stripTags(raw.replace(/【/g, "[").replace(/】/g, "]"), valid);
          const summary = summaryOf(text);
          const sources = citedTags(text);
          drafts.push({ seat: p.seat, model, text });
          seats.push({ seat: p.seat, model, name: nameOf(model), status: "done", summary, draft: clip(text.trim(), TRANSCRIPT_DRAFT_MAX), sources, queries });
          emit({ phase: "drafting", seat: p.seat, model, status: "done", summary });
          return;
        } catch (e) {
          if (signal.aborted) throw e;
          log.warn("table draft failed", { seat: p.seat, model, message: (e as Error).message?.slice(0, 120) });
        }
      }
      const model = p.models[p.models.length - 1];
      seats.push({ seat: p.seat, model, name: nameOf(model), status: "failed", summary: "", draft: "", sources: [], queries });
      emit({ phase: "drafting", seat: p.seat, model, status: "failed" });
    }),
  );
  if (signal.aborted) throw new DOMException("aborted", "AbortError");
  seats.sort((a, b) => a.seat.localeCompare(b.seat));
  drafts.sort((a, b) => a.seat.localeCompare(b.seat));
  // A drafter failed: give up gracefully, one model answers the normal way.
  if (drafts.length < QUORUM) return null;

  // ---- round 2 setup: the chair compares the drafts itself -------------------
  const chairSeat = drafts.find((d) => d.seat === "A") ?? drafts[0];
  const hasSources = tags.size > 0 || (input.research ?? []).some((r) => r.tags.length > 0);
  const chairMessage: Message = {
    role: "system",
    content: [hasSources ? CHAIR_PROMPT : `${CHAIR_PROMPT} ${DRAFT_NO_SOURCES}`, `<drafts>\n${draftsBlock(drafts)}\n</drafts>`].join("\n\n"),
  };

  const auto = input.vision ?? preferForPrompt(await deps.candidates(), input.promptChars + chairMessage.content.length);
  const candidates = [...new Set([chairSeat.model, ...drafts.filter((d) => d !== chairSeat).map((d) => d.model), ...auto])];
  chairModel = chairSeat.model;
  emit({ phase: "synthesizing", seat: chairSeat.seat, model: chairSeat.model });
  const tableCalls = calls;

  return {
    chairMessage,
    candidates,
    finish(chair, chairCalls, unresolved, answer = "") {
      const consensus = unresolved.length > 0 ? "disputed" : "agreed";
      let support: SupportItem[] = [];
      try {
        support = computeSupport(answer, drafts, unresolved);
      } catch (e) {
        log.warn("table support failed", { message: (e as Error).message?.slice(0, 120) });
      }
      const transcript: TableTranscript = {
        seats,
        reviews: [],
        consensus,
        unresolved,
        chair,
        calls: tableCalls + chairCalls,
        ms: Date.now() - started,
        ...(support.length ? { support } : {}),
      };
      emit({ phase: "done", transcript });
      return transcript;
    },
  };
}
