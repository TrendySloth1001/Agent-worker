// Memory intent classifier: what a user message means for long-term memory,
// decided locally with rules (no LLM, no network, well under a millisecond).
//
// Pipeline: strip text that is not the user speaking (code, quotes, URLs) ->
// detect message-level commands (remember / forget / forget-all) -> split into
// clauses -> expand contractions -> per clause: drop questions, hypotheticals,
// temporary states, hedged/future statements and statements about other
// people -> match slot patterns (name, nickname, location, hometown, work,
// role, pronouns, birthday, languages, tools, likes/dislikes) with negation ->
// standing instructions -> whatever first-person content is left is
// "residual" and goes to the LLM extractor (batched). English and romanised
// Hindi (Hinglish) are handled by rules; other languages fall back to the LLM
// when they contain first-person or "remember" markers.
import { extractEntities } from "./entities.js";
import { detectLanguage } from "./language.js";
import { stemTokens } from "./text.js";
import type { Kind } from "../memory/logic.js";

export const MEMORY_INTENTS = ["remember", "forget", "correct", "self_disclosure", "instruction", "recall_query", "none"] as const;
export type MemoryIntent = (typeof MEMORY_INTENTS)[number];

/** A structured fact for one memory slot. */
export type Fact =
  | { type: "name"; slot: "name"; full?: string; nick?: string }
  | { type: "langs"; slot: "languages"; langs: string[] }
  | { type: "simple"; slot: string; kind: Kind; text: string };

/** Delete the slot's memory; with [value], only when the memory mentions it; [nickOnly] drops just the nickname. */
export type Removal = { slot: string; value?: string; nickOnly?: boolean };

export type MemoryAnalysis = {
  /** Primary intent (forget > correct > remember > instruction > self_disclosure > recall_query > none). */
  intent: MemoryIntent;
  intents: MemoryIntent[];
  facts: Fact[];
  removals: Removal[];
  /** "forget everything about me": clear the unpinned memories. */
  forgetAll: boolean;
  /** Standing instructions written as memory text ("Keep answers short."). */
  instructions: string[];
  /** Whether the LLM extractor must still look at the message: now (explicit), batched, or not at all. */
  llm: "none" | "now" | "batch";
  /** The remember/forget subject, for the extractor prompt. */
  subject?: string;
  /** Short debug notes ("skip:question", "fact:location"). */
  reasons: string[];
};

// ---- lexicons ---------------------------------------------------------------------------

const NAME_STOP = new Set(
  "a an the not also actually just really so very from in at on and but or is am are was to of for with by back later tomorrow today tonight when whenever anytime anything sometime soon now please maybe crazy old fashioned whatever anything something someone somebody anyone you him her them me us it this that what if here there sir maam madam bro buddy dude boss yaar bhai kya hai nahi mat ok okay out up".split(" "),
);

/** Capitalised words after "I am" that are not names. */
const NOT_NAME = new Set(
  "indian american british english german french chinese japanese korean italian spanish russian canadian australian pakistani bangladeshi nepali sri lankan hindu muslim christian sikh jain buddhist jewish catholic atheist agnostic vegan vegetarian gay straight bi trans single married divorced engaged bengali punjabi marathi gujarati tamil telugu kannada malayali sorry fine good back here ready done new human".split(" "),
);

const ROLE_NOUNS =
  "developer|engineer|programmer|coder|designer|student|teacher|tutor|professor|lecturer|doctor|nurse|lawyer|accountant|manager|founder|co-founder|cofounder|ceo|cto|cfo|coo|consultant|freelancer|architect|analyst|scientist|researcher|writer|author|journalist|artist|musician|photographer|entrepreneur|intern|marketer|devops|sre|administrator|admin|editor|tester|chef|pharmacist|dentist|pilot|farmer|banker|trader|investor|youtuber|streamer|blogger|creator|contractor|owner|lead|director|recruiter|salesperson|technician|mechanic|electrician|pm|vp|hacker|maintainer|undergrad|undergraduate|graduate|postgrad|phd";
const ROLE_RE = new RegExp(String.raw`^((?:[\p{L}+#.-]+\s+){0,3}?(?:${ROLE_NOUNS})s?)$`, "iu");

const LANGUAGES = new Map(
  "english hindi marathi gujarati bengali bangla tamil telugu kannada malayalam punjabi urdu odia oriya assamese konkani sanskrit nepali sindhi bhojpuri spanish french german italian portuguese dutch russian chinese mandarin cantonese japanese korean arabic persian farsi turkish greek hebrew polish swedish norwegian danish finnish czech ukrainian romanian hungarian thai vietnamese indonesian malay tagalog filipino swahili hinglish"
    .split(" ")
    .map((l) => [l, l.charAt(0).toUpperCase() + l.slice(1)] as const),
);

const TEMPORARY =
  /\b(?:today|tonight|tomorrow|yesterday|this (?:morning|afternoon|evening|week|weekend|month)|right now|at the moment|for now|for (?:a|the) (?:few|couple of) (?:days|weeks|hours)|for a while|on (?:vacation|holiday|leave|a trip)|next (?:week|month|year)|aaj|abhi|kal)\b/i;
const STATE =
  /^i am (?:so |very |really |a bit |a little |kinda |kind of |pretty |feeling |just |still |also )*(?:tired|hungry|thirsty|sleepy|sick|ill|unwell|bored|busy|sad|happy|angry|upset|stressed|excited|confused|lost|stuck|late|back|here|there|done|ready|free|good|great|fine|ok|okay|sorry|sure|not sure|unsure|kidding|joking|curious|wondering|trying|going|leaving|coming|on my way|outside|home|at home|at work|in a meeting|driving|travelling|traveling|exhausted|frustrated|annoyed|worried|nervous|glad|grateful|afraid|scared)\b/i;
const HYPOTHETICAL = /\b(?:if i (?:were|was|had|am|lived|worked|moved|could|ever)|suppose|supposing|imagine|let us say|lets say|pretend|what if|hypothetically|in a story|in this story|as if|role ?play|agar main|agar mai|maan lo|maano)\b/i;
/** Hedged, wished-for or future statements are not facts yet. */
const HEDGE = /^(?:maybe |probably |perhaps )?i (?:would|could|might|may|will|shall|wish|hope|plan|want to|wanna|am planning|am thinking|was thinking|am going to|am gonna|think i|guess i|might)\b/i;
const OTHER_PERSON =
  /^(?:my|our|his|her|their)\s+(?:best\s+)?(?:friend|friends|brother|sister|bro|sis|mother|mom|mum|mummy|maa|father|dad|papa|wife|husband|partner|girlfriend|boyfriend|gf|bf|son|daughter|kid|kids|child|children|boss|manager|colleague|coworker|co-worker|cousin|uncle|aunt|grandma|grandpa|grandmother|grandfather|neighbour|neighbor|roommate|flatmate|teacher|client|customer|dog|cat|pet)(?:'s|s'|s)?\b/i;
