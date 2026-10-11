// Writes one section: streamed runChat with fallback, citation-tag cleanup,
// hidden summary line, one continuation when the model hit its length limit,
// then evidence and server-side image resolution.
import { TagStream } from "../web/tagStream.js";
import { computeEvidence, type EvidenceItem } from "../web/evidence.js";
import type { ImageResult } from "../web/images.js";
import { ChatFailure, type RunHooks, type RunResult } from "../llm/router.js";
import type { Message } from "../providers.js";
import { continueMessage } from "../prompts/doc.js";
import { citedIds, countWords, type DocImage, type DocSource } from "./types.js";

const HEAD_HOLD = 200;
const MARKER_HOLD = 16;

/**
 * Stream filter for a section body: drops a leading "# / ## heading" line the
 * model was told not to write, and hides the trailing <!--summary: ...-->
 * comment (kept for the running summaries), holding back a possible partial
 * marker at the end of each chunk.
 */
export class SectionFilter {
  private head = true;
  private headBuf = "";
  private tail = "";
  private hidden: string | null = null;

  push(chunk: string): string {
    if (this.hidden !== null) {
      this.hidden += chunk;
      return "";
    }
    let t = this.tail + chunk;
    this.tail = "";
    if (this.head) {
      this.headBuf += t;
      const body = this.headBuf.replace(/^\s+/, "");
      if (body.indexOf("\n") < 0 && body.length < HEAD_HOLD) return "";
      this.head = false;
      this.headBuf = "";
      t = dropHeading(body);
    }
    return this.scan(t);
  }

  private scan(t: string): string {
    const i = t.search(/<!--\s*summary/i);
    if (i >= 0) {
      this.hidden = t.slice(i);
      return t.slice(0, i);
    }
    const lt = t.lastIndexOf("<");
    if (lt >= 0 && t.length - lt < MARKER_HOLD && !t.slice(lt).includes(">") && "<!--summary".startsWith(t.slice(lt).replace(/\s+/g, "").toLowerCase().slice(0, 11))) {
      this.tail = t.slice(lt);
      return t.slice(0, lt);
    }
    return t;
  }

  /** Whatever is still held back, at the end of the stream. */
  flush(): string {
    let out = "";
    if (this.head) {
      this.head = false;
      out = this.scan(dropHeading(this.headBuf.replace(/^\s+/, "")));
      this.headBuf = "";
    }
    const rest = this.tail;
    this.tail = "";
    if (this.hidden === null && /^<!--\s*summary/i.test(rest)) {
      this.hidden = rest;
      return out;
    }
    return out + rest;
  }

  /** The hidden summary text (after flush), or "". */
  summary(): string {
    const m = (this.hidden ?? "").match(/<!--\s*summary\s*:?\s*([\s\S]*?)(?:-->|$)/i);
    return m ? m[1].replace(/\s+/g, " ").trim().slice(0, 600) : "";
  }

  reset(): void {
    this.head = true;
    this.headBuf = "";
    this.tail = "";
    this.hidden = null;
  }

  /** Continuation calls append mid-section: no leading-heading check. */
  resume(): void {
    this.head = false;
    this.hidden = null;
  }
}

function dropHeading(s: string): string {
  return s.replace(/^#{1,2}\s+[^\n]*(\n|$)\s*/, "");
}

/** Removes citation tags that are not in `valid`. */
export function keepValidTags(s: string, valid: Set<string>): string {
  return s.replace(/\[([KWDG]\d+)\]/g, (m, id: string) => (valid.has(id) ? m : ""));
}

/** Final cleanup of a finished section body (outside code fences): no #/## headings, at most one picture. */
export function normalizeSection(md: string): string {
  let images = 0;
  const parts = md.split(/(```[\s\S]*?(?:```|$))/g);
  const out = parts
    .map((p, i) => {
      if (i % 2 === 1) return p;
      return p
        .replace(/^#{1,2}(\s+)/gm, "###$1")
        // "> [!NOTE]" followed by "> > text": one quote level is meant.
        .replace(/^>\s*>\s?/gm, "> ")
        .replace(/<!--\s*summary[\s\S]*?(?:-->|$)/gi, "")
        .replace(/[ \t]+([.,;:])(?=\s|$)/g, "$1")
        .replace(/\{\{image:[^}]*\}\}\n?/g, (m) => (++images > 1 ? "" : m));
    })
    .join("");
  return out.replace(/\n{3,}/g, "\n\n").trim();
}

export type RunChatFn = (candidates: string[], messages: Message[], signal: AbortSignal, hooks: RunHooks, auto: boolean) => Promise<RunResult>;
export type ImagesFn = (query: string, limit: number) => Promise<ImageResult[]>;

