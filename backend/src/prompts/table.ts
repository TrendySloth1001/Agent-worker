// Prompts for Round Table mode: independent drafts, an agreement check,
// cross-review, and the chair's final synthesis.

export const DRAFT_PROMPT =
  "You are one of several experts at a round table answering the user independently. " +
  "Write a complete, accurate answer in at most 350 words. First line: 'TL;DR: <one sentence>'. " +
  "Only use facts you are confident in; cite sources with their exact tags ([W1], [K2], [D1]) and never invent tags; " +
  "mark uncertain claims '(uncertain)'. Plain markdown only, no widgets, images or diagrams.";

/** Appended to DRAFT_PROMPT (and the chair's brief) when the turn has no sources. */
export const DRAFT_NO_SOURCES = "No sources are provided for this question, so write no bracketed citation tags at all.";

export const REVIEW_PROMPT =
  "You are an expert at a round table. Other experts answered the user's question independently; their drafts are below. " +
  "Review the OTHER drafts (not your own) for factual errors, disagreements with the sources or with your own knowledge, and important missing points. " +
  "Check claims against the sources when sources are given. Ignore style, wording, length and formatting: no nitpicks. " +
  "Reply with JSON only, no prose and no code fences: " +
  '{"verdict":"agree|minor|major","points":[{"seat":"<letter of the draft the point is about>","kind":"error|disagree|missing","claim":"<the claim, at most 20 words>","detail":"<why, at most 40 words>","sources":["<tags like W1, if any>"]}]}. ' +
  "At most 6 points, most important first. If the drafts are correct and consistent, reply " +
  '{"verdict":"agree","points":[]}.';

export const JUDGE_PROMPT =
  "Do these answers make the same key factual claims and recommendations? Ignore wording and length. " +
  'JSON only: {"agree":bool,"conflicts":["<≤15 words each>"]}';

export const CHAIR_PROMPT =
  "You chair a round table. Below are the experts' drafts and their reviews. Write the single final answer to the user, " +
  "following all earlier instructions (tone, length, widgets). Fix every point the reviewers proved wrong. " +
  "Where experts disagree, side with the sources; without sources, side with the better-argued position and briefly say views differ. " +
  "Merge the missing points that matter. Keep citation tags exactly as in the sources list and no others. " +
  "Do not mention the table, experts or drafts. After the answer, write <unresolved> with one bullet per question " +
  "the table could not settle (or nothing) then </unresolved>. " +
  "Only list real factual disagreements between the experts that the sources and reviews could not settle, not general caveats or open research questions.";
