// PII and secret detection with checksum validation (Luhn, Verhoeff, IBAN mod 97).
// Pure and dependency-free. Used to keep secrets out of memories, external
// search queries and logs; the main LLM always gets the user's text unchanged.

export type PiiKind =
  | "private_key"
  | "jwt"
  | "api_key"
  | "password"
  | "email"
  | "card"
  | "iban"
  | "aadhaar"
  | "pan"
  | "phone"
  | "ip";

export type PiiSpan = { kind: PiiKind; start: number; end: number; value: string };

const LABEL: Record<PiiKind, string> = {
  private_key: "[PRIVATE_KEY]",
  jwt: "[JWT]",
  api_key: "[API_KEY]",
  password: "[PASSWORD]",
  email: "[EMAIL]",
  card: "[CARD]",
  iban: "[IBAN]",
  aadhaar: "[AADHAAR]",
  pan: "[PAN]",
  phone: "[PHONE]",
  ip: "[IP]",
};

/** Overlap priority: earlier wins. */
const PRIORITY: PiiKind[] = ["private_key", "jwt", "api_key", "password", "email", "card", "iban", "aadhaar", "pan", "phone", "ip"];

/** Credentials and identity numbers that must never be stored. */
export const SECRET_KINDS: readonly PiiKind[] = ["private_key", "jwt", "api_key", "password", "card", "aadhaar"];

// ---- checksums ---------------------------------------------------------------------------

export function luhn(digits: string): boolean {
  if (!/^\d{12,19}$/.test(digits)) return false;
  let sum = 0;
  let dbl = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48;
    if (dbl) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    dbl = !dbl;
  }
  return sum % 10 === 0;
}

