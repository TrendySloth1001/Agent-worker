// Language detection for chat messages. Local and deterministic: a script
// check (non-Latin alphabets), an English function-word check, a romanised
// Hindi ("Hinglish") marker check, then tinyld's n-gram model for the rest.
// Short or code-heavy text falls back to the user's previous turns.

import { detectAll } from "tinyld/light";
import { capTokens } from "./entities.js";

export type LangResult = {
  /** ISO 639-1 code, "hi-Latn" for Hinglish, "und" when nothing is known. */
  code: string;
  /** English display name ("German", "Hinglish"). */
  name: string;
  /** 0..1. */
  confidence: number;
  source: "text" | "history" | "default";
};

const DEFAULT: LangResult = { code: "en", name: "English", confidence: 0.5, source: "default" };
/** A non-English language must reach this to change the reply language. */
export const REPLY_LANG_MIN_CONFIDENCE = 0.7;

const SCRIPTS: { re: RegExp; lang: string }[] = [
  { re: /\p{Script=Devanagari}/gu, lang: "hi" },
  { re: /\p{Script=Bengali}/gu, lang: "bn" },
  { re: /\p{Script=Tamil}/gu, lang: "ta" },
  { re: /\p{Script=Telugu}/gu, lang: "te" },
  { re: /\p{Script=Gujarati}/gu, lang: "gu" },
  { re: /\p{Script=Gurmukhi}/gu, lang: "pa" },
  { re: /\p{Script=Kannada}/gu, lang: "kn" },
  { re: /\p{Script=Malayalam}/gu, lang: "ml" },
  { re: /\p{Script=Arabic}/gu, lang: "ar" },
  { re: /\p{Script=Cyrillic}/gu, lang: "ru" },
  { re: /[\p{Script=Hiragana}\p{Script=Katakana}]/gu, lang: "ja" },
  { re: /\p{Script=Hangul}/gu, lang: "ko" },
  { re: /\p{Script=Han}/gu, lang: "zh" },
  { re: /\p{Script=Thai}/gu, lang: "th" },
  { re: /\p{Script=Greek}/gu, lang: "el" },
  { re: /\p{Script=Hebrew}/gu, lang: "he" },
];

const EN_WORDS = new Set(
  (
    "the a an and or but if then so of to in on at for from with without by about as is are was were be been am do does did have has had will would can could should may might must " +
    "i me my we our you your he she it its they them their this that these those there here what why how when where which who whom not no yes please just also very more most some any all " +
    "get got make made use using need want help show tell give find write explain fix add create build run set into out up down over than too like way new one two how's what's it's i'm don't can't"
  ).split(" "),
);

/** Function words that confirm a Latin-script guess from the n-gram model. */
const STOP: Record<string, Set<string>> = Object.fromEntries(
  Object.entries({
    de: "der die das und ist nicht ich du wie kann mir dir mein meine ein eine einen mit für auf von zu den dem des bitte wir sie er es dass bin sind wird war haben hat auch oder aber zum zur im am über nach bei aus mich dich nur noch schon wenn wo was warum",
    es: "el la los las un una y es que de del en por para con mi me te se como puedo qué cómo cuál está son al más muy pero también sobre este esta estoy tengo quiero hay una mis lo le su sus qué por",
    fr: "le la les un une et est que de du des en pour avec mon ma mes je tu il nous vous ce cette comment quoi pas qui sur dans au aux suis peux veux ne mais très aussi où",
    pt: "o a os as um uma e é que de do da dos das em para com meu minha eu você como não mais mas muito está são tenho quero um uma por",
    it: "il lo la gli le un una e è che di del della in per con mio mia io tu come non più ma molto sono ho voglio cosa dove",
    nl: "de het een en is dat niet ik je hoe kan mijn met voor op van naar ook maar zijn wat wil heb ben",
  }).map(([k, v]) => [k, new Set(v.split(" "))]),
);
const OTHER_STOP = new Set(Object.values(STOP).flatMap((s) => [...s]));

