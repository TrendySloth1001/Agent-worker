// Prompts for DOC mode (docs/DOCS_MODE.md): outline, sections, rewrites, finish.
import type { Message } from "../providers.js";
import type { DocLength, DocStyle, GlossaryItem, Outline, OutlineSection, RewriteOp } from "../docs/types.js";

export const SECTION_COUNT: Record<DocLength, { min: number; max: number }> = {
  short: { min: 4, max: 4 },
  standard: { min: 6, max: 8 },
  long: { min: 10, max: 10 },
};

const clip = (s: string, n: number) => (s.length <= n ? s : s.slice(0, n - 1) + "…");
const oneLine = (s: string) => s.replace(/\s+/g, " ").trim();

export type OutlineContext = {
  web: Array<{ id: string; title: string; url: string; text: string }>;
  kb: Array<{ id: string; title: string; text: string }>;
  files: Array<{ id: string; title: string; text: string }>;
};

export function outlineMessages(prompt: string, length: DocLength, ctx: OutlineContext, preamble: string): Message[] {
  const n = SECTION_COUNT[length];
  const count = n.min === n.max ? `exactly ${n.min}` : `${n.min} to ${n.max}`;
  const system = `You plan long-form, well-researched documents. Given a request, design the document's outline. ${preamble}

Return ONLY a JSON object, no prose and no code fence, in this shape:
{"title":"","subtitle":"","audience":"","style":"report|guide|explainer|tutorial|brief",
 "glossary":[{"term":"","definition":""}],
 "sections":[{"id":"s1","heading":"","goal":"one sentence","keyPoints":["…"],"queries":["web search query"],"visual":"none|mermaid|table|image|math","words":250}]}

Rules:
- ${count} body sections, in a logical reading order (foundations first, advanced topics later). Do NOT include an introduction-only, "Conclusion", "Summary", "Key takeaways" or "References" section; the app adds takeaways and references itself.
- Each heading is short and specific (2-7 words, no numbering). Each goal is one sentence saying what the reader will understand after the section. 3-5 keyPoints per section, concrete and non-overlapping across sections.
- "queries": 1-2 precise web search queries per section that would find authoritative facts for it (specs, docs, papers, reputable explainers).
- "visual": choose the one visual that genuinely helps that section: "mermaid" for a process, protocol exchange or architecture; "table" for comparisons; "math" for formulas; "image" for something with a recognizable picture; otherwise "none". Use mermaid at most twice in the whole document.
- "words": 250-900 per section; important sections get more.
- glossary: 3-8 key terms the reader needs, one-sentence definitions.
- title: a clear document title; subtitle: one line saying what the document covers and for whom.`;

  const blocks: string[] = [`Request: ${prompt.trim()}`, `Length: ${length}`];
  if (ctx.web.length) blocks.push(`Background search results (for planning only):\n${ctx.web.map((w) => `- ${w.title} (${w.url}): ${clip(oneLine(w.text), 300)}`).join("\n")}`);
  if (ctx.kb.length) blocks.push(`From the user's knowledge base:\n${ctx.kb.map((k) => `- ${k.title}: ${clip(oneLine(k.text), 200)}`).join("\n")}`);
  if (ctx.files.length) blocks.push(`Attached documents:\n${ctx.files.map((f) => `- ${f.title}: ${clip(oneLine(f.text), 400)}`).join("\n")}`);
  blocks.push("Return the JSON outline now.");
  return [
    { role: "system", content: system },
    { role: "user", content: blocks.join("\n\n") },
  ];
}

const STYLE_CARDS: Record<DocStyle, string> = {
  report: "Style: REPORT. Formal, evidence-led, precise. Lead with findings, support each with sourced facts and numbers, note uncertainty and limits.",
  guide: "Style: GUIDE. Practical and direct. Explain what to do and why, with concrete steps, examples and pitfalls. Address the reader as \"you\".",
  explainer: "Style: EXPLAINER. Build intuition first, then precise detail. Use one apt analogy where it helps, then concrete examples with real values.",
  tutorial: "Style: TUTORIAL. Step by step, hands-on. Numbered steps, small runnable examples, expected results, and what to check when something fails.",
  brief: "Style: BRIEF. Dense and executive. Short paragraphs, the key facts and implications first, no filler.",
};

export type SectionPromptInput = {
  preamble: string;
  outline: Outline;
  glossary: GlossaryItem[];
  section: OutlineSection;
  /** Summaries of finished sections, in document order. */
  summaries: Array<{ heading: string; summary: string }>;
  /** The <web_results>/<knowledge>/<documents> block with the citation rule (buildContextMessage), or null. */
  context: string | null;
  validTags: string[];
  rewrite?: { op: RewriteOp; current: string; instruction?: string; selection?: string };
};

function visualRule(v: OutlineSection["visual"]): string {
  switch (v) {
    case "mermaid":
      return 'Include exactly one small ```mermaid diagram where it explains best. Use only flowchart, sequenceDiagram, stateDiagram-v2, classDiagram, erDiagram or gantt, and put every node label in double quotes, e.g. A["Client"] --> B["Server"]. Keep it readable on a phone (max ~10 nodes).';
    case "table":
      return "Include one markdown comparison table where it helps (3-6 rows, short cells, citation tags inside cells are fine).";
    case "math":
      return "Write formulas in TeX: inline as $...$, display on their own lines as $$...$$. Explain every symbol.";
    case "image":
      return "Put at most one picture on its own line where it belongs: {{image:SHORT PLAIN DESCRIPTION|caption}} (e.g. {{image:TLS handshake diagram|The TLS 1.3 handshake}}). The app finds a matching picture.";
    default:
      return "No diagrams or pictures in this section; use prose, lists and at most one small table if truly needed.";
  }
}

