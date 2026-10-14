// Smart composer toggles: when a turn would benefit from the knowledge base or from a Doc, the backend does not
// silently switch it on. It tells the app (`suggest_toggle` SSE event) and the user decides. Web search is different:
// in "auto" the existing preflight/NLP decide on their own (see web/searchDecision.ts).
//
// Everything here is pure (the knowledge-base peek in retrieval/peek.ts supplies the similarities), so the
// thresholds and the once-per-conversation rule are unit-tested without a database.
import { hasIntent, type IntentResult } from "../nlp/intent.js";

export type WebMode = "auto" | "on" | "off";
export type SuggestKind = "kb" | "doc";

/** Cosine similarity a knowledge-base chunk needs for the turn to count as "looks relevant". */
export const KB_SUGGEST_MIN_SIM = 0.42;
/** A single weak match is noise; this many distinct documents (or one very strong match) make a suggestion. */
export const KB_SUGGEST_MIN_DOCS = 2;
export const KB_SUGGEST_STRONG_SIM = 0.6;
export const MAX_SAMPLE_TITLES = 3;

/** The legacy `webSearch` boolean maps to auto/off; `webMode` wins. A missing mode means auto. */
export function resolveWebMode(o: { webMode?: WebMode; webSearch?: boolean }): WebMode {
  if (o.webMode) return o.webMode;
  return o.webSearch === false ? "off" : "auto";
}

// ---- knowledge base --------------------------------------------------------------------------------------------

/** The user points at their own material: "my notes", "the file I uploaded", "from my knowledge base". */
const KB_REF =
  /\b(my|our)\s+(notes?|docs?|documents?|files?|knowledge\s?base|kb|uploads?|saved\s+(notes|docs|files)|library)\b|\b(the\s+)?(file|doc|document|pdf|notes?)s?\s+(that\s+)?i\s+(uploaded|saved|added|shared)\b|\b(from|in|using|check|search)\s+(my\s+)?(knowledge\s?base|kb)\b|\bwhat\s+i\s+(uploaded|saved)\b/i;

export const referencesKb = (text: string): boolean => KB_REF.test(text);

export type KbPeekHit = { title: string; sim: number };

export type KbRelevance = { relevant: boolean; titles: string[]; top: number };

/**
 * Whether the peek hits make the knowledge base worth suggesting. Titles are distinct, best first. At least
 * [KB_SUGGEST_MIN_DOCS] distinct documents over the threshold, or one at [KB_SUGGEST_STRONG_SIM].
 */
export function kbRelevance(hits: KbPeekHit[], minSim = KB_SUGGEST_MIN_SIM): KbRelevance {
  const best = new Map<string, number>();
  for (const h of hits) {
    const title = h.title.trim();
    if (!title || !(h.sim >= minSim)) continue;
    best.set(title, Math.max(best.get(title) ?? 0, h.sim));
  }
  const ranked = [...best.entries()].sort((a, b) => b[1] - a[1]);
  const top = ranked[0]?.[1] ?? 0;
  const relevant = ranked.length >= KB_SUGGEST_MIN_DOCS || top >= KB_SUGGEST_STRONG_SIM;
  return { relevant, titles: ranked.slice(0, MAX_SAMPLE_TITLES).map(([t]) => t), top };
}

// ---- documents -------------------------------------------------------------------------------------------------

const DOC_NOUN = "(report|document|doc|essay|guide|documentation|whitepaper|white paper|proposal|handbook|manual|ebook|thesis|research paper|case study|prd|spec(ification)?|playbook|tutorial|article|business plan|project plan|readme)";
const DOC_VERB = "(write|draft|create|prepare|generate|produce|compose|put together|make|build)";
const DOC_REQUEST = new RegExp(
  `\\b${DOC_VERB}\\b[^.?!\\n]{0,40}\\b(long|detailed|full|complete|comprehensive|in-?depth|thorough|step[- ]by[- ]step|\\d+[- ]?(page|word)s?)\\b[^.?!\\n]{0,20}\\b${DOC_NOUN}\\b` +
    `|\\b${DOC_VERB}\\b[^.?!\\n]{0,24}\\b(a|an|the|me a|me an)\\s+(\\w+\\s+){0,2}(report|essay|whitepaper|white paper|documentation|handbook|ebook|thesis|research paper|case study|business plan|playbook)\\b` +
    `|\\b(need|want|give me|looking for)\\b[^.?!\\n]{0,20}\\b(long|detailed|full|complete|comprehensive|in-?depth|thorough|\\d+[- ]?(page|word)s?)\\b[^.?!\\n]{0,10}\\b${DOC_NOUN}\\b` +
    `|\\bdocumentation\\s+(for|of|on)\\b|\\b(full|complete|comprehensive)\\s+guide\\b`,
  "i",
);

export type DocSuggestion = { reason: string; proposedTitle: string };

