import { MODELS } from "../models.js";
import type { Message } from "../providers.js";
import { ask } from "../llm/ask.js";
import { pickCandidates, preferForPrompt } from "../llm/router.js";
import { log } from "../util/logger.js";
import { CHAIR_PROMPT, DRAFT_NO_SOURCES, DRAFT_PROMPT, JUDGE_PROMPT, REVIEW_PROMPT } from "../prompts/table.js";

// ---- configuration ---------------------------------------------------------

/** One model family per seat, best first. Seat A chairs. */
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
  B: ["groq:openai/gpt-oss-120b", "ollama:gpt-oss:120b", "nvidia:z-ai/glm-5.3-flash"],
  C: ["ollama:gemma4:31b", "groq:qwen/qwen3.8-27b", "nvidia:z-ai/glm-5.3-flash", "openrouter:google/gemma-4-31b-it:free"],
};
const SEAT_IDS = ["A", "B", "C"] as const;
// Concurrent requests per provider (mirrors llm/router.ts): seats prefer a
// provider with a free slot so drafts run in parallel, not in line.
const PROVIDER_SLOTS: Record<string, number> = { ollama: 1, openrouter: 2, groq: 3, nvidia: 2 };
const JUDGE_MODELS = ["groq:openai/gpt-oss-20b", "ollama:gpt-oss:20b"];

const DRAFT_MS = 45_000;
const DRAFT_TOKENS = 1200;
const DRAFT_MAX_CHARS = 4_000;
const REVIEW_MS = 25_000;
// Reasoning models (gpt-oss, nemotron) spend part of max_tokens on hidden
// reasoning; 600 often left the JSON empty, so reviews get more room.
const REVIEW_TOKENS = 1500;
const JUDGE_MS = 8_000;
const BUDGET_MS = 90_000;
const MIN_REVIEW_MS = 6_000;
const QUORUM = 2;
const SUMMARY_MAX = 160;
const TRANSCRIPT_DRAFT_MAX = 1_500;
const MAX_POINTS = 6;

// ---- types -----------------------------------------------------------------

export type SeatId = (typeof SEAT_IDS)[number];
export type SeatStatus = "working" | "done" | "failed" | "agreed" | "disputed";
export type TablePhase = "seating" | "drafting" | "checking" | "reviewing" | "synthesizing" | "done";
export type ReviewPoint = { seat: string; kind: "error" | "disagree" | "missing"; claim: string; detail: string; sources: string[] };
export type TableSeat = { seat: SeatId; model: string; name: string; status: "done" | "failed"; summary: string; draft: string };
export type TableReview = { seat: SeatId; model: string; verdict: "agree" | "minor" | "major" | "unknown"; points: ReviewPoint[] };
export type TableTranscript = {
  seats: TableSeat[];
  reviews: TableReview[];
  consensus: "agreed" | "resolved" | "disputed";
  unresolved: string[];
  chair: string;
  calls: number;
  ms: number;
};
export type TableEvent = {
  phase: TablePhase;
  seats?: { seat: SeatId; model: string; name: string }[];
  seat?: SeatId;
  model?: string;
  status?: SeatStatus;
  summary?: string;
  points?: ReviewPoint[];
  conflicts?: string[];
  transcript?: TableTranscript;
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
};

