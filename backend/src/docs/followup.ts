// Reader follow-ups on a finished document: ASK AI about a selected passage,
// selection edits with a preview (explain / simplify / expand / cite /
// rewrite) and the plan for "continue writing". All are single non-streamed
// model calls: the client gets JSON back and decides what to accept.
import { randomUUID } from "node:crypto";
import { buildContextMessage } from "../prompts/system.js";
import { askMessages, continueMessages, selectionMessages } from "../prompts/docFollowup.js";
import { parseJson } from "../table/roundTable.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { keepValidTags } from "./section.js";
import { preambleFor, sourceItems, type DocDeps } from "./pipeline.js";
import { type DocSection, type DocSource, type DocState, type QaEntry, type SelectionOp } from "./types.js";

const MODEL_TRIES = 3;
const ASK_TIMEOUT_MS = 45_000;
const SECTION_CLIP = 8_000;
const NEAR_CLIP = 700;
const MAX_ANSWER = 6_000;

const clip = (s: string, n: number) => (s.length <= n ? s : s.slice(0, n));

/** Runs `messages` on the best available models until one answers. */
async function askModels(deps: DocDeps, st: DocState, messages: Parameters<DocDeps["ask"]>[1], purpose: string, maxTokens: number, signal?: AbortSignal): Promise<string> {
  const chars = messages.reduce((n, m) => n + m.content.length, 0);
  const models = (await deps.candidates(st.options.model, chars)).slice(0, MODEL_TRIES);
  let last: unknown;
  for (const model of models) {
    try {
      const text = (await deps.ask(model, messages, { timeoutMs: ASK_TIMEOUT_MS, maxTokens, signal, purpose })).trim();
      if (text) return text;
    } catch (e) {
      last = e;
      if (signal?.aborted) break;
    }
  }
  log.warn("doc followup failed", { doc: st.id, purpose, message: String((last as Error)?.message ?? "no model").slice(0, 160) });
  throw new AppError(502, "upstream_failed", "sparky couldn't answer right now — try again.", true);
}

function sectionSources(st: DocState, sec: DocSection): DocSource[] {
  const ids = new Set([...sec.sourceIds, ...sec.usedIds]);
  return st.sources.filter((s) => ids.has(s.id));
}

const stripFence = (s: string) =>
  s
    .replace(/^\s*```(?:markdown|md)?\s*\n([\s\S]*?)\n```\s*$/i, "$1")
    .replace(/^\s*"""\s*([\s\S]*?)\s*"""\s*$/, "$1")
    .trim();

// ---- ASK AI ---------------------------------------------------------------------------

export async function answerQuestion(deps: DocDeps, st: DocState, sec: DocSection, input: { quote: string; question: string; thread: QaEntry[] }, signal?: AbortSignal): Promise<QaEntry> {
  const sources = sectionSources(st, sec);
  const items = sourceItems(sources);
  const messages = askMessages({
    preamble: preambleFor(st.options.profile),
    title: st.title,
    heading: sec.heading,
    section: clip(sec.markdown, SECTION_CLIP),
    quote: input.quote,
    question: input.question,
    thread: input.thread.slice(-4),
    context: buildContextMessage(items.kb, items.web, items.files),
    validTags: sources.map((s) => s.id),
  });
  const raw = await askModels(deps, st, messages, "doc-ask", 1800, signal);
  const answer = clip(keepValidTags(stripFence(raw), new Set(sources.map((s) => s.id))).trim(), MAX_ANSWER);
  if (!answer) throw new AppError(502, "upstream_failed", "sparky came back empty — try again.", true);
  return { id: randomUUID(), q: input.question.trim(), a: answer, at: new Date().toISOString() };
}

// ---- selection edits ------------------------------------------------------------------

