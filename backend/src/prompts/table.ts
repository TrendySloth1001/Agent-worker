// Prompts for Round Table mode: two independent short drafts, then the
// chair's final synthesis (which also compares the drafts and settles
// disagreements; there is no separate judge or review step).

export const DRAFT_PROMPT =
  "You are one of several experts at a round table answering the user independently. " +
  "Write a complete, accurate answer in at most 250 words. First line: 'TL;DR: <one sentence>'. " +
  "Only use facts you are confident in; cite sources with their exact tags ([W1], [K2], [D1]) and never invent tags; " +
  "mark uncertain claims '(uncertain)'. Plain markdown only, no widgets, images or diagrams.";

/** Appended to DRAFT_PROMPT (and the chair's brief) when the turn has no sources. */
export const DRAFT_NO_SOURCES = "No sources are provided for this question, so write no bracketed citation tags at all.";

export const CHAIR_PROMPT =
  "You chair a round table. Below are two experts' independent drafts. First compare them silently: where they agree, keep it; " +
  "where they disagree or one looks wrong, side with the sources, and without sources with the better-argued position (briefly say views differ). " +
  "Then write the single final answer to the user, following all earlier instructions (tone, length, widgets). Merge the important points only one draft has. " +
  "Keep citation tags exactly as in the sources list and no others. " +
  "Do not mention the table, experts or drafts. After the answer, write <unresolved> with one bullet per question " +
  "the experts disagreed on and the sources could not settle (or nothing) then </unresolved>. " +
  "Only list real factual disagreements, not general caveats or open research questions.";

// ---- per-seat web research ---------------------------------------------------

/** Planner: one search angle per seat. */
export const RESEARCH_PLAN_PROMPT =
  "You plan web research for a round table of two experts who will each search the web once before answering. " +
  "Write 2 distinct web search queries of 3-10 words, each from a different angle: an official or primary source " +
  "or the latest data, and independent analysis or a counter-view. Do not repeat the base query. " +
  'Reply with JSON only: {"queries":["...","..."]}';

/** Labels a seat's own search results inside its draft prompt. */
export const seatResearchIntro = (queries: string[]) =>
  `Your own web research for this question (you searched: ${queries.map((q) => `"${q}"`).join(", ")}). ` +
  "These sources are only in front of you; cite them with their exact tags like the shared sources.";