export type SectionEvents = {
  start(model: string): void;
  delta(text: string): void;
  reset(): void;
  notice(code: string, message: string): void;
};

export type SectionResult = {
  markdown: string;
  summary: string;
  model: string;
  finishReason: string;
  usedIds: string[];
  evidence: EvidenceItem[];
  images: DocImage[];
  words: number;
  calls: number;
};

/**
 * Streams one section. `budget()` says whether another model call (the
 * continuation) is allowed. Throws ChatFailure / AbortError on failure.
 */
export async function writeSection(args: {
  messages: Message[];
  candidates: string[];
  sources: DocSource[];
  signal: AbortSignal;
  events: SectionEvents;
  runChat: RunChatFn;
  images: ImagesFn;
  canContinue: () => boolean;
}): Promise<SectionResult> {
  const valid = new Set(args.sources.map((s) => s.id));
  const tags = new TagStream();
  const filter = new SectionFilter();
  let text = "";
  let base = "";
  let started = false;
  let calls = 0;

  const emitText = (t: string) => {
    if (!t) return;
    text += t;
    args.events.delta(t);
  };
  const hooks = (cont: boolean): RunHooks => ({
    onQueued: () => {},
    onModel: (model) => {
      if (!started) {
        started = true;
        args.events.start(model);
      }
    },
    onDelta: (chunk) => emitText(keepValidTags(filter.push(tags.push(chunk)), valid)),
    onReset: () => {
      tags.reset();
      args.events.reset();
      text = "";
      if (cont) {
        filter.resume();
        emitText(base);
      } else filter.reset();
    },
    onFallback: (from, to) => args.events.notice("fallback", `${from} failed, trying ${to}.`),
  });

  calls++;
  let result = await args.runChat(args.candidates, args.messages, args.signal, hooks(false), true);
  emitText(keepValidTags(filter.push(tags.flush()), valid));
  emitText(keepValidTags(filter.flush(), valid));
  let summary = filter.summary();

  if (result.finishReason === "length" && args.canContinue() && !args.signal.aborted) {
    base = text;
    filter.resume();
    const messages = [...args.messages, { role: "assistant" as const, content: text }, continueMessage(text.slice(-400))];
    try {
      calls++;
      const cont = await args.runChat([result.model, ...args.candidates.filter((c) => c !== result.model)], messages, args.signal, hooks(true), true);
      emitText(keepValidTags(filter.push(tags.flush()), valid));
      emitText(keepValidTags(filter.flush(), valid));
      summary = filter.summary() || summary;
      result = { ...cont, model: result.model };
    } catch (e) {
      if (args.signal.aborted) throw e;
      if (!(e instanceof ChatFailure)) throw e;
      args.events.notice("continuation_failed", "Could not continue a cut-off section; keeping what was written.");
    }
  }

  let markdown = normalizeSection(text);
  if (!markdown) throw new ChatFailure("upstream_failed", "The model returned an empty section.", true);
  const usedIds = citedIds(markdown).filter((id) => valid.has(id));
  let evidence: EvidenceItem[] = [];
  try {
    evidence = computeEvidence(markdown, args.sources.filter((s) => usedIds.includes(s.id)).map((s) => ({ id: s.id, text: s.full ?? s.text })));
  } catch {
    evidence = [];
  }
  const images: DocImage[] = [];
  const m = markdown.match(/\{\{image:([^}|]+)(?:\|([^}]*))?\}\}/);
  if (m) {
    const query = m[1].trim();
    const found = await Promise.race([
      args.images(query, 1).catch(() => [] as ImageResult[]),
      new Promise<ImageResult[]>((r) => setTimeout(() => r([]), 8_000)),
    ]);
    if (found[0]) images.push({ ...found[0], query, ...(m[2]?.trim() ? { caption: m[2].trim() } : {}) });
    else markdown = normalizeSection(markdown.replace(m[0], ""));
  }
  if (!summary) summary = fallbackSummary(markdown);
  return { markdown, summary, model: result.model, finishReason: result.finishReason, usedIds, evidence, images, words: countWords(markdown), calls };
}

/** First two plain sentences, when the model skipped its summary line. */
export function fallbackSummary(md: string): string {
  const plain = md
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/\{\{[^}]*\}\}/g, " ")
    .replace(/\[[KWDG]\d+\]/g, "")
    .replace(/^[#>|*\-\s]+/gm, "")
    .replace(/\s+/g, " ")
    .trim();
  return (plain.match(/[^.!?]+[.!?]+/g) ?? [plain]).slice(0, 2).join(" ").trim().slice(0, 400);
}
