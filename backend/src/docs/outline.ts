// Outline step: one model call (retried once on the next model when the JSON
// is unusable), normalized to the shape the pipeline relies on.
import { parseJson } from "../table/roundTable.js";
import { SECTION_COUNT, outlineMessages, type OutlineContext } from "../prompts/doc.js";
import type { Message } from "../providers.js";
import { REFERENCES_ID, STYLES, TAKEAWAYS_ID, VISUALS, type DocLength, type DocStyle, type GlossaryItem, type Outline, type OutlineSection, type Visual } from "./types.js";

export const OUTLINE_MODELS = ["groq:openai/gpt-oss-120b", "ollama:gpt-oss:120b"];
export const OUTLINE_TIMEOUT_MS = 30_000;

const str = (v: unknown, max: number) => (typeof v === "string" ? v.replace(/\s+/g, " ").trim().slice(0, max) : "");
const clampWords = (v: unknown) => {
  const n = Math.round(Number(v));
  return Number.isFinite(n) ? Math.min(Math.max(n, 250), 900) : 400;
};

export class OutlineError extends Error {}

/** Server-built sections appended to every outline. */
export function closingSections(): OutlineSection[] {
  return [
    { id: TAKEAWAYS_ID, heading: "Key takeaways", goal: "The most important points of the document.", keyPoints: [], queries: [], visual: "none", words: 120, kind: "takeaways" },
    { id: REFERENCES_ID, heading: "References", goal: "Sources cited in this document.", keyPoints: [], queries: [], visual: "none", words: 0, kind: "references" },
  ];
}

/** Normalizes model (or user-edited) outline JSON; throws OutlineError when unusable. */
export function normalizeOutline(raw: any, length: DocLength, fallbackTitle: string, maxSections?: number): { outline: Outline; glossary: GlossaryItem[] } {
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.sections)) throw new OutlineError("outline has no sections");
  const max = maxSections ?? SECTION_COUNT[length].max;
  const sections: OutlineSection[] = [];
  for (const s of raw.sections) {
    if (!s || typeof s !== "object" || s.kind) continue;
    const heading = str(s.heading, 120).replace(/^#+\s*/, "").replace(/^(§?\d+[.)]?\s+)/, "");
    if (!heading || /^(key takeaways|references|conclusion)$/i.test(heading)) continue;
    sections.push({
      id: "",
      heading,
      goal: str(s.goal, 300),
      keyPoints: (Array.isArray(s.keyPoints) ? s.keyPoints : []).map((p: unknown) => str(p, 200)).filter(Boolean).slice(0, 6),
      queries: (Array.isArray(s.queries) ? s.queries : []).map((q: unknown) => str(q, 120)).filter(Boolean).slice(0, 2),
      visual: (VISUALS as readonly string[]).includes(s.visual) ? (s.visual as Visual) : "none",
      words: clampWords(s.words),
      ...(str(s.notes, 240) ? { notes: str(s.notes, 240) } : {}),
      ...(Array.isArray(s.terms) ? { terms: s.terms.map((t: unknown) => str(t, 80)).filter(Boolean).slice(0, 5) } : {}),
    });
    if (sections.length >= max) break;
  }
  if (sections.length < 2) throw new OutlineError("outline has too few usable sections");
  sections.forEach((s, i) => (s.id = `s${i + 1}`));
  const glossary: GlossaryItem[] = (Array.isArray(raw.glossary) ? raw.glossary : [])
    .map((g: any) => ({ term: str(g?.term, 80), definition: str(g?.definition, 300) }))
    .filter((g: GlossaryItem) => g.term && g.definition)
    .slice(0, 12);
  return {
    outline: {
      title: str(raw.title, 160) || fallbackTitle,
      subtitle: str(raw.subtitle, 240),
      audience: str(raw.audience, 160),
      style: (STYLES as readonly string[]).includes(raw.style) ? (raw.style as DocStyle) : "report",
      sections: [...sections, ...closingSections()],
    },
    glossary,
  };
}

export type AskFn = (model: string, messages: Message[], opts: { timeoutMs: number; maxTokens?: number; signal?: AbortSignal; purpose?: string }) => Promise<string>;

/**
 * Tries the outline models in order. An upstream failure moves on to the next
 * model; unusable JSON is retried once on the next model. Returns the outline
 * plus how many model calls were made.
 */
export async function makeOutline(args: {
  prompt: string;
  length: DocLength;
  ctx: OutlineContext;
  preamble: string;
  models: string[];
  ask: AskFn;
  signal: AbortSignal;
}): Promise<{ outline: Outline; glossary: GlossaryItem[]; model: string; calls: number }> {
  const messages = outlineMessages(args.prompt, args.length, args.ctx, args.preamble);
  const fallbackTitle = args.prompt.trim().replace(/\s+/g, " ").slice(0, 80);
  let invalid = 0;
  let calls = 0;
  let last = "no outline model available";
  for (const model of args.models) {
    if (args.signal.aborted) break;
    calls++;
    let raw: string;
    try {
      raw = await args.ask(model, messages, { timeoutMs: OUTLINE_TIMEOUT_MS, maxTokens: 3000, signal: args.signal, purpose: "doc-outline" });
    } catch (e) {
      last = (e as Error).message ?? String(e);
      continue;
    }
    try {
      const { outline, glossary } = normalizeOutline(parseJson(raw, "sections"), args.length, fallbackTitle);
      return { outline, glossary, model, calls };
    } catch (e) {
      last = `invalid outline (${(e as Error).message})`;
      if (++invalid >= 2) break;
    }
  }
  throw new OutlineError(`Could not plan the document: ${last}`.slice(0, 200));
}
