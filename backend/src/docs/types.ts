// Shared types for DOC mode (long-form cited documents, docs/DOCS_MODE.md).
import type { EvidenceItem } from "../web/evidence.js";
import type { ImageResult } from "../web/images.js";

export const DOC_LENGTHS = ["short", "standard", "long"] as const;
export type DocLength = (typeof DOC_LENGTHS)[number];

export const DOC_STATUSES = ["planning", "outline_ready", "researching", "writing", "done", "partial", "failed", "interrupted"] as const;
export type DocStatus = (typeof DOC_STATUSES)[number];
export type SectionStatus = "pending" | "writing" | "done" | "failed";

export const VISUALS = ["none", "mermaid", "table", "image", "math"] as const;
export type Visual = (typeof VISUALS)[number];
export const STYLES = ["report", "guide", "explainer", "tutorial", "brief"] as const;
export type DocStyle = (typeof STYLES)[number];

export const REWRITE_OPS = ["regenerate", "expand", "shorten", "simplify", "custom"] as const;
export type RewriteOp = (typeof REWRITE_OPS)[number];
export type RevisionReason = "generate" | RewriteOp | "edit";

/** Section ids the server appends to every outline. */
export const TAKEAWAYS_ID = "takeaways";
export const REFERENCES_ID = "references";

export type OutlineSection = {
  id: string;
  heading: string;
  goal: string;
  keyPoints: string[];
  queries: string[];
  visual: Visual;
  words: number;
  /** Planner's brief for the writer: style and evidence guidance for this section only. */
  notes?: string;
  /** Glossary terms this section uses (the writer sees only these definitions). */
  terms?: string[];
  /** Set on the two server-built sections. */
  kind?: "takeaways" | "references";
};

export type Outline = {
  title: string;
  subtitle: string;
  audience: string;
  style: DocStyle;
  sections: OutlineSection[];
};

export type GlossaryItem = { term: string; definition: string };

/** Same shape as the chat Citation (routes/chat.ts). */
export type Citation = {
  id: string;
  kind: "kb" | "web" | "file";
  title: string;
  url: string;
  snippet: string;
  site: string;
  sourceType?: string;
};

/** A citation plus the text the model saw (`text`) and the longer text used for evidence (`full`). Server-only fields. */
export type DocSource = Citation & { text: string; full?: string };

export type DocImage = ImageResult & { query: string; caption?: string };

export type DocSection = {
  sectionId: string;
  ord: number;
  heading: string;
  level: number;
  markdown: string;
  summary: string;
  status: SectionStatus;
  sourceIds: string[];
  usedIds: string[];
  evidence: EvidenceItem[];
  images: DocImage[];
  model: string | null;
  words: number;
  updatedAt: string;
};

export type DocOptions = {
  length: DocLength;
  web: boolean;
  kb: boolean;
  sourceIds?: string[];
  model?: string;
  attachments?: string[];
  profile?: Record<string, unknown>;
  reviewOutline?: boolean;
  /** The conversation id the client sent (kept even when that chat is not saved yet). */
  conversationId?: string;
  /** Short rendering of the chat this doc was requested from (src/context), used in the planning and section prompts. */
  chatContext?: string;
  /** Ids of the doc-wide base search results (server-only bookkeeping). */
  sharedIds?: string[];
};

export type DocState = {
  id: string;
  userId: string;
  conversationId: string | null;
  title: string;
  prompt: string;
  options: DocOptions;
  status: DocStatus;
  outline: Outline | null;
  glossary: GlossaryItem[];
  sources: DocSource[];
  /** One-paragraph abstract (written at the end). */
  summary: string;
  words: number;
  version: number;
  createdAt: string;
  updatedAt: string;
  sections: DocSection[];
};

/** One question asked about a highlighted passage, with the model's answer. */
export type QaEntry = { id: string; q: string; a: string; at: string };

export const SELECTION_OPS = ["explain", "simplify", "expand", "cite", "rewrite"] as const;
export type SelectionOp = (typeof SELECTION_OPS)[number];

export type Highlight = {
  id: string;
  docId: string;
  sectionId: string;
  quote: string;
  prefix: string;
  suffix: string;
  color: string;
  note: string | null;
  thread: QaEntry[];
  createdAt: string;
};

export type Revision = { version: number; markdown: string; reason: RevisionReason; createdAt: string };

export const countWords = (md: string) =>
  (md
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/\{\{[^}]*\}\}/g, " ")
    .replace(/\[[KWDG]\d+\]/g, " ")
    .match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) ?? []).length;

/** Tags cited in `text`, first use first. */
export const citedIds = (text: string) => [...new Set([...text.matchAll(/\[([KWDG]\d+)\]/g)].map((m) => m[1]))];

/** What clients see: no server-only source text, no user id. */
export function publicDoc(d: DocState, running: boolean) {
  const { userId: _u, sources, outline, ...rest } = d;
  return {
    ...rest,
    subtitle: outline?.subtitle ?? "",
    outline,
    sources: sources.map(publicSource),
    running,
  };
}

export const publicSource = ({ text: _t, full: _f, ...c }: DocSource): Citation => c;

export type DocSummary = {
  id: string;
  title: string;
  status: DocStatus;
  words: number;
  sections: number;
  conversationId: string | null;
  createdAt: string;
  updatedAt: string;
};
