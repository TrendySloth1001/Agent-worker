/**
 * Does this question depend on facts that change over time? Then the answer
 * should be grounded in a live web search even if the user did not turn it on,
 * so the model does not answer from stale memory.
 */

/** Any one of these means the answer can be out of date. */
const STRONG = [
  /\b(latest|newest|current(ly)?|recent(ly)?|up[- ]to[- ]date|nowadays|right now|as of now|these days)\b/i,
  /\b(today|tonight|yesterday|tomorrow|this (week|month|year|season)|last (week|month|year)|next (week|month|year))\b/i,
  /\b(news|headlines?|release date|roadmap|changelog|deprecat\w*|end of life|eol|still supported)\b/i,
  /\b(price|pricing|how much (is|does|do)|salary|stock price|share price|market cap|exchange rate|free tier)\b/i,
  /\b(weather|forecast|scores?|election|polls?)\b/i,
  /\b(who is|who's) (the )?(ceo|cto|president|prime minister|founder|owner|head|leader|captain|coach)\b/i,
  /\bwhat('s| is)? new\b|\bwhat (has )?changed\b/i,
  /\b20(2[4-9]|3\d)\b/,
];

/** These suggest recency only outside a conceptual how-to question. */
const WEAK = [/\b(version|released?|launch(ed)?|announced?|update[sd]?)\b/i];

const CONCEPTUAL = /\b(explain|what does|how (do|does|to)|difference between|write|fix|debug|refactor|implement|example of)\b/i;

export function needsFreshFacts(question: string): boolean {
  const q = question.trim();
  if (q.length < 8) return false;
  if (STRONG.some((re) => re.test(q))) return true;
  return WEAK.some((re) => re.test(q)) && !CONCEPTUAL.test(q);
}