const V_D = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
  [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
  [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
  [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
  [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
  [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
  [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
  [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
  [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];
const V_P = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
  [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
  [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
  [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
  [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
  [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
  [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

/** Verhoeff check of a number whose last digit is the check digit. */
export function verhoeff(digits: string): boolean {
  if (!/^\d+$/.test(digits)) return false;
  let c = 0;
  const rev = [...digits].reverse();
  for (let i = 0; i < rev.length; i++) c = V_D[c][V_P[i % 8][Number(rev[i])]];
  return c === 0;
}

/** Aadhaar: 12 digits, first digit 2-9, Verhoeff check digit. */
export const isAadhaar = (digits: string) => /^[2-9]\d{11}$/.test(digits) && verhoeff(digits);

export function ibanValid(raw: string): boolean {
  const s = raw.replace(/\s+/g, "").toUpperCase();
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(s)) return false;
  const moved = s.slice(4) + s.slice(0, 4);
  let rem = 0;
  for (const ch of moved) {
    const v = ch >= "A" ? String(ch.charCodeAt(0) - 55) : ch;
    for (const d of v) rem = (rem * 10 + (d.charCodeAt(0) - 48)) % 97;
  }
  return rem === 1;
}

/** Card number with a known issuer prefix and length, passing Luhn (keeps timestamps and ids out). */
export function isCardNumber(digits: string): boolean {
  const n = digits.length;
  if (!luhn(digits) || n < 13 || n > 19) return false;
  const p2 = Number(digits.slice(0, 2));
  const p4 = Number(digits.slice(0, 4));
  if (digits[0] === "4") return n === 13 || n === 16 || n === 19;
  if ((p2 >= 51 && p2 <= 55) || (p4 >= 2221 && p4 <= 2720)) return n === 16;
  if (p2 === 34 || p2 === 37) return n === 15;
  if (p2 === 36 || p2 === 38 || p2 === 30) return n >= 14 && n <= 16;
  if (p2 === 35) return n >= 16 && n <= 19;
  if (p4 === 6011 || p2 === 65 || p2 === 64) return n >= 16 && n <= 19;
  if (p2 === 60 || p2 === 81 || p2 === 82 || digits.startsWith("508")) return n === 16; // RuPay
  if (p2 === 62) return n >= 16 && n <= 19; // UnionPay
  return false;
}

// ---- detectors ---------------------------------------------------------------------------

type Found = { start: number; end: number; value?: string };
type Detector = { kind: PiiKind; find: (text: string) => Found[] };

function all(re: RegExp, text: string, pick: (m: RegExpExecArray) => Found | null): Found[] {
  const out: Found[] = [];
  for (const m of text.matchAll(new RegExp(re.source, re.flags.includes("g") ? re.flags : re.flags + "g"))) {
    const f = pick(m as RegExpExecArray);
    if (f) out.push(f);
  }
  return out;
}
const whole = (m: RegExpExecArray): Found => ({ start: m.index!, end: m.index! + m[0].length });
const digitsOf = (s: string) => s.replace(/\D/g, "");

const DETECTORS: Detector[] = [
  {
    kind: "private_key",
    find: (t) => all(/-----BEGIN [A-Z ]*PRIVATE KEY(?: BLOCK)?-----(?:[\s\S]*?-----END [A-Z ]*PRIVATE KEY(?: BLOCK)?-----|[\s\S]*$)/, t, whole),
  },
  { kind: "jwt", find: (t) => all(/\beyJ[\w-]{5,}\.eyJ[\w-]{5,}\.[\w-]{0,}/, t, whole) },
  {
    kind: "api_key",
    find: (t) => [
      ...all(
        /\b(?:sk-(?:ant-|proj-|live-)?[A-Za-z0-9_-]{20,}|(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{16,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|npm_[A-Za-z0-9]{30,}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|hf_[A-Za-z0-9]{30,})/,
        t,
        whole,
      ),
      // "api key: abc123...", "secret = ...", "Authorization: Bearer ..." -> the value only.
      ...all(/\b(?:api[\s_-]?key|secret(?:[\s_-]?key)?|access[\s_-]?token|auth[\s_-]?token|client[\s_-]?secret|token)\b\s*(?:is|=|:)\s*["']?([A-Za-z0-9_\-./+=]{12,})/i, t, (m) => {
        const v = m[1];
        // A plain lowercase word is a description, not a key.
        if (!/\d/.test(v) && !/[A-Z]/.test(v)) return null;
        const s = m.index! + m[0].lastIndexOf(v);
        return { start: s, end: s + v.length };
      }),
      ...all(/\bBearer\s+([A-Za-z0-9_\-.=]{20,})/, t, (m) => {
        const s = m.index! + m[0].lastIndexOf(m[1]);
        return { start: s, end: s + m[1].length };
      }),
    ],
  },
  {
    kind: "password",
    find: (t) =>
      all(/\b(?:password|passwd|pwd|passphrase|passcode)\b\s*(?:is|=|:)\s*["']?([^\s"',;]{3,})/i, t, (m) => {
        const s = m.index! + m[0].lastIndexOf(m[1]);
        return { start: s, end: s + m[1].length };
      }),
  },
  { kind: "email", find: (t) => all(/(?<![\w.+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b/, t, whole) },
  {
    kind: "card",
    find: (t) => [
      ...all(/(?<![\w-])\d{13,19}(?![\w-])/, t, (m) => (isCardNumber(m[0]) ? whole(m) : null)),
      ...all(/(?<![\w-])\d{4}([ -])\d{4}\1\d{4}\1\d{1,7}(?:\1\d{1,3})?(?![\w-])/, t, (m) => (isCardNumber(digitsOf(m[0])) ? whole(m) : null)),
      ...all(/(?<![\w-])3[47]\d{2}([ -])\d{6}\1\d{5}(?![\w-])/, t, (m) => (isCardNumber(digitsOf(m[0])) ? whole(m) : null)),
    ],
  },
  {
    kind: "iban",
    find: (t) => all(/(?<![\w-])[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,3})?(?![\w-])/, t, (m) => (ibanValid(m[0]) ? whole(m) : null)),
  },
  {
    kind: "aadhaar",
    find: (t) => [
      ...all(/(?<![\w.-])[2-9]\d{11}(?![\w-]|\.\d)/, t, (m) => (isAadhaar(m[0]) ? whole(m) : null)),
      ...all(/(?<![\w.-])[2-9]\d{3}([ -])\d{4}\1\d{4}(?![\w-]|\.\d)/, t, (m) => (isAadhaar(digitsOf(m[0])) ? whole(m) : null)),
    ],
  },
  { kind: "pan", find: (t) => all(/(?<![\w-])[A-Z]{3}[ABCFGHJLPT][A-Z]\d{4}[A-Z](?![\w-])/, t, whole) },
  {
    kind: "phone",
    find: (t) => [
      // Indian mobile: optional +91 / 0091 / 91 / 0, then 6-9 + 9 digits (also grouped 5+5).
      ...all(/(?<![\w.+-])(?:(?:\+|00)91[\s-]?|91[\s-]|0)?[6-9]\d{4}[\s-]?\d{5}(?![\w-]|\.\d)/, t, (m) => {
        const d = digitsOf(m[0]);
        return d.length === 10 || d.length === 11 || d.length === 12 || d.length === 14 ? whole(m) : null;
      }),
      // International: +CC followed by 7-13 digits in short groups.
      ...all(/(?<![\w.+-])\+[1-9]\d{0,2}(?:[\s.-]?\(?\d{1,5}\)?){2,5}(?![\w-]|\.\d)/, t, (m) => {
        const d = digitsOf(m[0]);
        return d.length >= 8 && d.length <= 15 && !/^\+\d{2}:\d{2}/.test(m[0]) ? whole(m) : null;
      }),
      // North American 3-3-4 with separators.
      ...all(/(?<![\w.-])(?:\(\d{3}\)\s?|\d{3}[\s.-])\d{3}[\s.-]\d{4}(?![\w-]|\.\d)/, t, whole),
    ],
  },
  {
    kind: "ip",
    find: (t) => [
      ...all(/(?<![\w.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\w]|\.\d)/, t, (m) => {
        const v = m[0];
        if (v === "0.0.0.0" || v.startsWith("127.") || v === "255.255.255.255") return null;
        const before = t.slice(Math.max(0, m.index! - 14), m.index!);
        if (/\b(?:v|ver|version|release|node|python|go|rust|java|ios|android|api)\s*$/i.test(before)) return null;
        return whole(m);
      }),
      ...all(/(?<![\w:])(?:[0-9a-f]{1,4}:){7}[0-9a-f]{1,4}(?![\w:])/i, t, whole),
      ...all(/(?<![\w:])(?:[0-9a-f]{1,4}:){1,6}(?::[0-9a-f]{1,4}){1,6}(?![\w:])/i, t, (m) => {
        const groups = m[0].split(":").filter(Boolean);
        return groups.length >= 2 && groups.some((g) => g.length === 4) ? whole(m) : null;
      }),
    ],
  },
];

/** Typed, non-overlapping PII/secret spans in order of position. */
export function detectPii(text: string, kinds?: readonly PiiKind[]): PiiSpan[] {
  if (!text) return [];
  const cands: Array<PiiSpan & { pri: number }> = [];
  for (const d of DETECTORS) {
    if (kinds && !kinds.includes(d.kind)) continue;
    const pri = PRIORITY.indexOf(d.kind);
    for (const f of d.find(text)) cands.push({ kind: d.kind, start: f.start, end: f.end, value: text.slice(f.start, f.end), pri });
  }
  cands.sort((a, b) => a.pri - b.pri || a.start - b.start);
  const taken: PiiSpan[] = [];
  for (const c of cands) {
    if (taken.some((t) => c.start < t.end && t.start < c.end)) continue;
    taken.push({ kind: c.kind, start: c.start, end: c.end, value: c.value });
  }
  return taken.sort((a, b) => a.start - b.start);
}

/** Replaces each detected span with its label ([EMAIL], [CARD], ...). */
export function redact(text: string, kinds?: readonly PiiKind[]): string {
  const spans = detectPii(text, kinds);
  if (!spans.length) return text;
  let out = "";
  let at = 0;
  for (const s of spans) {
    out += text.slice(at, s.start) + LABEL[s.kind];
    at = s.end;
  }
  return out + text.slice(at);
}

export const hasPii = (text: string, kinds?: readonly PiiKind[]) => detectPii(text, kinds).length > 0;
export const hasSecret = (text: string) => hasPii(text, SECRET_KINDS);

// ---- policies ----------------------------------------------------------------------------

/**
 * A memory candidate made safe: null when it holds a secret, card or Aadhaar
 * number; otherwise contact details and ids are redacted unless the user said
 * to remember it explicitly.
 */
export function sanitizeMemory(text: string, explicit = false): string | null {
  if (hasSecret(text)) return null;
  return explicit ? text : redact(text);
}

/** Text for a non-LLM external service (web, GitHub or image search): all PII redacted. */
export function redactForExternal(text: string): string {
  return redact(text).replace(/\s{2,}/g, " ").trim();
}

/** Free-text log/telemetry fields: redacted and capped. */
export function redactForLog(text: string, max = 200): string {
  const r = redact(text);
  return r.length > max ? r.slice(0, max) + "…" : r;
}

const NOTE_KINDS: readonly PiiKind[] = ["card", "password", "private_key", "api_key", "jwt", "aadhaar"];

/**
 * A short system note for the model when the user's message contains a secret,
 * or null. The note never includes the secret itself.
 */
export function safetyNote(text: string): string | null {
  const kinds = [...new Set(detectPii(text, NOTE_KINDS).map((s) => s.kind))];
  if (!kinds.length) return null;
  const names = kinds.map((k) => ({ card: "a payment card number", password: "a password", private_key: "a private key", api_key: "an API key or token", jwt: "an auth token", aadhaar: "an Aadhaar number" })[k as "card"]);
  return `Safety note: the user's message appears to contain ${names.join(", ")}. Answer the question, but briefly remind them not to share secrets in chat (and to rotate it if it is real), and never repeat the secret back in your reply.`;
}