const MARKS = /[*_`~]/;
const BETWEEN = String.raw`(?:\s|[*_` + "`" + String.raw`~]|\[[KWDG]\d{1,3}\]|\{\{[^}]*\}\}|[-*+>]|\d+[.)])+`;

/** Where a selected (plain) quote sits in a section's Markdown: the words may be separated by inline marks, citation tags and list markers. Null when absent. */
export function locateSpan(markdown: string, quote: string): { start: number; end: number } | null {
  const words = quote.replace(/\s+/g, " ").trim().split(" ").filter(Boolean);
  if (!words.length) return null;
  const esc = (w: string) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(words.map(esc).join(BETWEEN));
  const m = re.exec(markdown);
  if (!m) return null;
  let start = m.index;
  let end = m.index + m[0].length;
  // Take the marks hugging the passage so ** … ** pairs stay balanced.
  while (start > 0 && MARKS.test(markdown[start - 1])) start--;
  while (end < markdown.length && MARKS.test(markdown[end])) end++;
  return { start, end };
}

export type SelectionEdit = {
  op: SelectionOp;
  /** The passage as Markdown (empty for a pure insertion). */
  original: string;
  /** What replaces it, or is inserted. */
  replacement: string;
  /** The whole section after the change: accepting saves this. */
  markdown: string;
  version: number;
};

export async function editSelection(deps: DocDeps, st: DocState, sec: DocSection, op: SelectionOp, quote: string, instruction: string | undefined, signal?: AbortSignal): Promise<SelectionEdit> {
  const span = locateSpan(sec.markdown, quote);
  if (!span) throw new AppError(422, "not_found", "Could not find the selected text in the section. Select a passage inside a single paragraph.");
  const passage = sec.markdown.slice(span.start, span.end);
  const sources = sectionSources(st, sec);
  const items = sourceItems(sources);
  const valid = new Set(sources.map((s) => s.id));
  const messages = selectionMessages({
    preamble: preambleFor(st.options.profile),
    title: st.title,
    heading: sec.heading,
    op,
    passage,
    before: sec.markdown.slice(Math.max(0, span.start - NEAR_CLIP), span.start),
    after: sec.markdown.slice(span.end, span.end + NEAR_CLIP),
    instruction,
    context: op === "cite" || op === "expand" ? buildContextMessage(items.kb, items.web, items.files) : null,
    validTags: [...valid],
  });
  const raw = await askModels(deps, st, messages, `doc-selection-${op}`, 1600, signal);
  const out = keepValidTags(stripFence(raw), valid).trim();
  if (!out) throw new AppError(502, "upstream_failed", "sparky came back empty — try again.", true);

  if (op === "explain") {
    // A NOTE callout after the paragraph that holds the passage.
    const para = sec.markdown.indexOf("\n\n", span.end);
    const at = para < 0 ? sec.markdown.length : para;
    const note = `> [!NOTE]\n${out
      .split("\n")
      .map((l) => `> ${l}`)
      .join("\n")}`;
    const markdown = `${sec.markdown.slice(0, at)}\n\n${note}${sec.markdown.slice(at)}`;
    return { op, original: "", replacement: out, markdown, version: st.version };
  }
  if (out.replace(/\s+/g, " ") === passage.replace(/\s+/g, " ")) throw new AppError(422, "no_change", "Nothing to change in that passage.");
  if (out.length > Math.max(passage.length * 6, 600) + 400) throw new AppError(502, "upstream_failed", "That answer came out too long — try again.", true);
  const markdown = sec.markdown.slice(0, span.start) + out + sec.markdown.slice(span.end);
  return { op, original: passage, replacement: out, markdown, version: st.version };
}

// ---- continue writing -----------------------------------------------------------------

/** The heading, goal and key points of the next section. */
export async function planNextSection(deps: DocDeps, st: DocState, hint: string | undefined, signal?: AbortSignal): Promise<{ heading: string; goal: string; keyPoints: string[] }> {
  const body = (st.outline?.sections ?? []).filter((s) => !s.kind);
  const raw = await askModels(deps, st, continueMessages(st.title, body, hint, preambleFor(st.options.profile)), "doc-continue", 700, signal);
  let obj: { heading?: unknown; goal?: unknown; keyPoints?: unknown };
  try {
    obj = parseJson(raw, "heading");
  } catch {
    throw new AppError(502, "upstream_failed", "Could not plan the next section. Try again.", true);
  }
  const heading = String(obj.heading ?? "").replace(/^\d+[.)]\s*/, "").trim().slice(0, 120);
  if (!heading) throw new AppError(502, "upstream_failed", "Could not plan the next section. Try again.", true);
  const keyPoints = Array.isArray(obj.keyPoints) ? obj.keyPoints.map((k) => String(k).slice(0, 300)).filter(Boolean).slice(0, 6) : [];
  return { heading, goal: String(obj.goal ?? "").trim().slice(0, 300) || heading, keyPoints };
}
