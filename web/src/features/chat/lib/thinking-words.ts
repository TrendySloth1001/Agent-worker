const MAX_LENGTH = 22;
const ELLIPSIS = "…";
const GENERAL = "general";

const KEYWORDS: Record<string, string[]> = {
  code: ["code", "bug", "function", "flutter", "dart", "python", "java", "script", "api", "error", "compile", "debug", "sql", "regex", "app", "class", "git", "html", "css", "react", "server"],
  math: ["math", "calcul", "equation", "solve", "number", "sum", "percent", "algebra", "integral", "derivative", "probab", "statistic", "average", "formula", "geometry"],
  travel: ["travel", "trip", "flight", "hotel", "visit", "itinerary", "tour", "vacation", "holiday", "train", "route", "city", "country", "beach"],
  food: ["recipe", "cook", "food", "eat", "dinner", "lunch", "breakfast", "bake", "meal", "ingredient", "restaurant", "diet", "snack", "curry"],
  writing: ["write", "essay", "email", "story", "poem", "letter", "draft", "summar", "rewrite", "blog", "caption", "article", "translate", "speech", "resume", "outline"],
};

const STEMS: Record<string, string[]> = {
  general: ["Ponder", "Untangl", "Mull", "Mus", "Weigh", "Connect", "Gather", "Sift", "Brew", "Chas", "Piec", "Hatch", "Simmer", "Ruminat", "Percolat", "Cogitat", "Daydream", "Wonder"],
  code: ["Debugg", "Compil", "Pars", "Refactor", "Trac", "Stitch", "Lint", "Hack", "Unravel", "Patch"],
  math: ["Crunch", "Comput", "Add", "Factor", "Deriv", "Graph", "Solv", "Estimat", "Tally"],
  travel: ["Mapp", "Rout", "Wander", "Scout", "Pack", "Chart", "Explor", "Navigat"],
  food: ["Season", "Stirr", "Whisk", "Tast", "Marinat", "Sizzl", "Simmer"],
  writing: ["Draft", "Sketch", "Polish", "Phras", "Word", "Shap", "Edit", "Outlin"],
};

const OBJECTS: Record<string, string[]> = {
  general: ["ideas", "thoughts", "it over", "the angles", "options"],
  code: ["the logic", "the stack", "some code", "the bits"],
  math: ["numbers", "the maths", "the figures"],
  travel: ["a route", "the map", "the options"],
  food: ["a flavour", "the recipe", "ideas"],
  writing: ["an outline", "some words", "a draft", "the tone"],
};

const ADVERBS = ["Gently", "Carefully", "Quietly", "Happily", "Slowly", "Briefly", "Warmly", "Keenly"];
const FIXED = ["Thinking", "One moment", "On it", "Hmm"];

export function seedOf(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h = Math.imul(h ^ text.charCodeAt(i), 0x01000193) >>> 0;
  }
  return h;
}

function random(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function topicOf(prompt: string | undefined): string {
  const words = (prompt ?? "").toLowerCase().match(/[a-z]+/g) ?? [];
  let best = GENERAL;
  let bestScore = 0;
  for (const [topic, prefixes] of Object.entries(KEYWORDS)) {
    const score = words.filter((w) => prefixes.some((p) => w.startsWith(p))).length;
    if (score > bestScore) {
      best = topic;
      bestScore = score;
    }
  }
  return best;
}

export function pool(topic: string): string[] {
  const extra = topic === GENERAL ? [] : [GENERAL];
  const stems = [topic, ...extra].flatMap((t) => STEMS[t] ?? []);
  const objects = [topic, ...extra].flatMap((t) => OBJECTS[t] ?? []);
  const out = new Set<string>();
  for (const stem of stems) {
    const verb = `${stem}ing`;
    out.add(verb + ELLIPSIS);
    for (const o of objects) out.add(`${verb} ${o}${ELLIPSIS}`);
    for (const a of ADVERBS) out.add(`${a} ${verb.toLowerCase()}${ELLIPSIS}`);
  }
  for (const f of FIXED) out.add(f + ELLIPSIS);
  return [...out].filter((l) => l.length <= MAX_LENGTH);
}

const sessionUsed = new Set<string>();

export function nextThinkingWord(prompt: string | undefined, used: Set<string> = sessionUsed): string {
  const topic = topicOf(prompt);
  const stems = (STEMS[topic] ?? []).map((s) => s.toLowerCase());
  const topical = (line: string) =>
    topic !== GENERAL && stems.some((s) => line.toLowerCase().includes(s));
  const all = pool(topic).sort();
  const rand = random(seedOf(prompt ?? "") + used.size);
  for (let i = all.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [all[i], all[j]] = [all[j] as string, all[i] as string];
  }
  const ordered = [...all.filter(topical), ...all.filter((l) => !topical(l))];
  let fresh = ordered.filter((l) => !used.has(l));
  if (fresh.length === 0) {
    used.clear();
    fresh = ordered;
  }
  const line = fresh[0] ?? "Thinking…";
  used.add(line);
  return line;
}