/** Romanised Hindi words that are not also common English/Spanish/German words. */
const HINGLISH = new Set(
  (
    "hai hain hoon hu hoga hogi honge tha thi hua hui kya kyu kyun kyon kaise kaisa kaisi kab kahan kaha kaun konsa rahega rahegi ya kitna kitne kitni mujhe mujhko mera meri mere tumhe tumhara tum aap apna apni apne hum humein " +
    "nahi nahin nhi mat bhai yaar yar bhaiya dost karo kar karna karke kiya kare karein karun karu kijiye chahiye chahta chahti chahte batao bata batana samjhao samjha likho likh likhna banao bana banana " +
    "dikhao dikha abhi aur lekin magar toh isliye kyunki ka ki ke ko mein andar bahut bohot zyada thoda thodi ek koi kuch sab kal aaj parso acha accha achha theek thik sahi galat " +
    "wala wali wale raha rahi rahe rha rhi sakta sakte sakti sakta lagta lagti lagega milega milta dena lena jao jana chalo chal ruk bolo bol sunao suno dekho dekh pehle pahle baad matlab samajh pata " +
    "paisa kaam ghar naam hona hota hoti hote lo do na ji haan han bas bilkul jaldi aisa aise waise yeh ye woh wo uska uski unka iska iski isme usme mujhse tumse usse isse"
  )
    .split(" ")
    // "do", "lo", "na", "ho", "to" collide with English/Spanish; they only count next to other markers.
    .filter((w) => !["do", "lo", "na"].includes(w)),
);

// English words that are also function words elsewhere (no, me, was, die...) must not count as English evidence.
for (const w of [...EN_WORDS]) if (OTHER_STOP.has(w)) EN_WORDS.delete(w);

const names = (() => {
  try {
    return new Intl.DisplayNames(["en"], { type: "language" });
  } catch {
    return null;
  }
})();

export function languageName(code: string): string {
  if (code === "hi-Latn") return "Hinglish";
  try {
    return names?.of(code) ?? code;
  } catch {
    return code;
  }
}