/** A short title for the proposed Doc, taken from the request ("write a report on X" -> "X"). */
export function proposeDocTitle(text: string): string {
  const t = text.replace(/\s+/g, " ").trim();
  const topic = t.match(/\b(?:on|about|for|covering|of)\s+(.{3,80}?)(?:[.?!,;]|$)/i)?.[1] ?? t;
  const title = topic
    .replace(/^(the|a|an)\s+/i, "")
    .slice(0, 70)
    .trim();
  return title ? title[0].toUpperCase() + title.slice(1) : "Untitled document";
}

/**
 * The turn asks for something long-form: a report, a full guide, documentation, an essay, or the intent classifier
 * is sure it is a long document. Null for everything else, including questions about attached files.
 */
export function detectDocSuggestion(text: string, intent: IntentResult, o: { hasAttachments?: boolean } = {}): DocSuggestion | null {
  const t = text.trim();
  if (t.length < 12 || o.hasAttachments) return null;
  // "Summarize this" is the classifier's long-document label too, but it is not a request to write a long document.
  const summarizing = /\b(summari[sz]e|summary|tl;?dr|key points)\b/i.test(t);
  if (DOC_REQUEST.test(t)) return { reason: "long-form request", proposedTitle: proposeDocTitle(t) };
  if (!summarizing && intent.top === "longdoc" && intent.confidence >= 0.7 && hasIntent(intent, "longdoc", 3)) {
    return { reason: "long document", proposedTitle: proposeDocTitle(t) };
  }
  return null;
}

// ---- when to ask -----------------------------------------------------------------------------------------------

/**
 * Whether to emit a suggestion. `suppressed` lists the kinds already suggested (or dismissed) in this conversation,
 * sent by the app. A kind is offered at most once per conversation, except that a KB suggestion is repeated when the
 * user explicitly points at their own material.
 */
export function mayAsk(kind: SuggestKind, o: { smart: boolean; alreadyOn: boolean; suppressed: readonly string[]; explicit?: boolean }): boolean {
  if (!o.smart || o.alreadyOn) return false;
  if (!o.suppressed.includes(kind)) return true;
  return kind === "kb" && !!o.explicit;
}

export type SuggestToggle =
  | { kind: "kb"; reason: string; sampleTitles: string[] }
  | { kind: "doc"; reason: string; proposedTitle: string };

/** Which toggle (if any) to suggest this turn, KB first. [kb] is the peek verdict, null when the peek did not run. */
export function pickSuggestion(o: {
  smart: boolean;
  kbOn: boolean;
  docOn: boolean;
  suppressed: readonly string[];
  text: string;
  intent: IntentResult;
  kb: KbRelevance | null;
  kbHasContent: boolean;
  hasAttachments?: boolean;
}): SuggestToggle | null {
  const explicit = referencesKb(o.text);
  if (mayAsk("kb", { smart: o.smart, alreadyOn: o.kbOn, suppressed: o.suppressed, explicit })) {
    if (o.kb?.relevant) return { kind: "kb", reason: explicit ? "you mentioned your notes" : "matches your knowledge base", sampleTitles: o.kb.titles };
    if (explicit && o.kbHasContent) return { kind: "kb", reason: "you mentioned your notes", sampleTitles: o.kb?.titles ?? [] };
  }
  if (mayAsk("doc", { smart: o.smart, alreadyOn: o.docOn, suppressed: o.suppressed })) {
    const d = detectDocSuggestion(o.text, o.intent, { hasAttachments: o.hasAttachments });
    if (d) return { kind: "doc", ...d };
  }
  return null;
}

// ---- the model's view ------------------------------------------------------------------------------------------

export type ToolsState = { web: "searched" | "auto-none" | "off" | "unavailable"; kb: "on" | "off"; kbSuggested?: boolean; docSuggested?: boolean };

/** A short system note: which tools were active this turn, so the model never claims one it did not use. */
export function toolsNote(s: ToolsState): string {
  const lines = ["Tools this turn:"];
  lines.push(
    s.web === "searched"
      ? "- Web search: used. Cite the numbered web sources you were given."
      : s.web === "unavailable"
        ? "- Web search: tried, but no usable live sources came back. Answer from what you know. Only if the answer depends on current facts, say in one short plain sentence that you couldn't check live sources just now; never mention search engines, providers or errors."
        : s.web === "off"
        ? "- Web search: off. Do not say you searched the web. Answer from memory only what you are sure of; for anything uncertain, obscure or possibly changed since your training, say so and mention that turning web search on would let you check."
        : "- Web search: none was run this turn (it was judged unnecessary). Do not say you searched the web. Answer from memory only what you are sure of; for anything uncertain, obscure or possibly changed since your training, say so.",
  );
  if (s.kb === "on") lines.push("- Knowledge base: on. Only call something 'from your knowledge base' if it appears in the provided knowledge sources.");
  else
    lines.push(
      `- Knowledge base: OFF. You did not search the user's notes or files and must never claim to have.${s.kbSuggested ? " It may be relevant: after answering, you may say once, briefly, that you can check their knowledge base if they want." : ""}`,
    );
  if (s.docSuggested) {
    lines.push("- This looks like a long document and the app has offered to write it as a Doc. Answer briefly in chat (a short answer or outline, not the full text), then offer once to expand it into a full Doc.");
  }
  return lines.join("\n");
}