export type TableRun = {
  /** System message for the chair, appended after the normal prompt. */
  chairMessage: Message;
  /** Candidates for the chair's streamed answer. */
  candidates: string[];
  /** Finishes the transcript once the chair answered. */
  finish(chair: string, chairCalls: number, unresolved: string[]): TableTranscript;
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
function parseJson(raw: string, key: string): any {
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

function parsePoints(raw: unknown, valid: Set<string>): ReviewPoint[] {
  if (!Array.isArray(raw)) return [];
  const out: ReviewPoint[] = [];
  for (const p of raw) {
    if (!p || typeof p !== "object") continue;
    const kind = ["error", "disagree", "missing"].includes(p.kind) ? p.kind : "disagree";
    const claim = typeof p.claim === "string" ? clip(p.claim.trim(), 200) : "";
    if (!claim) continue;
    const seat = typeof p.seat === "string" ? p.seat.trim().toUpperCase().replace(/^(DRAFT|SEAT|EXPERT)\s*/, "").slice(0, 1) : "";
    out.push({
      seat: valid.has(seat) ? seat : "",
      kind,
      claim,
      detail: typeof p.detail === "string" ? clip(p.detail.trim(), 300) : "",
      sources: Array.isArray(p.sources) ? p.sources.filter((s: unknown): s is string => typeof s === "string" && /^[KWD]\d+$/.test(s.replace(/[[\]]/g, ""))).map((s: string) => s.replace(/[[\]]/g, "")).slice(0, 5) : [],
    });
    if (out.length >= MAX_POINTS) break;
  }
  return out;
}

function draftsBlock(drafts: Draft[]): string {
  return drafts.map((d) => `### Draft ${d.seat} (${nameOf(d.model)})\n${d.text.trim()}`).join("\n\n");
}

/** Removes citation tags that are not in `valid` (models copy example tags or invent them). */
const stripTags = (text: string, valid: Set<string>) =>
  text.replace(/[\[【]([KWD]\d+)[\]】]/g, (m, tag: string) => (valid.has(tag) ? m : "")).replace(/ +([.,;:])/g, "$1");

const withoutImages = (msgs: Message[]): Message[] => msgs.map((m) => (m.images?.length ? { role: m.role, content: m.content } : m));

/** Seats one model per family, skipping models in cooldown or otherwise unavailable. */
async function seat(promptChars: number, vision: string[] | null): Promise<Plan[]> {
  if (vision) {
    // Images: every seat must see them, so the seats come from the vision list.
    return vision.slice(0, SEAT_IDS.length).map((id, i) => ({ seat: SEAT_IDS[i], models: [id] }));
  }
  const avail = preferForPrompt(await pickCandidates(undefined), promptChars);
  const used = new Set<string>();
  const load = new Map<string, number>();
  const providerOf = (id: string) => id.slice(0, id.indexOf(":"));
  const hasSlot = (id: string) => (load.get(providerOf(id)) ?? 0) < (PROVIDER_SLOTS[providerOf(id)] ?? 1);
  const plans: Plan[] = [];
  for (const s of SEAT_IDS) {
    const open = FAMILIES[s].filter((id) => avail.includes(id) && !used.has(id));
    const family = [...open.filter(hasSlot), ...open.filter((id) => !hasSlot(id))];
    const models = family.length > 0 ? family.slice(0, 2) : avail.filter((id) => !used.has(id)).slice(0, 2);
    if (models.length === 0) continue;
    used.add(models[0]);
    load.set(providerOf(models[0]), (load.get(providerOf(models[0])) ?? 0) + 1);
    plans.push({ seat: s, models });
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
 * Rounds 1 and 2 of the table: independent drafts, an agreement check and,
 * when needed, cross-review. Returns null when fewer than two drafts came
 * back (the caller then answers the normal way). Round 3 (the chair) is
 * streamed by the caller with the returned message and candidates.
 */
export async function runRoundTable(input: TableInput): Promise<TableRun | null> {
  const started = Date.now();
  const deadline = started + BUDGET_MS;
  const { signal, emit } = input;
  let calls = 0;

  const plans = await seat(input.promptChars, input.vision);
  if (plans.length < QUORUM) return null;
  emit({ phase: "seating", seats: plans.map((p) => ({ seat: p.seat, model: p.models[0], name: nameOf(p.models[0]) })) });

  // ---- round 1: drafts ----------------------------------------------------
  emit({ phase: "drafting" });
  const tags = new Set([...(input.context ?? "").matchAll(/^\[([KWD]\d+)\]/gm)].map((m) => m[1]));
  const draftPrompt = tags.size > 0 ? DRAFT_PROMPT : `${DRAFT_PROMPT} ${DRAFT_NO_SOURCES}`;
  const draftMsgs: Message[] = [
    { role: "system", content: `${draftPrompt}\n\n${input.preamble}`.trim() },
    ...(input.context ? [{ role: "system" as const, content: input.context }] : []),
    ...input.history,
  ];
  const seats: TableSeat[] = [];
  const drafts: Draft[] = [];
  await Promise.allSettled(
    plans.map(async (p) => {
      for (const model of p.models) {
        const left = deadline - Date.now() - MIN_REVIEW_MS;
        if (left < 5_000 || signal.aborted) break;
        emit({ phase: "drafting", seat: p.seat, model, status: "working" });
        calls++;
        try {
          const raw = await ask(model, draftMsgs, { timeoutMs: Math.min(DRAFT_MS, left), maxTokens: DRAFT_TOKENS, maxChars: DRAFT_MAX_CHARS, signal });
          const text = stripTags(raw, tags);
          const summary = summaryOf(text);
          drafts.push({ seat: p.seat, model, text });
          seats.push({ seat: p.seat, model, name: nameOf(model), status: "done", summary, draft: clip(text.trim(), TRANSCRIPT_DRAFT_MAX) });
          emit({ phase: "drafting", seat: p.seat, model, status: "done", summary });
          return;
        } catch (e) {
          if (signal.aborted) throw e;
          log.warn("table draft failed", { seat: p.seat, model, message: (e as Error).message?.slice(0, 120) });
        }
      }
      const model = p.models[p.models.length - 1];
      seats.push({ seat: p.seat, model, name: nameOf(model), status: "failed", summary: "", draft: "" });
      emit({ phase: "drafting", seat: p.seat, model, status: "failed" });
    }),
  );
  if (signal.aborted) throw new DOMException("aborted", "AbortError");
  seats.sort((a, b) => a.seat.localeCompare(b.seat));
  drafts.sort((a, b) => a.seat.localeCompare(b.seat));
  if (drafts.length < QUORUM) return null;

  // ---- agreement check ----------------------------------------------------
  emit({ phase: "checking" });
  let agreed = false;
  let conflicts: string[] = [];
  const judgeMsgs: Message[] = [
    { role: "system", content: JUDGE_PROMPT },
    { role: "user", content: `Question: ${clip(input.question, 1500)}\n\n${drafts.map((d) => `### Answer ${d.seat}\n${clip(d.text.trim(), 2500)}`).join("\n\n")}` },
  ];
  const judges = (await pickCandidates(undefined)).filter((id) => JUDGE_MODELS.includes(id));
  for (const model of JUDGE_MODELS.filter((id) => judges.includes(id))) {
    if (signal.aborted) break;
    calls++;
    try {
      const parsed = parseJson(await ask(model, judgeMsgs, { timeoutMs: JUDGE_MS, signal }), "agree");
      conflicts = Array.isArray(parsed.conflicts) ? parsed.conflicts.filter((c: unknown): c is string => typeof c === "string" && !!c.trim()).map((c: string) => clip(c.trim(), 140)).slice(0, 5) : [];
      agreed = parsed.agree === true && conflicts.length === 0;
      break;
    } catch (e) {
      if (signal.aborted) break;
      log.warn("table judge failed", { model, message: (e as Error).message?.slice(0, 120) });
    }
  }
  if (signal.aborted) throw new DOMException("aborted", "AbortError");
  emit({ phase: "checking", status: agreed ? "agreed" : "disputed", conflicts });

  // ---- round 2: cross-review ----------------------------------------------
  const reviews: TableReview[] = [];
  const reviewMs = Math.min(REVIEW_MS, deadline - Date.now());
  if (!agreed && reviewMs >= MIN_REVIEW_MS) {
    emit({ phase: "reviewing" });
    const textHistory = withoutImages(input.history);
    const valid = new Set(drafts.map((d) => d.seat));
    await Promise.allSettled(
      drafts.map(async (own) => {
        const others = drafts.filter((d) => d !== own);
        emit({ phase: "reviewing", seat: own.seat, model: own.model, status: "working" });
        const msgs: Message[] = [
          { role: "system", content: REVIEW_PROMPT },
          ...(input.context ? [{ role: "system" as const, content: input.context }] : []),
          ...textHistory,
          {
            role: "user",
            content: `You are expert ${own.seat}. Your own draft:\n${clip(own.text.trim(), 2500)}\n\nReview these drafts from the other experts:\n\n${draftsBlock(others)}\n\nReply with the JSON only.`,
          },
        ];
        calls++;
        let review: TableReview = { seat: own.seat, model: own.model, verdict: "unknown", points: [] };
        try {
          const parsed = parseJson(await ask(own.model, msgs, { timeoutMs: reviewMs, maxTokens: REVIEW_TOKENS, signal }), "verdict");
          const points = parsePoints(parsed.points, valid).filter((p) => p.seat !== own.seat);
          const verdict = ["agree", "minor", "major"].includes(parsed.verdict) ? parsed.verdict : points.length ? "minor" : "agree";
          review = { seat: own.seat, model: own.model, verdict, points: verdict === "agree" ? [] : points };
        } catch (e) {
          if (signal.aborted) throw e;
          log.warn("table review failed", { seat: own.seat, model: own.model, message: (e as Error).message?.slice(0, 120) });
        }
        reviews.push(review);
        emit({
          phase: "reviewing",
          seat: own.seat,
          model: own.model,
          status: review.verdict === "unknown" ? "failed" : review.verdict === "agree" ? "agreed" : "disputed",
          points: review.points,
        });
      }),
    );
    if (signal.aborted) throw new DOMException("aborted", "AbortError");
    reviews.sort((a, b) => a.seat.localeCompare(b.seat));
  }

  // ---- round 3 setup: the chair -----------------------------------------
  const chairSeat = drafts.find((d) => d.seat === "A") ?? drafts[0];
  const reviewLines = reviews.flatMap((r) =>
    r.verdict === "unknown"
      ? []
      : r.points.length === 0
        ? [`- Expert ${r.seat}: agrees with the other drafts.`]
        : r.points.map((p) => `- Expert ${r.seat} on draft ${p.seat || "?"} [${p.kind}]: ${p.claim}${p.detail ? ` — ${p.detail}` : ""}${p.sources.length ? ` (${p.sources.join(", ")})` : ""}`),
  );
  const parts = [
    tags.size > 0 ? CHAIR_PROMPT : `${CHAIR_PROMPT} ${DRAFT_NO_SOURCES}`,
    `<drafts>\n${draftsBlock(drafts)}\n</drafts>`,
    agreed ? "Agreement check: the drafts agree on the key facts, so leave the <unresolved> block empty unless a draft is plainly wrong." : conflicts.length ? `Agreement check found conflicts:\n${conflicts.map((c) => `- ${c}`).join("\n")}` : "",
    reviewLines.length ? `<reviews>\n${reviewLines.join("\n")}\n</reviews>` : "",
  ].filter(Boolean);
  const chairMessage: Message = { role: "system", content: parts.join("\n\n") };

  const auto = input.vision ?? preferForPrompt(await pickCandidates(undefined), input.promptChars + chairMessage.content.length);
  const candidates = [...new Set([chairSeat.model, ...drafts.filter((d) => d !== chairSeat).map((d) => d.model), ...auto])];
  emit({ phase: "synthesizing", seat: chairSeat.seat, model: chairSeat.model });
  const tableCalls = calls;

  return {
    chairMessage,
    candidates,
    finish(chair, chairCalls, unresolved) {
      const disputedReviews = reviews.some((r) => r.verdict === "minor" || r.verdict === "major");
      const consensus = unresolved.length > 0 ? "disputed" : agreed || !disputedReviews ? "agreed" : "resolved";
      const transcript: TableTranscript = { seats, reviews, consensus, unresolved, chair, calls: tableCalls + chairCalls, ms: Date.now() - started };
      emit({ phase: "done", transcript });
      return transcript;
    },
  };
}
