/**
 * Intent-hint router: one short, targeted system line per request that nudges
 * the model toward the right widget. Pure and regex-based so it is cheap and
 * testable. Returns null when nothing matches. Order = priority.
 */
type Rule = { re: RegExp; hint: string };

// Only explicit asks trigger a hint: loose words ("trend", "how does X work")
// do not, so ordinary questions get ordinary answers.
const RULES: Rule[] = [
  {
    re: /\b(quiz me|test me|test my knowledge|give me a (quiz|test)|make (me )?a quiz|quiz on|mcqs?)\b/i,
    hint: "The user asked to be quizzed: a short intro line, then a ```quiz block (4-8 questions, one * correct answer each, a why: line each).",
  },
  {
    re: /\b(flash ?cards?|help me (memori[sz]e|remember)|vocab(ulary)? (list|drill))\b/i,
    hint: "The user asked for flashcards: a short intro line, then a ```flashcards block ('card: front | back' lines).",
  },
  {
    re: /\b(timeline|chronolog(y|ical))\b/i,
    hint: "The user asked for a timeline: include a ```timeline block ('when | title | detail' lines, oldest first). Only use dates you are sure of.",
  },
  {
    re: /\b(build|make|create|generate|design|code)\b[^.?!\n]{0,60}\b(html|web ?page|page|website|landing page|cheat ?sheet|reference (page|sheet|card)|dashboard|demo|mock-?up|prototype|simulation)\b/i,
    hint: "The user wants something built and shown: one complete ```html block (mobile-first, with a <title>) after a one-line intro. Use the app's design kit: semantic HTML plus kit classes (.card .grid .stack .row .label .tag .btn .btn.primary .stat .callout .chip-list) and CSS variables (--bg --surface --text --text-2 --border --accent); no custom colors, fonts, backgrounds, gradients, shadows or emoji (layout CSS is fine); icons via <iconify-icon icon='hugeicons:...'>; JS only for interactivity. Do not paste the same code again in another block.",
  },
  {
    re: /\b(calculator|calculate (my|the)|what if i|loan|mortgage|emi|bmi|compound interest|split the bill|savings plan)\b/i,
    hint: "If the user wants to play with numbers, a ```calc block (input: sliders, out: formulas) helps. Let the calculator show the results: do not restate computed totals in prose (mental arithmetic on long numbers is error-prone).",
  },
  {
    re: /\b(chart|graph|plot|visuali[sz]e (the |this |my )?(data|numbers))\b/i,
    hint: "The user asked for a chart: include a ```chart block with real data only (theirs, from sources, or well-established figures). If you do not have trustworthy numbers, ask for them with an ```ask block instead of inventing any.",
  },
  {
    re: /\b(kpis?|key metrics|scoreboard)\b/i,
    hint: "If showing the headline numbers, a ```stats block fits (stat: Label | value | delta | up/down). Real numbers only.",
  },
  {
    re: /\b(visual(ly)?|diagram|flow ?chart|step[- ]by[- ]step|walk me through|pipeline|lifecycle)\b/i,
    hint: "The user wants a visual/stepwise explanation: right after your opening sentence, a ```flow block (3-6 stages) if the topic is a linear process; use mermaid for branching graphs.",
  },
  {
    re: /\b(checklist|to-?do list|packing list|task list)\b/i,
    hint: "The user asked for a checklist: a ```checklist block ('[ ] item' lines).",
  },
];

const CASUAL_RE = /\b(bro|bruh|dude|yo|mate|fam|bruv|sis)\b/i;

/** Casual when the user writes slang such as "bro" or "yo". */
function looksCasual(text: string): boolean {
  // Slang decides it; lowercase typing alone is not a request for a casual tone.
  return CASUAL_RE.test(text);
}

export function intentHint(text: string): string | null {
  const t = (text ?? "").trim().slice(0, 600);
  if (!t) return null;
  const hits: string[] = [];
  for (const r of RULES) {
    if (r.re.test(t)) {
      hits.push(r.hint);
      break;
    }
  }
  if (looksCasual(t)) {
    hits.push(
      'The user is casual: your very first sentence is a short casual opener in their voice (for example "Bro, ..."), before any heading, flow or widget.',
    );
  }
  return hits.length ? `Hint for this reply: ${hits.join(" ")}` : null;
}