const REWRITE_RULES: Record<RewriteOp, string> = {
  regenerate: "Write this section afresh (a new, better version), following all the rules.",
  expand: "Expand the current version to roughly 1.6x its length: add depth, examples and detail, keep what is already good, keep its citations.",
  shorten: "Shorten the current version to roughly 60% of its length: keep the most important points and their citations, cut repetition and filler.",
  simplify: "Rewrite the current version in simpler, plainer language for a non-expert reader: shorter sentences, define jargon, keep facts and citations.",
  custom: "Revise the current version following the user's instruction below. Keep everything the instruction does not ask to change, including citations.",
};

export function sectionMessages(input: SectionPromptInput): Message[] {
  const { outline, section } = input;
  const body = outline.sections.filter((s) => !s.kind);
  const k = body.findIndex((s) => s.id === section.id);
  const plan = body
    .map((s, i) => `${i === k ? "YOU WRITE: " : ""}§${i + 1} ${s.heading} - ${s.goal}`)
    .join("\n");
  const later = body.slice(k + 1).map((s) => `- §${body.indexOf(s) + 1} ${s.heading}: ${s.goal}`);
  const tags = input.validTags.length ? input.validTags.join(", ") : "none";

  const system = `You are writing ONE section of a long-form, cited document. ${input.preamble}

${STYLE_CARDS[outline.style] ?? STYLE_CARDS.report}
Audience: ${outline.audience || "curious, technically literate readers"}.

Rules:
- Output ONLY the section body in Markdown. Do NOT write the section heading (the app inserts "## ${section.heading}"); use ### subheadings if the section needs them, never # or ##.
- Every sentence that states a fact from the sources ends with its tag, placed before the final punctuation, e.g. "TLS 1.3 removed RSA key exchange [W3]." Valid tags for this section: ${tags}. Use only these tags, one or two per sentence; never invent tags, never write bare numbers like [1], never add a "Sources" list. If the sources do not cover something, write it from your own knowledge without a tag, and never invent facts, numbers, versions, dates or quotes.
- ${visualRule(section.visual)}
- Callouts, when useful (at most one): a line "> [!NOTE]" or "> [!WARNING]" followed by "> " lines.
- No emoji. No "In conclusion", "In summary" or "Overall" wrap-ups, no greeting, no meta talk about the document ("In this section we will").
- Stay within this section's goal; do not cover topics that belong to later sections.
- The very last line must be an HTML comment with a two-sentence summary of what this section established (it is hidden from the reader and helps the writers of later sections): <!--summary: two sentences-->`;

  const ctx: string[] = [
    `Document: ${outline.title}${outline.subtitle ? ` - ${outline.subtitle}` : ""}`,
    `Outline:\n${plan}`,
  ];
  if (input.glossary.length) ctx.push(`Glossary (use these terms consistently):\n${input.glossary.map((g) => `- ${g.term}: ${g.definition}`).join("\n")}`);
  if (input.summaries.length) ctx.push(`Already written (do not repeat):\n${input.summaries.map((s) => `- ${s.heading}: ${s.summary}`).join("\n")}`);
  if (later.length) ctx.push(`Covered later by other sections (do not cover these here):\n${later.join("\n")}`);

  const messages: Message[] = [
    { role: "system", content: system },
    { role: "system", content: ctx.join("\n\n") },
  ];
  if (input.context) messages.push({ role: "system", content: input.context });

  const task = [
    `Write §${k + 1}: ${section.heading}`,
    `Goal: ${section.goal}`,
    section.keyPoints.length ? `Key points:\n${section.keyPoints.map((p) => `- ${p}`).join("\n")}` : "",
    `Target length: about ${section.words} words.`,
  ].filter(Boolean);
  if (input.rewrite) {
    const r = input.rewrite;
    task.push(REWRITE_RULES[r.op]);
    if (r.op !== "regenerate") task.push(`Current version:\n"""\n${r.current.trim()}\n"""`);
    if (r.instruction) task.push(`User instruction: ${r.instruction.trim()}`);
    if (r.selection) task.push(`Apply the change only to this passage (keep the rest of the section as it is):\n"""\n${r.selection.trim()}\n"""`);
    task.push("Output the complete new section body, ending with the <!--summary: ...--> line.");
  }
  messages.push({ role: "user", content: task.join("\n\n") });
  return messages;
}

export function continueMessage(tail: string): Message {
  return {
    role: "user",
    content: `You were cut off. Continue exactly from where you stopped; the text so far ends with:\n"""\n${tail}\n"""\nDo not repeat any of it (continue mid-sentence if needed), keep the same rules, and finish the section with the <!--summary: two sentences--> line.`,
  };
}

export function finishMessages(title: string, summaries: Array<{ heading: string; summary: string }>, preamble: string): Message[] {
  return [
    {
      role: "system",
      content: `You finish a long-form document. ${preamble} Return ONLY JSON: {"takeaways":["3-5 crisp, specific key takeaways, one sentence each"],"abstract":"one paragraph (3-5 sentences) abstract of the whole document"}. No citation tags, no emoji.`,
    },
    { role: "user", content: `Document: ${title}\n\nSection summaries:\n${summaries.map((s) => `- ${s.heading}: ${s.summary}`).join("\n")}` },
  ];
}