/** Removes things that are not prose: code fences, inline code, URLs, emails, paths, identifiers, numbers. */
export function stripNonProse(text: string): string {
  return text
    .replace(/```[\s\S]*?(```|$)/g, " ")
    .replace(/`[^`]*`/g, " ")
    .replace(/https?:\/\/\S+|www\.\S+/gi, " ")
    .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, " ")
    .replace(/(?:[\w.-]*\/)+[\w.-]*/g, " ")
    .replace(/\b\w*(?:_|[a-z][A-Z]|\d)\w*\b/g, " ")
    .replace(/[{}[\]()<>=;$#*+|\\^~]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const wordsOf = (s: string) => s.toLowerCase().match(/[\p{L}][\p{L}'’]*/gu) ?? [];

function detectOnce(raw: string): { code: string; confidence: number; reliable: boolean } {
  const text = capTokens(raw.slice(0, 1000));
  const prose = stripNonProse(text);
  const letters = (prose.match(/\p{L}/gu) ?? []).length;
  if (letters === 0) return { code: "und", confidence: 0, reliable: false };
  const codeHeavy = stripNonProse(text).length < text.trim().length * 0.4 && text.length > 40;

  // 1. Non-Latin script dominates.
  let best: { lang: string; n: number } | null = null;
  for (const s of SCRIPTS) {
    const n = (prose.match(s.re) ?? []).length;
    if (n > (best?.n ?? 0)) best = { lang: s.lang, n };
  }
  if (best && best.n / letters >= 0.4) {
    let lang = best.lang;
    const hit = detectAll(prose)[0];
    // Let the model separate hi/mr/ne, ar/fa/ur, ru/uk/bg; ja and zh come from the script itself.
    if (hit && !["ja", "zh"].includes(lang) && SAME_SCRIPT[lang]?.includes(hit.lang)) lang = hit.lang;
    return { code: lang, confidence: Math.min(0.98, 0.8 + (best.n / letters) * 0.2), reliable: letters >= 3 };
  }

  // 2. Latin script from here on.
  const words = wordsOf(prose);
  if (words.length === 0) return { code: "und", confidence: 0, reliable: false };
  const en = words.filter((w) => EN_WORDS.has(w)).length;
  const hing = words.filter((w) => HINGLISH.has(w)).length;
  const enRatio = en / words.length;
  const hingRatio = hing / words.length;

  // Romanised Hindi: several markers, and clearly more Hindi than English function words.
  if (hing >= 2 && hingRatio >= 0.2 && hing >= en) {
    return { code: "hi-Latn", confidence: Math.min(0.95, 0.6 + hingRatio * 0.7 + Math.min(hing, 6) * 0.03), reliable: true };
  }
  if (words.length <= 2) {
    // "ok", "thanks", "hola": too little to tell. English function words still count.
    return { code: en > 0 ? "en" : "und", confidence: en > 0 ? 0.6 : 0.2, reliable: false };
  }
  if (enRatio >= 0.3 || (enRatio >= 0.2 && words.length <= 6)) {
    return { code: "en", confidence: Math.min(0.97, 0.7 + enRatio * 0.5) * (codeHeavy ? 0.85 : 1), reliable: !codeHeavy };
  }

  const hits = detectAll(prose);
  const top = hits[0];
  if (!top) return { code: "und", confidence: 0.2, reliable: false };
  const second = hits[1]?.accuracy ?? 0;
  const margin = top.accuracy / (top.accuracy + second + 1e-9);
  let conf = margin * Math.min(1, 0.45 + words.length / 8);
  // A few Hindi markers inside an otherwise ambiguous line still mean Hinglish rather than a random European language.
  if (hing >= 2 && top.lang !== "en") return { code: "hi-Latn", confidence: Math.min(0.85, 0.55 + hing * 0.1), reliable: true };
  const list = STOP[top.lang];
  if (list) {
    const n = words.filter((w) => list.has(w)).length;
    if (n >= (words.length <= 6 ? 1 : 2) && margin >= 0.45) conf = Math.max(conf, 0.72);
    else if (n === 0 && words.length < 8) conf *= 0.6;
  } else if (words.length < 6) {
    // No function-word evidence for this language: a short guess is not trusted.
    conf = Math.min(conf, 0.6);
  }
  if (codeHeavy) conf *= 0.6;
  return { code: top.lang, confidence: Math.min(0.98, conf), reliable: conf >= REPLY_LANG_MIN_CONFIDENCE && !codeHeavy };
}

const SAME_SCRIPT: Record<string, string[]> = {
  hi: ["hi", "mr", "ne", "sa"],
  ar: ["ar", "fa", "ur"],
  ru: ["ru", "uk", "bg", "sr", "be", "mk"],
};

/**
 * Language of [text]. When the text is too short, mostly code, or otherwise
 * unsure, the most recent [history] message (newest first) that gives a
 * confident answer decides instead. Without any signal it is English.
 */
export function detectLanguage(text: string, history: string[] = []): LangResult {
  const own = detectOnce(text ?? "");
  if (own.reliable && own.confidence >= REPLY_LANG_MIN_CONFIDENCE) {
    return { code: own.code, name: languageName(own.code), confidence: round(own.confidence), source: "text" };
  }
  for (const h of history.slice(0, 4)) {
    const r = detectOnce(h ?? "");
    if (r.reliable && r.confidence >= REPLY_LANG_MIN_CONFIDENCE) {
      return { code: r.code, name: languageName(r.code), confidence: round(r.confidence * 0.9), source: "history" };
    }
  }
  // Low-confidence Latin text is English, never a random European language.
  if (own.code === "en") return { code: "en", name: "English", confidence: round(Math.max(own.confidence, 0.5)), source: "text" };
  return { ...DEFAULT };
}

const round = (n: number) => Math.round(n * 100) / 100;

export function isEnglish(r: LangResult): boolean {
  return r.code === "en" || r.code === "und";
}

/**
 * One-line reply-language instruction, or null: English, an explicit profile
 * language (that setting already says what to do) and low confidence add nothing.
 */
export function languageInstruction(r: LangResult, profileLanguage?: string): string | null {
  if (profileLanguage?.trim()) return null;
  if (isEnglish(r) || r.confidence < REPLY_LANG_MIN_CONFIDENCE) return null;
  if (r.code === "hi-Latn") return "Reply in Hinglish (Hindi written in Roman letters), matching the user's mix of Hindi and English. Keep code and technical terms as they are.";
  return `Reply in ${r.name}. Keep code, identifiers and technical terms in their original form.`;
}

/** A short clause for helper prompts ("Write in German."), or null for English. */
export function languageClause(r: LangResult | undefined): string | null {
  if (!r || isEnglish(r) || r.confidence < REPLY_LANG_MIN_CONFIDENCE) return null;
  return r.code === "hi-Latn" ? "Write in Hinglish (Hindi in Roman letters), like the user." : `Write in ${r.name}.`;
}
