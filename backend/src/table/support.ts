// "Who agreed": for each sentence of the chair's answer, which seats' drafts
// back it. Lexical overlap with the evidence scorer (web/evidence.ts), so it
// is pure CPU and adds no model calls.

import { bestPassage, buildIndex, splitSentences, stripFences, type Index } from "../web/evidence.js";

export type SupportItem = {
  /** The answer sentence, markup stripped. */
  sentence: string;
  /** Paragraph (block) index in the answer, counting non-empty blocks. */
  paragraph: number;
  /** Seats whose draft makes the same claim, e.g. ["A", "C"]. */
  seats: string[];
  /** A reviewer, the agreement check or the open questions disputed it. */
  disputed?: boolean;
  /** The matching passage of each supporting seat's draft. */
  excerpts: Record<string, string>;
};

const SUPPORT_MIN = 0.45;
const DISPUTE_MIN = 0.55;
const MIN_CHARS = 25;
const MAX_ITEMS = 40;
const MAX_SENTENCE = 300;

/** Plain text of an answer line: no widgets, icons, tags or markdown. */
function plain(s: string): string {
  return s
    .replace(/\{\{[^}]*\}\}/g, "")
    .replace(/\s*\[[KWDG]\d+\]/g, "")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\*+|__|`/g, "")
    .replace(/^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ x]\]\s*)?/i, "")
    .replace(/^\s*>\s*/, "")
    .replace(/\s+/g, " ")
    .trim();
}

const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1).trimEnd()}…` : s);

export function computeSupport(answer: string, drafts: { seat: string; text: string }[], disputes: string[]): SupportItem[] {
  if (drafts.length === 0 || !answer.trim()) return [];
  const indexes = drafts.map((d) => ({ seat: d.seat, idx: buildIndex(d.text) }));
  const out: SupportItem[] = [];
  const blocks = stripFences(answer)
    .split(/\n\s*\n/)
    .map((b) => b.trim())
    .filter(Boolean);
  blocks.forEach((block, paragraph) => {
    for (const line of block.split("\n")) {
      // Headings, tables and rules are structure, not claims.
      if (/^\s*(#|\||---|<)/.test(line.replace(/\{\{[^}]*\}\}\s*/g, ""))) continue;
      for (const raw of splitSentences(plain(line))) {
        if (out.length >= MAX_ITEMS) return;
        if (raw.length < MIN_CHARS || raw.split(" ").length < 5) continue;
        // A closing offer ("Want a code sketch…?") is not a claim.
        if (/\?$/.test(raw) && /\b(you|your)\b/i.test(raw)) continue;
        const seats: string[] = [];
        const excerpts: Record<string, string> = {};
        for (const { seat, idx } of indexes) {
          const hit = bestPassage(raw, idx);
          if (hit && hit.score >= SUPPORT_MIN) {
            seats.push(seat);
            excerpts[seat] = hit.quote;
          }
        }
        const own: Index = buildIndex(raw.length >= 30 ? raw : `${raw} ${raw}`);
        const disputed = disputes.some((d) => (bestPassage(d, own)?.score ?? 0) >= DISPUTE_MIN);
        out.push({ sentence: clip(raw, MAX_SENTENCE), paragraph, seats, ...(disputed ? { disputed } : {}), excerpts });
      }
    }
  });
  return out;
}
