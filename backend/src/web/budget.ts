// Evidence budgeting for web search: skip fetching pages whose snippet already
// answers, and keep the prompt's web sources within a total token budget by
// cutting each source down to its passages that matter for the question.
// Pure functions.
import { selectPassages, terms } from "./passages.js";

/** About 2.5k tokens of web evidence per turn. */
export const WEB_BUDGET_CHARS = 10_000;
const MIN_PER_ITEM = 350;
const GENERIC = new Set(["work", "works", "working", "use", "using", "way", "make", "get", "tutorial", "guide", "example", "examples", "news", "today"]);

/** Whether a hit's own text already covers the question, so fetching the full page would add little. */
export function snippetAnswers(c: { snippet: string; text?: string }, focus: string): boolean {
  const body = c.text && c.text.length > c.snippet.length ? c.text : c.snippet;
  if (body.length < 350) return false;
  const q = [...new Set(terms(focus.replace(/\b20\d\d\b/g, " ")).filter((t) => !GENERIC.has(t)))];
  if (!q.length) return false;
  const have = new Set(terms(body));
  return q.filter((t) => have.has(t)).length / q.length >= 0.7;
}

/**
 * Cuts the sources (best first) to fit [budgetChars] in total: earlier sources
 * keep more room, each is reduced to its passages relevant to [focus]. Sources
 * already small enough are untouched; nothing is dropped.
 */
export function fitBudget<T extends { text: string; full?: string }>(items: T[], focus: string, budgetChars = WEB_BUDGET_CHARS): T[] {
  const total = items.reduce((n, i) => n + i.text.length, 0);
  if (total <= budgetChars || items.length === 0) return items;
  const weights = items.map((_, i) => 1 / (1 + i * 0.35));
  const sum = weights.reduce((a, b) => a + b, 0);
  return items.map((item, i) => {
    const share = Math.max(MIN_PER_ITEM, Math.floor((budgetChars * weights[i]) / sum));
    if (item.text.length <= share) return item;
    const source = item.full && item.full.length > item.text.length ? item.full : item.text;
    return { ...item, text: selectPassages(source, focus, { maxChars: share, maxPassages: 3, passageLen: Math.min(600, share) }) };
  });
}