const QUESTION_START =
  /^(?:what|who|whom|whose|where|when|why|how|which|do|does|did|is|are|am|was|were|can|could|would|should|will|shall|have|has|kya|kaun|kahan|kab|kyun|kyu|kaise|kitna|kitne)\b/i;
/** Messages that are tasks over pasted or invented text: the content is data, not the user. */
const TASK_GATE =
  /^\s*(?:please\s+|pls\s+|can you\s+|could you\s+)?(?:translate|rewrite|re-write|paraphrase|proofread|summari[sz]e|fix (?:the )?(?:grammar|spelling)|correct (?:the )?(?:grammar|spelling|this)|check (?:the )?grammar|write (?:a|an|me|some|the)|draft|compose|generate|make (?:a|an|me)(?! note)|create (?:a|an)|roleplay|role-play|pretend|act as|imagine|continue (?:this|the) story)\b/i;

const HINGLISH = /\b(?:hai|hain|hoon|hun|hu|mera|meri|mere|mujhe|nahi|nahin|karo|karna|dena|kya|aur|bhi|mein|se|ko|ka|ki|ke|rakhna|bulao|kehte|bulate|pasand|rehta|rehti)\b/i;

// ---- helpers ----------------------------------------------------------------------------

const CONTRACTIONS: Array<[RegExp, string]> = [
  [/\bi'm\b/gi, "i am"],
  [/\bim\b(?=\s+(?:a|an|the|from|in|at|based|living|not|no|currently|now|still|building|working|using|into|vegetarian|vegan))/gi, "i am"],
  [/\bi've\b/gi, "i have"],
  [/\bi'd\b/gi, "i would"],
  [/\bi'll\b/gi, "i will"],
  [/\bcan't\b/gi, "cannot"],
  [/\bwon't\b/gi, "will not"],
  [/\b(do|does|did|is|are|was|were|have|has|had|would|should|could)n't\b/gi, "$1 not"],
  [/\bdont\b/gi, "do not"],
  [/\bdoesnt\b/gi, "does not"],
  [/\b(what|who|where|that|it|there|name)'s\b/gi, "$1 is"],
  [/\blet's\b/gi, "let us"],
  [/\bur\b/gi, "your"],
  [/\bu\b/gi, "you"],
];

export function expandContractions(s: string): string {
  let t = s.replace(/[’‘`´]/g, "'");
  for (const [re, rep] of CONTRACTIONS) t = t.replace(re, rep);
  return t;
}

/** Removes text that is not the user speaking: code, quotes, block quotes and links. */
export function stripNonUser(s: string): string {
  return s
    .replace(/```[\s\S]*?(?:```|$)/g, " ")
    .replace(/`[^`\n]*`/g, " ")
    .replace(/^\s*>.*$/gm, " ")
    .replace(/"[^"\n]{0,400}"/g, " ")
    .replace(/“[^”\n]{0,400}”/g, " ")
    .replace(/https?:\/\/\S+/g, " ")
    .replace(/[ \t]+/g, " ");
}

type Clause = { text: string; question: boolean };

/** Sentences, then clauses joined by "and/but" before a new first-person subject. */
export function splitClauses(s: string): Clause[] {
  const out: Clause[] = [];
  const sentences = s.match(/[^.!?\n;]+(?:[.!?]+(?=\s|$)|[\n;]|$)|[^\n;]+$/g) ?? [];
  for (const raw of sentences) {
    const question = /\?\s*$/.test(raw);
    const body = raw.replace(/[.!?;\n]+\s*$/, "").trim();
    if (!body) continue;
    // "I live in Pune and work at Acme": the second verb shares the subject, so give it one back.
    const withSubject = /^(?:i|i am)\b/i.test(body)
      ? body.replace(/\s*,?\s+and\s+(?=(?:also\s+|now\s+|currently\s+)?(?:work|live|stay|use|study|speak|love|like|prefer|hate|code|program|moved|joined)\b)/gi, " and I ")
      : body;
    const parts = withSubject.split(
      /\s*,?\s+(?:and|but|also|plus|aur|lekin|par|so)\s+(?=(?:i|i'm|i am|my|everyone|everybody|people|friends|they|main|mai|mera|meri|mujhe|sab|call me|you can call me)\b)|\s*,\s*(?=(?:i|i'm|my|main|mera|mujhe|everyone|people|call me)\b)|\s*,\s*(?=(?:what|how|and you|wbu|hbu|aap|tum)\b)/i,
    );
    parts.forEach((p, i) => {
      const t = p.trim();
      if (t) out.push({ text: t, question: question && i === parts.length - 1 });
    });
  }
  return out;
}

const titleCase = (s: string) =>
  s
    .split(/\s+/)
    .map((w) => (/^[a-z]/.test(w) ? w.charAt(0).toUpperCase() + w.slice(1) : w))
    .join(" ");

/** 1-3 letter-only words that are not common function words. */
function cleanName(raw: string | undefined): string | null {
  if (!raw) return null;
  const words = raw.trim().replace(/[,.!?]+$/, "").split(/\s+/);
  const kept: string[] = [];
  for (const w of words) {
    if (!/^\p{L}[\p{L}'-]*$/u.test(w) || NAME_STOP.has(w.toLowerCase())) break;
    kept.push(w);
    if (kept.length === 3) break;
  }
  if (!kept.length || kept.join("").length < 2) return null;
  return titleCase(kept.join(" "));
}

const FILLER_TAIL =
  /\s+(?:now|currently|these days|nowadays|for (?:work|years|a living|many years|\d+ years|the last \d+ years|a long time)|since .+|with .+|right now|at the moment|daily|every ?day|a lot|so much|very much|too|mostly|mainly|as well|at work|for my job|full[- ]time|part[- ]time|bro|yaar|btw|lol|haha|by the way|though|anymore|any more|hai|hoon|hu)$/i;

function trimTail(s: string): string {
  let t = s.trim().replace(/[,.!?]+$/, "");
  for (let i = 0; i < 4; i++) {
    const n = t.replace(FILLER_TAIL, "").trim();
    if (n === t) break;
    t = n;
  }
  return t;
}

/** A place: up to 5 words, letters and commas, no articles or pronouns up front. */
function cleanPlace(raw: string): string | null {
  const t = trimTail(raw).replace(/\s+(?:city|area)$/i, (m) => m);
  if (!t || t.length > 60) return null;
  if (/^(?:a|an|the|my|our|this|that|there|here|it|some|one|india's)\b/i.test(t)) return null;
  if (!/^[\p{L}][\p{L} ,.'-]*$/u.test(t)) return null;
  if (t.split(/\s+/).length > 5) return null;
  return titleCase(t.replace(/\s*,\s*/g, ", "));
}

/** An organisation: up to 5 words starting with a letter or digit; lower-case common nouns are rejected. */
function cleanOrg(raw: string): string | null {
  const t = trimTail(raw).replace(/\s+as\s+.*$/i, "");
  if (!t || t.length > 60 || t.split(/\s+/).length > 5) return null;
  if (/^(?:a|an|the|my|our|this|that|home|it|tech|it industry|finance|marketing|sales|software|hardware|healthcare|education|retail)\b/i.test(t) && !/^[A-Z]/.test(t.replace(/^(?:a|an|the)\s+/i, ""))) return null;
  if (!/^[\p{L}\p{N}][\p{L}\p{N} &.,'-]*$/u.test(t)) return null;
  // Lower-case single generic words ("startup", "bank") are not names.
  const ents = extractEntities(t).filter((e) => e.type === "org" || e.type === "tech" || e.type === "person" || e.type === "name");
  if (!ents.length && /^[a-z]/.test(t) && /^(?:startup|company|bank|hospital|school|college|university|firm|agency|office|factory|shop|store|mnc|corporate)s?$/i.test(t)) return null;
  return t.split(/\s+/).map((w) => (/^[a-z]/.test(w) && w.length > 2 ? w.charAt(0).toUpperCase() + w.slice(1) : w)).join(" ");
}

/** Canonical tech names for a list like "Neovim and tmux" when every item is a known technology. */
export function techList(raw: string): string[] | null {
  // "Neovim with a custom Lua config" says more than a tool name: leave it to the model.
  if (/\s(?:with|using|via|on top of)\s/i.test(raw)) return null;
  const items = trimTail(raw)
    .split(/\s*,\s*|\s+(?:and|&|plus|aur)\s+|\s*\/\s*/i)
    .map((x) => x.trim())
    .filter(Boolean);
  if (!items.length || items.length > 5) return null;
  const out: string[] = [];
  for (const it of items) {
    const t = extractEntities(it).find((e) => e.type === "tech" && e.text.length >= it.replace(/[.,]$/, "").length - 1);
    if (!t) return null;
    out.push(t.value);
  }
  return out;
}

export const slotKey = (s: string) =>
  stemTokens(s)
    .filter((w) => !/^(a|an|the|to|of|and|my)$/.test(w))
    .join("-")
    .slice(0, 48);

const LANG_ADJ = /\b(?:fluent|fluently|a little|a bit of|a bit|little|some|basic|decent|good|native|conversational|broken|bad|ok|okay|also)\b\s*/gi;

function languageList(raw: string): string[] | null {
  const items = trimTail(raw.replace(LANG_ADJ, ""))
    .split(/\s*,\s*|\s+(?:and|&|aur)\s+/i)
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);
  if (!items.length) return null;
  const out: string[] = [];
  for (const it of items) {
    const l = LANGUAGES.get(it);
    if (!l) return null;
    out.push(l);
  }
  return out;
}

const OBJ_STOP = /^(?:it|this|that|these|those|you|your|yours|him|her|them|me|myself|us|when|how|what|where|why|if|because|the way|being|to be|having|getting|doing|making|her|his|their|our|my|the|everything|nothing|anything|something|everyone|nobody|all|both|one|some|any|lot|lots)\b/i;

function cleanObject(raw: string): string | null {
  const t = trimTail(raw);
  if (!t || OBJ_STOP.test(t)) return null;
  if (/\b(?:when|if|because|but|unless|that you|you)\b/i.test(t)) return null;
  const words = t.split(/\s+/);
  if (words.length > 4 || t.length > 50) return null;
  if (!/^[\p{L}\p{N}][\p{L}\p{N} '+#.&-]*$/u.test(t)) return null;
  return t;
}

const LIKE_VERB: Record<string, string> = {
  love: "Loves",
  adore: "Loves",
  like: "Likes",
  enjoy: "Enjoys",
  prefer: "Prefers",
  hate: "Hates",
  detest: "Hates",
  "cannot stand": "Hates",
  "can not stand": "Hates",
  dislike: "Dislikes",
  "do not like": "Dislikes",
  "do not enjoy": "Dislikes",
  "am not a fan of": "Dislikes",
  "am a fan of": "Likes",
  "am a big fan of": "Likes",
  "am a huge fan of": "Likes",
};

/** "a"/"an" by sound: "an engineer", "an ML engineer", "a UX designer". */
const article = (w: string) => (/^[A-Z]{2,}\b/.test(w) ? (/^[AEFHILMNORSX]/.test(w) ? "an" : "a") : /^[aeiou]/i.test(w) ? "an" : "a");

// ---- message-level commands ------------------------------------------------------------

const LEAD = String.raw`^\s*(?:hey,?\s+|ok(?:ay)?,?\s+|so,?\s+|and\s+|also,?\s+|btw,?\s+)?(?:sparky,?\s+)?(?:please\s+|pls\s+)?(?:(?:can|could|would|will) you\s+(?:please\s+)?)?`;
const REMEMBER_EN = new RegExp(
  String.raw`${LEAD}(?:always\s+)?(?:remember|do not forget|never forget|keep in mind|make a note(?: of)?|note down|note(?= that\b| this\b|:)|save (?:this |that |it )?(?:to|in) (?:your )?memory|add (?:this |that |it )?to (?:your )?memory)\b[\s:,-]*(?:that\s+|this:?\s+)?(.*)$`,
  "is",
);
const REMEMBER_HI = /\b(?:yaad\s+rakh(?:na|no|o|iye|ein|en|e|ega|egi|i)?|yaad\s+kar\s+(?:lo|lena|le)|dhyan\s+rakh(?:na|o|iye)?|note\s+kar\s*(?:lo|lena|le|o)?|save\s+kar\s*(?:lo|lena|le|o)?)\b/i;
const REMEMBER_TAIL = /[,\s]*(?:please\s+)?(?:remember (?:that|this|it)|keep (?:that|this|it) in mind|do not forget (?:that|this|it)|note (?:that|this|it)(?: down)?)\s*(?:please)?\s*[.!]*\s*$/i;
const FORGET_EN = new RegExp(
  String.raw`${LEAD}(?:forget|stop remembering|unlearn|remove from (?:your )?memory|delete from (?:your )?memory|erase from (?:your )?memory|(?:remove|delete|erase|clear|drop)(?= (?:my (?:name|nick ?name|location|city|address|home ?town|job|employer|company|role|pronouns|birthday|languages?|preferences?)|what you know about|the (?:memory|note) about|your (?:memory|note) (?:of|about))\b|.*\bfrom (?:your )?memory\b))\b[\s:,-]*(?:that\s+|about\s+)?(.*)$`,
  "is",
);
const FORGET_HI = /\b(?:bh[ou]{1,2}l\s+ja(?:o|na|ana|aiye|iye|ye)?|bhula\s+do|bhul\s+jao|mita\s+do|hata\s+do|delete\s+kar\s*do)\b/i;
const FORGET_ALL =
  /\b(?:forget|erase|delete|wipe|clear|remove)\s+(?:absolutely\s+)?(?:everything|all(?: of it)?|all the things)\s+(?:that\s+)?(?:you\s+(?:know|remember|have saved|saved)\s+)?about me\b|\b(?:delete|erase|wipe|clear|remove)\s+(?:all\s+)?(?:of\s+)?(?:my|your)\s+(?:memories|saved memories|memory about me)\b|\bsab\s*kuch\s+bh[ou]{1,2}l\s+ja(?:o|na)\b/i;
/** Forget subjects that are idioms ("forget it"), not a memory to delete. */
const TRIVIAL_SUBJECT = /^(?:it|about it|that|this|all that|all of that|it then|what i (?:just )?said|the above|the previous (?:one|message)|previous|the last one|me|everything|all|the rest|the instructions?|previous instructions?|your instructions|instructions)\s*[.!?]*$/i;

/** "Can you …?" is a request, not a question. */
const POLITE = /^\s*(?:\w+,?\s+)?(?:please\s+)?(?:can|could|would|will) you\b/i;

const RECALL =
  /\b(?:what (?:do|did) you (?:know|remember) about me|what (?:else )?do you know about me|what have you (?:saved|stored|remembered) about me|tell me what you (?:know|remember) about me|who am i\b|what is my (?:name|nickname|full name|job|role|location|city|hometown|birthday|pronouns|employer|company|stack|tech stack|editor|favou?rite \w+|preferences?)|where do i (?:live|work|stay)|where am i from|what do i do(?: for (?:a )?living| for work)?|what (?:languages?|tools?) do i (?:speak|use)|do you (?:know|remember) (?:my|who i am|me\b|what i|where i|anything about me)|what did i (?:tell|say to) you about (?:me|myself)|what are my (?:preferences|projects|instructions)|mera naam kya (?:hai|h)|mere (?:baare|bare) (?:mein|me|mai) (?:kya|tum|tumhe|aap)|tumhe (?:kya )?yaad (?:hai|h)|kya tumhe .{0,30}yaad|main kahan rehta|main kaun (?:hoon|hu))\b/i;

const CORRECT_LEAD = /^(?:actually|no|nope|nah|correction|wait|sorry|oops|not quite|to correct|i meant|asal mein|asal me|nahi|nahin|galat)\b[,:!]?\s*/i;
const CORRECT_ANY = /\b(?:anymore|any more|no longer|not any ?more|moved to|relocated to|shifted to|switched (?:from .+ )?to|changed my name|ab nahi|ab nahin)\b/i;

const INSTRUCTION_LEAD =
  /^(?:from now on|going forward|henceforth|in (?:the )?future|from today|every time|whenever|aage se|ab se|hamesha|always|never|i want you to (?:always|never)|i would like you to (?:always|never)|you should (?:always|never)|please (?:always|never)|make sure (?:you )?(?:always|never))\b[,:]?\s*/i;
const INSTRUCTION_KEEP = /^(?:please\s+)?keep (?:your |the )?(?:answers|replies|responses|explanations|messages|code samples)\s+\w+/i;
const INSTRUCTION_UNLESS = /^(?:please\s+)?(?:do not|never)\b.+\bunless\b/i;
const NOT_INSTRUCTION = /^(?:never ?mind|nevermind|always the same|never again\b|never heard|never seen|never done|never used|never tried|never been)\b/i;

// ---- per-clause slot extraction --------------------------------------------------------

type ClauseOut = { facts: Fact[]; removals: Removal[]; consumed: boolean; correct?: boolean; reason?: string };

const FIRST_PERSON = /\b(?:i|me|my|mine|myself|main|mai|mera|meri|mere|mujhe|hum|hamara|we|our)\b/i;
const PERSONAL_RESIDUAL =
  /\b(?:i am|i have|i work|i use|i live|i prefer|i like|i love|i hate|i study|i build|i code|i write|i speak|i run|i own|i teach|i manage|i lead|i founded|i started|i play|i follow|i eat|i do not eat|i drive|i need you to|my (?:name|job|role|team|company|project|stack|setup|goal|favou?rite|school|university|college|city|country|timezone|birthday|budget|business|startup|app|site|website|phone|laptop|editor|workflow|os|religion|diet|age)|we use|we are|our (?:team|stack|company|product|app|startup|codebase|repo|project)|mera|meri|mujhe|main .{1,40} (?:hoon|hu|hun|karta|karti))\b/i;

function simple(slot: string, kind: Kind, text: string): Fact {
  return { type: "simple", slot, kind, text };
}

/** Facts, removals or nothing for one clause (already contraction-expanded). */
function parseClause(c: string): ClauseOut {
  const out: ClauseOut = { facts: [], removals: [], consumed: false };
  let m: RegExpExecArray | null;
  let t = c.replace(/^(?:hi|hello|hey|yo|ok|okay|so|well|btw|also|and|but|oh|hmm|haan|ha|accha|acha)\b[,!]?\s*/i, "").trim();
  const corrected = CORRECT_LEAD.test(t);
  if (corrected) {
    t = t.replace(CORRECT_LEAD, "").trim();
    out.correct = true;
  }
  if (CORRECT_ANY.test(t)) out.correct = true;
  const done = (reason: string) => ((out.consumed = true), (out.reason = reason), out);

  // ---- name / nickname
  if ((m = /\bmy (?:full |real |first |actual )?name is not ([\p{L}'-]+)/iu.exec(t))) {
    out.removals.push({ slot: "name", value: m[1] });
    const rest = /\bit is ([\p{L}'-]+(?: [\p{L}'-]+)?)/iu.exec(t);
    const n = cleanName(rest?.[1]);
    if (n) out.facts.push({ type: "name", slot: "name", full: n });
    out.correct = true;
    return done("name:not");
  }
  if ((m = /\bmy (?:full |real |first |actual )?name is ([\p{L}][\p{L}' -]{0,60})/iu.exec(t)) || (m = /\bmera (?:poora |pura |asli )?naam ([\p{L}][\p{L}' -]{0,60}?) (?:hai|h)\b/iu.exec(t))) {
    const n = cleanName(m[1]);
    if (n) {
      out.facts.push({ type: "name", slot: "name", full: n });
      const nick = /\b(?:calls? me|go by|goes by|known as)\s+([\p{L}'-]+)/iu.exec(t.slice(m.index + 11));
      const nn = cleanName(nick?.[1]);
      if (nn) (out.facts[0] as { nick?: string }).nick = nn;
      return done("name");
    }
  }
  if ((m = /^(?:please\s+)?(?:do not|never|stop) call(?:ing)? me ([\p{L}'-]+)/iu.exec(t))) {
    const n = cleanName(m[1]);
    if (n) {
      out.removals.push({ slot: "name", value: n, nickOnly: true });
      out.correct = true;
      return done("nick:not");
    }
  }
  if (
    (m = /^(?:please\s+|just\s+|you can\s+|you may\s+|you could\s+|feel free to\s+)*call me ([\p{L}'-]+(?: [\p{L}'-]+)?)/iu.exec(t)) ||
    (m = /\b(?:everyone|everybody|people|friends|my friends|they|most people|folks|my family|my colleagues|colleagues|all my friends|my team|everyone at work)\s+(?:usually |often |just |all |mostly |also )*(?:call|calls) me ([\p{L}'-]+)/iu.exec(t)) ||
    (m = /\bi (?:usually |mostly |also |just )?go by ([\p{L}'-]+)/iu.exec(t)) ||
    (m = /\bmy nick ?name is ([\p{L}'-]+)/iu.exec(t)) ||
    (m = /\bmujhe ([\p{L}'-]+) (?:bulao|bulaiye|bulana|bula|kaho|kehna|bolo|bol|keh)\b/iu.exec(t)) ||
    (m = /\bsab (?:log )?mujhe ([\p{L}'-]+) (?:bulate|kehte|bolte)\b/iu.exec(t))
  ) {
    const n = cleanName(m[1]);
    if (n) {
      out.facts.push({ type: "name", slot: "name", nick: n });
      return done("nick");
    }
  }
  if ((m = /^i am ([A-Z][\p{Ll}'-]+(?: [A-Z][\p{Ll}'-]+)?)$/u.exec(t.replace(/^(?:this is)\s+/i, "i am ")))) {
    const n = cleanName(m[1]);
    if (n && !NOT_NAME.has(n.split(" ")[0].toLowerCase()) && !STATE.test(`i am ${n.toLowerCase()}`) && !LANGUAGES.has(n.toLowerCase()) && !extractEntities(n).some((e) => e.type === "tech")) {
      out.facts.push({ type: "name", slot: "name", full: n });
      return done("name:i-am");
    }
  }

  // ---- location / hometown
  if ((m = /\bi (?:do not|no longer|do not really) (?:live|stay|reside) in ([^,;]+)/i.exec(t)) || (m = /\bi am (?:not|no longer) (?:living |staying |based )?in ([^,;]+?) any ?more\b/i.exec(t)) || (m = /\bi am no longer (?:living |staying |based )?in ([^,;]+)/i.exec(t))) {
    const p = cleanPlace(m[1]);
    if (p) {
      out.removals.push({ slot: "location", value: p });
      return done("location:not");
    }
  }
  if (
    (m = /\bi (?:currently |now |still |actually |mostly )*(?:live|stay|reside) in ([^;]+)/i.exec(t)) ||
    (m = /\bi am (?:currently |now |still )*(?:based|living|staying|settled|located) (?:in|out of) ([^;]+)/i.exec(t)) ||
    (m = /\bi (?:have )?(?:just |recently |finally )?(?:moved|relocated|shifted) (?:back )?to ([^;]+)/i.exec(t)) ||
    (m = /\bmy (?:current )?(?:city|location) is ([^;]+)/i.exec(t)) ||
    (m = /\b(?:main|mai) ([\p{L} ]{2,30}?) (?:mein|me|mai) (?:rehta|rehti|rehte|reh raha|reh rahi) (?:hoon|hu|hun|h)\b/iu.exec(t))
  ) {
    const p = cleanPlace(m[1]);
    if (p) {
      if (/moved|relocated|shifted/i.test(m[0])) out.correct = true;
      out.facts.push(simple("location", "identity", `Lives in ${p}.`));
      return done("location");
    }
  }
  if ((m = /\bi am (?:originally )?from ([^;]+)/i.exec(t)) || (m = /\bi (?:originally )?come from ([^;]+)/i.exec(t)) || (m = /\bmy home ?town is ([^;]+)/i.exec(t)) || (m = /\b(?:main|mai) ([\p{L} ]{2,30}?) se (?:hoon|hu|hun)\b/iu.exec(t))) {
    const p = cleanPlace(m[1]);
    if (p) {
      out.facts.push(simple("hometown", "identity", `From ${p}.`));
      return done("hometown");
    }
  }
  if ((m = /\bi was born in ([^;]+)/i.exec(t))) {
    const p = cleanPlace(m[1]);
    if (p) {
      out.facts.push(simple("hometown", "identity", `Born in ${p}.`));
      return done("hometown:born");
    }
  }

  // ---- pronouns / birthday / languages
  if ((m = /\bmy pronouns are ([a-z]+(?:\s*\/\s*[a-z]+){1,2})/i.exec(t)) || (m = /\bi use ([a-z]+(?:\s*\/\s*[a-z]+){1,2}) pronouns\b/i.exec(t))) {
    out.facts.push(simple("pronouns", "identity", `Pronouns: ${m[1].replace(/\s+/g, "").toLowerCase()}.`));
    return done("pronouns");
  }
  if ((m = /\bmy (?:birthday|bday|b-day|birth ?day|date of birth|dob) is (?:on )?([^;]+)/i.exec(t)) || (m = /\bi was born on ([^;]+)/i.exec(t))) {
    const v = trimTail(m[1]);
    if (/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b|\b\d{1,2}[/.-]\d{1,2}\b/i.test(v) && v.length <= 30) {
      out.facts.push(simple("birthday", "identity", `Birthday: ${v.replace(/\b[a-z]/g, (ch, i) => (/[a-z]/.test(v[i - 1] ?? " ") ? ch : ch.toUpperCase()))}.`));
      return done("birthday");
    }
  }
  if ((m = /\bi (?:can |also )?speak ([^;]+)/i.exec(t)) || (m = /\bmy (?:native|first|mother) (?:language|tongue) is ([^;]+)/i.exec(t))) {
    if (/\bi (?:do not|cannot) speak\b/i.test(t)) return out;
    const langs = languageList(m[1]);
    if (langs) {
      out.facts.push({ type: "langs", slot: "languages", langs });
      return done("languages");
    }
  }

  // ---- work / role
  if ((m = /\bi (?:no longer work|do not work|stopped working) (?:at|for) ([^;]+)/i.exec(t)) || (m = /\bi (?:have )?(?:left|quit) ([A-Z][^;]*)/i.exec(t))) {
    const o = /^[A-Z]/.test(m[1]) || /no longer|do not|stopped/i.test(m[0]) ? cleanOrg(m[1]) : null;
    if (o) {
      out.removals.push({ slot: "work", value: o });
      out.correct = true;
      return done("work:not");
    }
  }
  if ((m = /\bi (?:currently |now |still |also )?work (?:as (?:a |an )?(.+?) )?(?:at|for) ([^;]+?)(?: as (?:a |an )?([^;]+))?$/i.exec(t))) {
    const role = cleanRole(m[1] ?? m[3]);
    if (/^(?:myself|my ?self)\b/i.test(m[2])) {
      out.facts.push(simple("work", "identity", "Self-employed."));
      if (role) out.facts.push(roleFact(role));
      return done("work:self");
    }
    const org = cleanOrg(m[2]);
    if (org) {
      out.facts.push(simple("work", "identity", `Works at ${org}.`));
      if (role) out.facts.push(roleFact(role));
      return done("work");
    }
  }
  if ((m = /\bi (?:have )?(?:just |recently )?joined ([A-Z][^;]*)/i.exec(t)) && /^[A-Z]/.test(m[1])) {
    const org = cleanOrg(m[1]);
    if (org) {
      out.facts.push(simple("work", "identity", `Works at ${org}.`));
      out.correct = true;
      return done("work:joined");
    }
  }
  if ((m = /\bi (?:currently |now )?work as (?:a |an )?([^;]+)/i.exec(t)) || (m = /\bmy (?:job|role|position|title|profession) is (?:a |an )?([^;]+)/i.exec(t))) {
    const role = cleanRole(m[1]);
    if (role) {
      out.facts.push(roleFact(role));
      return done("role");
    }
  }
  if ((m = /\bi am (?:currently |now |also |actually )?(?:a |an )([^;]+?)(?: (?:at|in|with|for) ([^;]+))?$/i.exec(t)) || (m = /\b(?:main|mai) (?:ek )?([\p{L} -]{2,40}?) (?:hoon|hu|hun)\b/iu.exec(t))) {
    const role = cleanRole(m[1]);
    if (role) {
      out.facts.push(roleFact(role));
      const org = m[2] ? cleanOrg(m[2]) : null;
      if (org) out.facts.push(simple("work", "identity", /student|undergrad|graduate|phd|postgrad/i.test(role) ? `Studies at ${org}.` : `Works at ${org}.`));
      return done("role");
    }
  }
  if ((m = /\bi (?:currently )?study at ([A-Z][^;]+)/i.exec(t)) && /^[A-Z]/.test(m[1])) {
    const org = cleanOrg(m[1]);
    if (org) {
      out.facts.push(simple("work", "identity", `Studies at ${org}.`));
      return done("study");
    }
  }

  // ---- tools / stack
  if ((m = /\bi (?:do not|no longer|stopped|do not really) (?:use|using|code in|work with) ([^;]+)/i.exec(t)) || (m = /\bi am not using ([^;]+?) any ?more/i.exec(t))) {
    const techs = techList(m[1].replace(/\s+any ?more$/i, ""));
    if (techs) {
      for (const x of techs) out.removals.push({ slot: `tool:${slotKey(x)}` });
      return done("tool:not");
    }
  }
  if ((m = /\bi (?:have )?(?:switched|moved|migrated|changed) (?:over )?from ([^;]+?) to ([^;]+)/i.exec(t))) {
    const from = techList(m[1]);
    const to = techList(m[2]);
    if (from && to) {
      for (const x of from) out.removals.push({ slot: `tool:${slotKey(x)}` });
      for (const x of to) out.facts.push(simple(`tool:${slotKey(x)}`, "fact", `Uses ${x}.`));
      out.correct = true;
      return done("tool:switch");
    }
  }
  if (
    (m = /\bi (?:mostly |mainly |primarily |usually |always |now |currently |still |only |also |daily |actively )*(?:use|code in|program in|develop in|build with|work with|write|am using|have been using|switched to|moved to)\s+([^;]+)/i.exec(t)) ||
    (m = /\bmy (?:editor|ide|os|operating system|browser|shell|terminal|stack|tech stack|main language|language of choice|go-to language|laptop|phone) (?:is|=) ([^;]+)/i.exec(t)) ||
    (m = /\b(?:main|mai) ([\p{L}\p{N} .+#,&-]{2,60}?) use (?:karta|karti|karte) (?:hoon|hu|hun|h)\b/iu.exec(t))
  ) {
    const techs = techList(m[1]);
    if (techs) {
      for (const x of techs) out.facts.push(simple(`tool:${slotKey(x)}`, "fact", `Uses ${x}.`));
      if (/switched to|moved to/i.test(m[0])) out.correct = true;
      return done("tool");
    }
  }

  // ---- likes / dislikes
  if ((m = /\bi prefer ([^;]+?) (?:over|to|rather than|instead of) ([^;]+)/i.exec(t))) {
    const a = cleanObject(m[1]);
    const b = cleanObject(m[2]);
    if (a && b) {
      out.facts.push(simple(`taste:${slotKey(a)}`, "preference", `Prefers ${a} over ${b}.`));
      return done("prefer");
    }
  }
  if ((m = /\bi (?:really |absolutely |totally |kind of |kinda |truly |honestly |just |also |do |genuinely |actually )*(love|adore|like|enjoy|prefer|hate|detest|dislike|cannot stand|can not stand|do not like|do not enjoy|am not a fan of|am a fan of|am a big fan of|am a huge fan of)\s+([^;]+)/i.exec(t))) {
    const verb = LIKE_VERB[m[1].toLowerCase()];
    const techs = techList(m[2]);
    if (verb && techs) {
      for (const x of techs) out.facts.push(simple(`taste:${slotKey(x)}`, "preference", `${verb} ${x}.`));
      return done("taste");
    }
    if (OBJ_STOP.test(trimTail(m[2]))) return done("taste:pronoun");
    const o = cleanObject(m[2]);
    if (verb && o) {
      out.facts.push(simple(`taste:${slotKey(o)}`, "preference", `${verb} ${o}.`));
      return done("taste");
    }
  }
  if ((m = /\bmujhe ([\p{L}\p{N} .+#-]{2,40}?) (?:bilkul )?pasand (nahi|nahin|nhi)?\s*(?:hai|h|hain)?\b/iu.exec(t))) {
    const techs = techList(m[1]);
    const items = techs ?? (cleanObject(m[1]) ? [cleanObject(m[1])!] : null);
    if (items) {
      for (const x of items) out.facts.push(simple(`taste:${slotKey(x)}`, "preference", `${m[2] ? "Dislikes" : "Likes"} ${x}.`));
      return done("taste:hi");
    }
  }
  return out;
}

function cleanRole(raw: string | undefined): string | null {
  if (!raw) return null;
  const t = trimTail(raw).replace(/\s+(?:by profession|by trade)$/i, "");
  if (!ROLE_RE.test(t) || t.length > 50) return null;
  if (/\b(?:fan|bit|lot|little|kind|sort|type|big)\b/i.test(t.split(/\s+/)[0] ?? "") && t.split(/\s+/).length === 1) return null;
  return t.toLowerCase().replace(/\b(ceo|cto|cfo|coo|vp|pm|sre|qa|phd|ai|ml|ui|ux|ios|it)\b/g, (x) => x.toUpperCase());
}

function roleFact(role: string): Fact {
  return /^(?:\S+\s+)*(?:student|undergrad|undergraduate|graduate|postgrad|phd)$/i.test(role) ? simple("role", "identity", `Is ${article(role)} ${role}.`) : simple("role", "identity", `Works as ${article(role)} ${role}.`);
}

// ---- forget subjects -> slots --------------------------------------------------------------

/** The slots a forget subject names ("my location", "where I live", "that I use vim"); null when none is clear. */
export function forgetSlots(subject: string): Removal[] | null {
  const s = expandContractions(subject).toLowerCase().replace(/[.!?]+$/, "").trim();
  const out: Removal[] = [];
  if (/\bnick ?name\b|\bwhat (?:people|everyone|they) call me\b/.test(s)) out.push({ slot: "name", nickOnly: true });
  else if (/\b(?:my )?(?:full |real )?name\b|\bwho i am\b|\bnaam\b|\bwhat to call me\b/.test(s)) out.push({ slot: "name" });
  if (/\b(?:location|where i (?:live|stay)|my (?:city|address|home)|i live|rehta|rehti)\b/.test(s)) out.push({ slot: "location" });
  if (/\b(?:hometown|home town|where i am from|where i come from|where i was born)\b/.test(s)) out.push({ slot: "hometown" });
  if (/\b(?:job|employer|company|where i work|workplace|my work|office|college|university|school)\b/.test(s)) out.push({ slot: "work" });
  if (/\b(?:role|job title|what i do|profession|designation)\b/.test(s)) out.push({ slot: "role" });
  if (/\bpronouns?\b/.test(s)) out.push({ slot: "pronouns" });
  if (/\b(?:birthday|bday|date of birth|dob)\b/.test(s)) out.push({ slot: "birthday" });
  if (/\blanguages?\b|\bwhat i speak\b/.test(s)) out.push({ slot: "languages" });
  const techs = extractEntities(subject).filter((e) => e.type === "tech").map((e) => slotKey(e.value));
  for (const k of new Set(techs)) {
    if (/\b(?:use|using|tool|stack|editor)\b/.test(s) || !/\b(?:like|love|hate|prefer|dislike)\b/.test(s)) out.push({ slot: `tool:${k}` });
    out.push({ slot: `taste:${k}` });
  }
  return out.length ? out : null;
}

// ---- main --------------------------------------------------------------------------------

const EMPTY = (): MemoryAnalysis => ({ intent: "none", intents: [], facts: [], removals: [], forgetAll: false, instructions: [], llm: "none", reasons: [] });

const FOREIGN_FIRST_PERSON =
  /(?:\b(?:ich|mein|meine|mich|mir|me llamo|mi nombre|soy|vivo|trabajo|uso|prefiero|je|j'habite|je m'appelle|mon nom|ma|moi|sono|mi chiamo|abito|lavoro|eu|meu nome|moro em)\b)|मेरा|मेरी|मैं|मुझे/i;
const FOREIGN_REMEMBER = /\b(?:merk dir|erinnere dich|vergiss|recuerda|olvida|souviens-toi|n'oublie pas|oublie|ricorda|dimentica|lembre)\b|याद रख|भूल जा/i;

/** Classifies [input] for memory: intents, slot facts/removals and whether the LLM extractor is still needed. */
export function analyzeMemory(input: string): MemoryAnalysis {
  const a = EMPTY();
  const raw = (input ?? "").slice(0, 2000);
  const cleaned = stripNonUser(raw).trim();
  if (!cleaned) return a;
  const intents = new Set<MemoryIntent>();
  const expandedAll = expandContractions(cleaned);

  // Tasks over text ("translate: my name is …", "write a story where I …") are not about the user.
  if (TASK_GATE.test(expandedAll)) {
    a.reasons.push("skip:task");
    return a;
  }

  // Message-level commands.
  if (FORGET_ALL.test(expandedAll)) {
    a.forgetAll = true;
    a.intent = "forget";
    a.intents = ["forget"];
    a.reasons.push("forget:all");
    return a;
  }
  let body = expandedAll;
  let remember = false;
  let forgetSubject: string | null = null;
  const polite = POLITE.test(body);
  const fe = FORGET_EN.exec(body);
  const fh = FORGET_HI.test(body) && !/\?\s*$/.test(body);
  if ((fe && (polite || !/\?\s*$/.test(fe[1] ?? ""))) || fh) {
    forgetSubject = (fe ? fe[1] : body.replace(FORGET_HI, " "))
      .replace(/\s+/g, " ")
      .trim()
      .split(/\s*[,;.!]\s+|\s+(?:and then|then|let us|lets|and move on)\b/i)[0]!
      .replace(/[.!?]+$/, "");
    if (TRIVIAL_SUBJECT.test(forgetSubject) || !forgetSubject) {
      a.reasons.push("skip:forget-idiom");
      return a;
    }
    intents.add("forget");
  }
  if (!forgetSubject) {
    const re = REMEMBER_EN.exec(body);
    if (re && (!/\?\s*$/.test(body) || polite)) {
      remember = true;
      body = re[1].trim().replace(/\?\s*$/, "");
    } else if (REMEMBER_HI.test(body) && !/\?\s*$/.test(body)) {
      remember = true;
      body = body.replace(REMEMBER_HI, " ").replace(/\s+/g, " ").trim();
    } else if (REMEMBER_TAIL.test(body)) {
      remember = true;
      body = body.replace(REMEMBER_TAIL, "").trim();
    }
    if (remember) {
      body = body.replace(/^(?:that|this)\s*[:,-]?\s*/i, "").replace(/[,\s]+(?:please|pls|bro|yaar|ok)\s*[.!]*$/i, "");
      // "remember me" / "remember?" carries nothing to store.
      if (/^(?:me|me please|me\?|)$/i.test(body.replace(/[.!]+$/, ""))) {
        a.reasons.push("skip:remember-nothing");
        return a;
      }
      intents.add("remember");
      a.subject = body.slice(0, 300);
    }
  }

  if (forgetSubject) {
    a.subject = forgetSubject.slice(0, 300);
    const slots = forgetSlots(forgetSubject);
    if (slots) a.removals.push(...slots);
    else a.llm = "now";
    a.intent = "forget";
    a.intents = [...intents];
    a.reasons.push(slots ? "forget:slots" : "forget:llm");
    return a;
  }

  // "No, my name is …" / "Actually, I moved to …": the lead applies to the whole message.
  const correctAll = CORRECT_LEAD.test(body.replace(/^\W+/, "")) && FIRST_PERSON.test(body);
  if (correctAll) body = body.replace(/^\W+/, "").replace(CORRECT_LEAD, "");
  body = body.replace(/^[\s,.:;-]+/, "");

  // Per-clause analysis.
  let residual = false;
  let unresolvedRemember = false;
  for (const cl of splitClauses(body)) {
    const c = cl.text.trim();
    const lc = c.toLowerCase();
    if (RECALL.test(c) && (cl.question || QUESTION_START.test(c) || /^(?:tell me|batao)\b/i.test(c) || /\b(?:kya|hai)\s*$/i.test(c))) {
      intents.add("recall_query");
      a.reasons.push("recall");
      continue;
    }
    if (cl.question || (QUESTION_START.test(c) && !/^(?:do not|never)\b/i.test(c))) {
      a.reasons.push("skip:question");
      continue;
    }
    if (HYPOTHETICAL.test(c)) {
      a.reasons.push("skip:hypothetical");
      continue;
    }
    // Standing instructions to the assistant.
    if (!NOT_INSTRUCTION.test(c) && (INSTRUCTION_LEAD.test(c) || INSTRUCTION_KEEP.test(c) || INSTRUCTION_UNLESS.test(c))) {
      intents.add("instruction");
      const text = instructionText(c);
      if (text) {
        a.instructions.push(text);
        a.reasons.push("instruction");
      } else {
        unresolvedRemember = true;
        a.reasons.push("instruction:llm");
      }
      continue;
    }
    if (OTHER_PERSON.test(c) && !/\b(?:call|calls) me\b/i.test(c)) {
      if (remember) unresolvedRemember = true;
      a.reasons.push("skip:other-person");
      continue;
    }
    if (TEMPORARY.test(c) || STATE.test(c)) {
      a.reasons.push("skip:temporary");
      continue;
    }
    if (HEDGE.test(c)) {
      a.reasons.push("skip:hedge");
      continue;
    }
    // "I am in Goa" without live/based: a trip, not an address.
    if (/^i am (?:currently |now )?in [A-Za-z]/i.test(c) && !/\b(?:live|based|living|settled)\b/i.test(c)) {
      a.reasons.push("skip:visiting");
      continue;
    }
    const r = parseClause(c);
    if (r.consumed) {
      a.facts.push(...r.facts);
      a.removals.push(...r.removals);
      if (r.correct || correctAll || r.removals.length) intents.add("correct");
      if (r.facts.length) intents.add("self_disclosure");
      a.reasons.push(`rule:${r.reason}`);
      continue;
    }
    if (remember) {
      unresolvedRemember = true;
      continue;
    }
    if ((correctAll || CORRECT_LEAD.test(c)) && FIRST_PERSON.test(c)) {
      intents.add("correct");
      unresolvedRemember = true;
      a.reasons.push("correct:llm");
      continue;
    }
    if (PERSONAL_RESIDUAL.test(lc)) {
      residual = true;
      intents.add("self_disclosure");
      a.reasons.push("residual");
    }
  }

  // Other languages: rules above are English/Hinglish; hand first-person or "remember" messages to the extractor.
  if (!intents.size && !remember && cleaned.length >= 8) {
    if (FOREIGN_REMEMBER.test(cleaned)) {
      const lang = detectLanguage(cleaned);
      if (lang.code !== "en" && lang.code !== "hi-Latn") {
        intents.add("remember");
        unresolvedRemember = true;
        a.reasons.push(`foreign:${lang.code}`);
      }
    } else if (FOREIGN_FIRST_PERSON.test(cleaned)) {
      const lang = detectLanguage(cleaned);
      if (lang.code !== "en" && lang.code !== "hi-Latn") {
        intents.add("self_disclosure");
        residual = true;
        a.reasons.push(`foreign:${lang.code}`);
      }
    }
  }

  if (remember && !a.facts.length && !a.instructions.length && !a.removals.length) unresolvedRemember = true;
  a.intents = [...intents];
  a.intent = (["forget", "correct", "remember", "instruction", "self_disclosure", "recall_query"] as const).find((i) => intents.has(i)) ?? "none";
  a.llm = unresolvedRemember ? "now" : residual ? "batch" : "none";
  return a;
}

/** A standing instruction as memory text, or null when it needs the model (pronouns that point elsewhere, too long, Hinglish). */
export function instructionText(clause: string): string | null {
  let t = clause.trim().replace(/[.!]+$/, "");
  if (HINGLISH.test(t) || t.length > 160) return null;
  t = t
    .replace(/^(?:from now on|going forward|henceforth|in (?:the )?future|from today|i want you to|i would like you to|you should|please|make sure (?:you )?)\b[,:]?\s*/i, "")
    .replace(/^(?:from now on|going forward|please)\b[,:]?\s*/i, "")
    .replace(/[,\s]+(?:please|thanks|thank you|ok|okay)$/i, "")
    .trim();
  if (!t || t.split(/\s+/).length < 2) return null;
  if (/\b(?:this|that|it|above|these|those|here)\b/i.test(t) && !/\b(?:that is|that are)\b/i.test(t)) return null;
  t = t.replace(/\bme\b/g, "me").replace(/\bmy\b/gi, "my");
  // The assistant addresses itself in these notes the way the user wrote them ("Never use emojis.").
  return `${t.charAt(0).toUpperCase()}${t.slice(1)}.`;
}
