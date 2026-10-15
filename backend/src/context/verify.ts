/**
 * Server post-pass on every reply: contact details that are not in the turn's sources.
 *
 * Models invent phone numbers, e-mail addresses, street addresses and links ("Hotel Sahil +91-2114-272727").
 * A detail survives only if it also appears in what the turn actually had: web / knowledge / document / GitHub
 * sources, place look-ups, or the user's own messages. Everything else is replaced by a plain note (or, for a
 * Markdown link, reduced to its text). Fenced blocks (code, cards, widgets) and inline code are left alone.
 */

export const NOTE_PHONE = "(number not verified)";
export const NOTE_EMAIL = "(email not verified)";
export const NOTE_ADDRESS = "(check on Maps)";
export const NOTE_URL = "(link not verified)";

// ---- phones ------------------------------------------------------------------

/**
 * A candidate phone number: optional +/00, 8-14 digits with spaces, dashes, dots between groups or in brackets.
 * Dates, decimals and amounts are filtered afterwards.
 */
const PHONE_RE = /(?<![\w@./:-])(?:\+|00)?\(?\d[\d\s().-]{6,17}\d(?![\w@])/g;

/** National significant digits for comparing numbers: no +, 00 or 0 prefix, no 91/1/44 country code when a 10-digit rest remains. */
export function phoneDigits(raw: string): string {
  let d = raw.replace(/\D/g, "");
  if (raw.trim().startsWith("00")) d = d.slice(2);
  if (d.length > 10) d = d.slice(-10);
  else d = d.replace(/^0+/, "");
  return d;
}

const DATE_LIKE = /^\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}$/;

function looksLikePhone(raw: string): boolean {
  const s = raw.trim();
  const digits = s.replace(/\D/g, "");
  if (digits.length < 8 || digits.length > 14) return false;
  if (DATE_LIKE.test(s)) return false;
  if (/^\d+\.\d+/.test(s) && !/\s/.test(s)) return false; // 12.9716 / version numbers / coordinates
  if (/^\d{4}\s*[-–]\s*\d{4}$/.test(s)) return false; // year range
  if (/^\d[\d.]*\d$/.test(s) && /\./.test(s)) return false; // dotted run without spaces
  return true;
}

/** Every phone-like string in [text] (with its position). */
export function findPhones(text: string): Array<{ raw: string; index: number }> {
  const out: Array<{ raw: string; index: number }> = [];
  for (const m of text.matchAll(PHONE_RE)) {
    const raw = m[0].replace(/[\s.-]+$/, "").replace(/^[\s(]+(?=\d)/, (x) => x.replace(/\s/g, ""));
    if (looksLikePhone(raw)) out.push({ raw, index: m.index ?? 0 });
  }
  return out;
}

// ---- emails, urls, addresses -------------------------------------------------

const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/g;
const MD_LINK_RE = /\[([^\]\n]{1,200})\]\((https?:\/\/[^\s)]+)\)/g;
const URL_RE = /\bhttps?:\/\/[^\s<>()\[\]"'`]+|\bwww\.[a-z0-9-]+(?:\.[a-z0-9-]+)+[^\s<>()\[\]"'`]*/gi;

/** A URL reduced to host + path for comparison (no scheme, www, query, fragment, trailing slash or trailing punctuation). */
export const urlKey = (u: string): string =>
  u
    .replace(/[.,;:!?)\]]+$/, "")
    .replace(/^https?:\/\/(www\.)?/i, "")
    .replace(/^www\./i, "")
    .replace(/[?#].*$/, "")
    .replace(/\/+$/, "")
    .toLowerCase();

const STREET_RE =
  /\b(?:(?:Plot|Survey|Gat|Shop|Flat|House|Door|No\.?|#)\s*(?:No\.?\s*)?\d+[A-Za-z/-]*,?\s+)?\d+[A-Za-z]?(?:\/\d+)?,?\s+(?:[A-Z][\w.'-]*\s+){1,4}(?:Road|Rd\.?|Street|St\.?|Lane|Marg|Highway|Avenue|Ave\.?|Cross|Main|Nagar|Chowk)\b(?:,\s*[A-Z][\w']+(?: [A-Z][\w']+)*){0,2}/g;

// ---- the sources -------------------------------------------------------------

export type Known = { phones: Set<string>; emails: Set<string>; urls: Set<string>; text: string };

/** What the turn legitimately knew: build once from the sources and the user's messages. */
export function knownFrom(sources: string[]): Known {
  const phones = new Set<string>();
  const emails = new Set<string>();
  const urls = new Set<string>();
  const joined = sources.join("\n");
  for (const p of findPhones(joined)) phones.add(phoneDigits(p.raw));
  // Numbers glued to words ("Tel:+912114272727") or in a run without separators are caught by a plain digit scan too.
  for (const m of joined.matchAll(/(?<![\d])\+?\d{10,13}(?![\d])/g)) phones.add(phoneDigits(m[0]));
  for (const m of joined.matchAll(EMAIL_RE)) emails.add(m[0].toLowerCase());
  for (const m of joined.matchAll(URL_RE)) urls.add(urlKey(m[0]));
  return { phones, emails, urls, text: joined.toLowerCase() };
}

// ---- the pass ----------------------------------------------------------------

function scrubPlain(s: string, k: Known): string {
  let out = s.replace(MD_LINK_RE, (whole, label: string, url: string) => (k.urls.has(urlKey(url)) ? whole : label));
  // Markdown links that survived hold a verified URL: park them so the bare-URL pass does not touch them.
  const parked: string[] = [];
  out = out.replace(MD_LINK_RE, (whole) => `\u0000${parked.push(whole) - 1}\u0000`);
  out = out.replace(URL_RE, (u) => (k.urls.has(urlKey(u)) ? u : NOTE_URL));
  out = out.replace(EMAIL_RE, (e) => (k.emails.has(e.toLowerCase()) ? e : NOTE_EMAIL));
  out = out.replace(STREET_RE, (a) => (k.text.includes(a.toLowerCase().replace(/,.*$/, "").trim()) ? a : NOTE_ADDRESS));
  const phones = findPhones(out);
  for (const p of phones.reverse()) {
    if (k.phones.has(phoneDigits(p.raw))) continue;
    out = out.slice(0, p.index) + NOTE_PHONE + out.slice(p.index + p.raw.length);
  }
  return out.replace(/\u0000(\d+)\u0000/g, (_w, i: string) => parked[Number(i)]);
}

/** [text] with every unverified phone, e-mail, link and street address replaced. Code, fenced blocks and inline code are kept. */
export function scrubUnverified(text: string, sources: string[]): string {
  const k = knownFrom(sources);
  const lines = text.split("\n");
  let fence: string | null = null;
  const out: string[] = [];
  for (const line of lines) {
    const f = /^\s*(`{3,}|~{3,})/.exec(line);
    if (fence) {
      if (f && f[1][0] === fence[0] && f[1].length >= fence.length) fence = null;
      out.push(line);
      continue;
    }
    if (f) {
      fence = f[1];
      out.push(line);
      continue;
    }
    // Inline code spans stay as they are.
    out.push(line.split(/(`[^`\n]*`)/).map((part, i) => (i % 2 === 1 ? part : scrubPlain(part, k))).join(""));
  }
  return out.join("\n");
}

/** Whether [scrubbed] differs from [text] only by notes (used for logging). */
export const countNotes = (s: string): number => [NOTE_PHONE, NOTE_EMAIL, NOTE_ADDRESS, NOTE_URL].reduce((n, note) => n + s.split(note).length - 1, 0);
