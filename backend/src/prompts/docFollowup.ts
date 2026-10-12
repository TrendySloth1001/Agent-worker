// Prompts for reader follow-ups in DOC mode: ASK AI on a selection, selection
// edits (explain / simplify / expand / cite / rewrite) and "continue writing".
import type { Message } from "../providers.js";
import type { SelectionOp } from "../docs/types.js";

export type AskPromptInput = {
  preamble: string;
  title: string;
  heading: string;
  /** The section's markdown (clipped by the caller). */
  section: string;
  quote: string;
  question: string;
  /** Earlier questions and answers about the same passage, oldest first. */
  thread: Array<{ q: string; a: string }>;
  /** The <web_results>… block with the citation rule, or null. */
  context: string | null;
  validTags: string[];
};

/** A reader's question about a passage: answered in a few sentences, never a rewrite of the section. */
export function askMessages(i: AskPromptInput): Message[] {
  const tags = i.validTags.length ? i.validTags.join(", ") : "none";
  const system = `You answer a reader's question about a passage in a long-form document ("${i.title}", section "${i.heading}"). ${i.preamble}
- Answer the question directly and concisely (usually 2-6 sentences; more only if the question needs it). Do NOT rewrite or continue the document.
- Ground the answer in the passage and the section; you may add general knowledge, but say so when you are unsure. Never invent facts, numbers or quotes.
- Cite sources only with these tags when they support a sentence: ${tags}. Never invent tags.
- Markdown allowed (lists, bold, inline code). No headings, no greeting, no emoji, no "Great question".`;
  const messages: Message[] = [{ role: "system", content: system }, { role: "system", content: `Section "${i.heading}":\n"""\n${i.section}\n"""` }];
  if (i.context) messages.push({ role: "system", content: i.context });
  for (const t of i.thread) {
    messages.push({ role: "user", content: t.q });
    messages.push({ role: "assistant", content: t.a });
  }
  messages.push({ role: "user", content: `Passage the reader selected:\n"""\n${i.quote.trim()}\n"""\n\nQuestion: ${i.question.trim()}` });
  return messages;
}

export type SelectionPromptInput = {
  preamble: string;
  title: string;
  heading: string;
  op: SelectionOp;
  /** The selected passage as it appears in the section's Markdown. */
  passage: string;
  /** Text around the passage, for context only. */
  before: string;
  after: string;
  instruction?: string;
  context: string | null;
  validTags: string[];
};

const SELECTION_RULES: Record<SelectionOp, string> = {
  explain: "Write a short explanation (1-3 sentences) of what the passage means, for a reader who does not know the background: define jargon, give the why. Output ONLY the explanation text, not the passage.",
  simplify: "Rewrite the passage in simpler, plainer language: shorter sentences, define jargon, keep every fact and citation tag. Output ONLY the rewritten passage.",
  expand: "Expand the passage to roughly 1.6-2x its length with depth, a concrete example or detail, keeping what is there and its citation tags. Output ONLY the expanded passage.",
  cite: "Add citation tags to the passage where a source supports a statement. Do not change the wording otherwise; keep tags already there. Output ONLY the passage with tags added.",
  rewrite: "Rewrite the passage following the user's instruction, keeping facts and citation tags unless told otherwise. Output ONLY the rewritten passage.",
};

export function selectionMessages(i: SelectionPromptInput): Message[] {
  const tags = i.validTags.length ? i.validTags.join(", ") : "none";
  const system = `You edit one passage of a long-form document ("${i.title}", section "${i.heading}"). ${i.preamble}
${SELECTION_RULES[i.op]}
- Keep the passage's Markdown style (inline marks, lists, tables). No headings unless the passage has them. No code fence around your output, no preface, no quotes around it.
- Valid citation tags: ${tags}. Use only these; never invent tags, facts, numbers or quotes. No emoji.`;
  const messages: Message[] = [{ role: "system", content: system }];
  if (i.context) messages.push({ role: "system", content: i.context });
  const task = [`Text before the passage (context only):\n"""\n${i.before}\n"""`, `Text after the passage (context only):\n"""\n${i.after}\n"""`, `PASSAGE:\n"""\n${i.passage}\n"""`];
  if (i.instruction) task.push(`User instruction: ${i.instruction.trim()}`);
  messages.push({ role: "user", content: task.join("\n\n") });
  return messages;
}

/** Asks for the heading and goal of one more section that fits the document. */
export function continueMessages(title: string, outline: Array<{ heading: string; goal: string }>, hint: string | undefined, preamble: string): Message[] {
  return [
    {
      role: "system",
      content: `You plan the next section of a long-form document. ${preamble} Return ONLY JSON: {"heading":"2-7 words, no numbering","goal":"one sentence saying what the reader will understand after it","keyPoints":["3-4 concrete points"]}. It must not repeat an existing section.`,
    },
    { role: "user", content: `Document: ${title}\n\nExisting sections:\n${outline.map((s, n) => `${n + 1}. ${s.heading} - ${s.goal}`).join("\n")}${hint ? `\n\nThe reader wants the next section to cover: ${hint.trim()}` : ""}` },
  ];
}
