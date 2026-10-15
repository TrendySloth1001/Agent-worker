/**
 * Every link and phone intent an action card can carry, built in one place.
 *
 * A card's button is a CardIntent: an allow-listed action (view, dial, send,
 * set an alarm...) plus data. Nothing here opens or sends anything; the app
 * runs an intent only when the user taps its button, and re-checks it against
 * the same allow-lists (lib/core/constants/intent_cards.dart, CardIntents.kt).
 * Params are always encoded; a scheme or host that is not listed is dropped.
 */

export type IntentAction = "view" | "dial" | "sendto" | "send" | "set_alarm" | "set_timer" | "insert_event" | "insert_contact" | "launch";

export type Extras = Record<string, string | number | boolean>;

export type CardIntent = {
  action: IntentAction;
  uri?: string;
  /** Android package: used when installed, else the intent runs without it. */
  package?: string;
  /** https link tried when the intent cannot run (app missing). */
  fallback?: string;
  /** Wrap in the system chooser. */
  chooser?: boolean;
  extras?: Extras;
};

/** Schemes each action may carry in `uri`. */
export const URI_SCHEMES: Record<IntentAction, readonly string[]> = {
  view: ["https", "geo", "google.navigation", "upi"],
  dial: ["tel"],
  sendto: ["smsto", "mailto"],
  send: [],
  set_alarm: [],
  set_timer: [],
  insert_event: [],
  insert_contact: [],
  launch: [],
};

/** Extras each action may carry (everything else is dropped). */
export const EXTRA_KEYS: Record<IntentAction, readonly string[]> = {
  view: [],
  dial: [],
  sendto: ["body", "subject"],
  send: ["text"],
  set_alarm: ["hour", "minutes", "message"],
  set_timer: ["length", "message"],
  insert_event: ["title", "begin", "end", "allDay", "location", "description"],
  insert_contact: ["name", "phone", "email"],
  launch: [],
};

/** https hosts a card may link to (a leading dot matches subdomains). */
export const ALLOWED_HOSTS: readonly string[] = [
  "www.google.com",
  "maps.google.com",
  "google.com",
  "play.google.com",
  "wa.me",
  "www.amazon.in",
  "amazon.in",
  "www.flipkart.com",
  "www.myntra.com",
  "www.swiggy.com",
  "www.zomato.com",
  "m.uber.com",
  "www.uber.com",
  "www.olacabs.com",
  "www.rapido.bike",
  "www.irctc.co.in",
  "www.ixigo.com",
  "www.makemytrip.com",
  "www.openstreetmap.org",
];

export const isAllowedHost = (host: string): boolean => ALLOWED_HOSTS.includes(host.toLowerCase());

/** The parsed scheme of [uri] (lowercase), or null. */
function schemeOf(uri: string): string | null {
  const m = /^([a-z][a-z0-9+.-]*):/i.exec(uri);
  return m ? m[1].toLowerCase() : null;
}

/** [url] when it is an https link to a listed host, else null. */
export function safeHttps(url: string | undefined): string | null {
  if (!url || url.length > 2000) return null;
  try {
    const u = new URL(url);
    return u.protocol === "https:" && !u.username && !u.password && isAllowedHost(u.hostname) ? u.toString() : null;
  } catch {
    return null;
  }
}

/** Android package names are dotted identifiers. */
const PACKAGE_RE = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/i;

/**
 * [i] cleaned against the allow-lists: unknown schemes, hosts, extras and
 * packages are dropped; null when nothing runnable is left.
 */
export function sanitizeIntent(i: CardIntent): CardIntent | null {
  const uri = i.uri;
  let outUri: string | undefined;
  if (uri !== undefined) {
    const scheme = schemeOf(uri);
    if (!scheme || !URI_SCHEMES[i.action]?.includes(scheme) || uri.length > 2000) return null;
    if (scheme === "https" && !safeHttps(uri)) return null;
    outUri = uri;
  } else if (URI_SCHEMES[i.action]?.length) {
    return null;
  }
  if (!(i.action in EXTRA_KEYS)) return null;
  const extras: Extras = {};
  for (const [k, v] of Object.entries(i.extras ?? {})) {
    if (!EXTRA_KEYS[i.action].includes(k)) continue;
    if (typeof v === "string") extras[k] = v.slice(0, 1500);
    else if (typeof v === "number" && Number.isFinite(v)) extras[k] = v;
    else if (typeof v === "boolean") extras[k] = v;
  }
  if (i.action === "launch" && !(i.package && PACKAGE_RE.test(i.package))) return null;
  const fallback = safeHttps(i.fallback);
  return {
    action: i.action,
    ...(outUri ? { uri: outUri } : {}),
    ...(i.package && PACKAGE_RE.test(i.package) ? { package: i.package } : {}),
    ...(fallback ? { fallback } : {}),
    ...(i.chooser ? { chooser: true } : {}),
    ...(Object.keys(extras).length ? { extras } : {}),
  };
}

// ---- packages ---------------------------------------------------------------

export const PKG = {
  maps: "com.google.android.apps.maps",
  whatsapp: "com.whatsapp",
  amazon: "in.amazon.mShop.android.shopping",
  flipkart: "com.flipkart.android",
  myntra: "com.myntra.android",
  swiggy: "in.swiggy.android",
  zomato: "com.application.zomato",
  uber: "com.ubercab",
  ola: "com.olacabs.customer",
  rapido: "com.rapido.passenger",
  irctc: "cris.org.in.prs.ima",
  ixigo: "com.ixigo.train.ixitrain",
  makemytrip: "com.makemytrip",
} as const;

const enc = encodeURIComponent;

// ---- text -------------------------------------------------------------------

/** A single clean line of at most [n] characters. */
export const clip = (s: unknown, n: number): string => (typeof s === "string" || typeof s === "number" ? String(s) : "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim().slice(0, n);

// ---- phone numbers ----------------------------------------------------------

/**
 * A phone number as "+<digits>" (7-15 digits), or null. A bare 10-digit
 * mobile number starting 6-9 is taken as Indian (+91); a leading 0 is dropped.
 */
export function normalizePhone(raw: string): string | null {
  const s = raw.trim();
  const plus = s.startsWith("+") || s.startsWith("00");
  let digits = s.replace(/\D/g, "");
  if (s.startsWith("00")) digits = digits.slice(2);
  if (!plus) {
    digits = digits.replace(/^0+/, "");
    if (/^[6-9]\d{9}$/.test(digits)) digits = `91${digits}`;
  }
  return digits.length >= 7 && digits.length <= 15 ? `+${digits}` : null;
}

export const telUri = (number: string) => `tel:${number}`;
export const smsUri = (number: string) => `smsto:${number}`;

/** wa.me link; the message is only prefilled (the user presses send in WhatsApp). */
export function whatsappUrl(number: string, text?: string): string {
  const digits = number.replace(/\D/g, "");
  return `https://wa.me/${digits}${text ? `?text=${enc(text)}` : ""}`;
}

// ---- maps -------------------------------------------------------------------

export const mapsSearchUrl = (query: string) => `https://www.google.com/maps/search/?api=1&query=${enc(query)}`;
export const mapsDirectionsUrl = (destination: string) => `https://www.google.com/maps/dir/?api=1&destination=${enc(destination)}`;

/** Turn-by-turn directions in the Maps app; the maps.google.com link when it is not installed. */
export function directionsIntent(destination: string, coords?: { lat: number; lon: number }): CardIntent {
  const target = coords ? `${coords.lat},${coords.lon}` : destination;
  return { action: "view", uri: `google.navigation:q=${enc(target)}`, package: PKG.maps, fallback: mapsDirectionsUrl(coords ? `${coords.lat},${coords.lon}` : destination) };
}

export type TravelModeParam = "driving" | "transit" | "walking" | "bicycling";

/** Google Maps directions link; `origin` only when the user named a starting point (Maps uses their location otherwise). */
export const mapsDirUrl = (o: { destination: string; origin?: string; mode?: TravelModeParam }): string =>
  `https://www.google.com/maps/dir/?api=1&destination=${enc(o.destination)}${o.origin ? `&origin=${enc(o.origin)}` : ""}&travelmode=${o.mode ?? "driving"}`;

/** Live navigation from wherever the user is now: no origin needed. */
export const navigateIntent = (destination: string): CardIntent => ({ action: "view", uri: `google.navigation:q=${enc(destination)}`, package: PKG.maps, fallback: mapsDirUrl({ destination }) });

// ---- UPI --------------------------------------------------------------------

/** A virtual payment address: name@handle. The handle has no dot, so an email address is not one. */
const VPA_RE = /^[a-z0-9][a-z0-9._-]{1,255}@[a-z][a-z0-9]{1,63}$/i;
export const isValidVpa = (v: string): boolean => VPA_RE.test(v.trim());

/** Every VPA written in [text]. */
export function findVpas(text: string): string[] {
  const out = new Set<string>();
  for (const m of text.matchAll(/(?<![\w.@-])([a-z0-9][a-z0-9._-]{1,255}@[a-z][a-z0-9]{1,63})(?![\w@]|\.\w)/gi)) out.add(m[1]);
  return [...out];
}

/** An amount as "123.45", or null (positive, at most one lakh, two decimals). */
export function normalizeAmount(v: unknown): string | null {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v.replace(/[,₹\s]|rs\.?|inr/gi, "")) : NaN;
  if (!Number.isFinite(n) || n <= 0 || n > 100_000) return null;
  return (Math.round(n * 100) / 100).toString();
}

/** upi://pay deep link; only prefilled, the user confirms and pays in their UPI app. */
export function upiUri(o: { vpa: string; name?: string; amount?: string; note?: string }): string | null {
  if (!isValidVpa(o.vpa)) return null;
  const parts = [`pa=${enc(o.vpa.trim())}`];
  if (o.name) parts.push(`pn=${enc(o.name)}`);
  if (o.amount) parts.push(`am=${enc(o.amount)}`);
  if (o.note) parts.push(`tn=${enc(o.note)}`);
  parts.push("cu=INR");
  return `upi://pay?${parts.join("&")}`;
}

// ---- shopping, food, rides, travel ------------------------------------------

export const amazonSearchUrl = (q: string) => `https://www.amazon.in/s?k=${enc(q)}`;
export const flipkartSearchUrl = (q: string) => `https://www.flipkart.com/search?q=${enc(q)}`;
/** Myntra's own search path: /<words-with-dashes>?rawQuery=<words>. */
export const myntraSearchUrl = (q: string) => {
  const slug = q.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-|-$/g, "");
  return `https://www.myntra.com/${enc(slug || "search")}?rawQuery=${enc(q)}`;
};
export const swiggySearchUrl = (q: string) => `https://www.swiggy.com/search?query=${enc(q)}`;
export const zomatoSearchUrl = (q: string) => `https://www.zomato.com/search?q=${enc(q)}`;

/** Uber's universal link: pickup is the rider's location, dropoff is [destination]. */
export const uberUrl = (destination: string) => `https://m.uber.com/ul/?action=setPickup&pickup=my_location&${enc("dropoff[nickname]")}=${enc(destination)}&${enc("dropoff[formatted_address]")}=${enc(destination)}`;

export type TravelMode = "flight" | "train" | "bus";

/** Google Flights opens a results page for the free-text query. */
export function flightsUrl(o: { from: string; to: string; date?: string; returnDate?: string }): string {
  const q = `Flights from ${o.from} to ${o.to}${o.date ? ` on ${o.date}` : ""}${o.returnDate ? ` returning ${o.returnDate}` : ""}`;
  return `https://www.google.com/travel/flights?q=${enc(q)}`;
}

/** Web search for trains or buses between two places (the sites below take no public search params). */
export function travelSearchUrl(mode: TravelMode, o: { from: string; to: string; date?: string }): string {
  return `https://www.google.com/search?q=${enc(`${mode}s from ${o.from} to ${o.to}${o.date ? ` on ${o.date}` : ""}`)}`;
}

export const SITE = {
  irctc: "https://www.irctc.co.in/nget/train-search",
  ixigoTrains: "https://www.ixigo.com/trains",
  ixigoBus: "https://www.ixigo.com/bus",
  mmtTrains: "https://www.makemytrip.com/railways/",
  mmtBus: "https://www.makemytrip.com/bus-tickets/",
  mmtFlights: "https://www.makemytrip.com/flights/",
  ola: "https://www.olacabs.com/",
  rapido: "https://www.rapido.bike/",
} as const;

// ---- clock and calendar -----------------------------------------------------

export function alarmIntent(hour: number, minutes: number, message?: string): CardIntent {
  return { action: "set_alarm", extras: { hour, minutes, ...(message ? { message } : {}) } };
}

export function timerIntent(seconds: number, message?: string): CardIntent {
  return { action: "set_timer", extras: { length: seconds, ...(message ? { message } : {}) } };
}

export function eventIntent(o: { title: string; start: string; end?: string; allDay?: boolean; location?: string; notes?: string }): CardIntent {
  return {
    action: "insert_event",
    extras: {
      title: o.title,
      begin: o.start,
      ...(o.end ? { end: o.end } : {}),
      ...(o.allDay ? { allDay: true } : {}),
      ...(o.location ? { location: o.location } : {}),
      ...(o.notes ? { description: o.notes } : {}),
    },
  };
}

export function saveContactIntent(o: { name: string; phone: string; email?: string }): CardIntent {
  return { action: "insert_contact", extras: { name: o.name, phone: o.phone, ...(o.email ? { email: o.email } : {}) } };
}

export const shareIntent = (text: string): CardIntent => ({ action: "send", chooser: true, extras: { text } });

/** A "YYYY-MM-DDTHH:MM" local time that is a real date, else false. */
export function isLocalDateTime(s: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$/.exec(s);
  if (!m) return false;
  const [y, mo, d, h, mi] = [m[1], m[2], m[3], m[4] ?? "0", m[5] ?? "0"].map(Number);
  const t = new Date(Date.UTC(y, mo - 1, d, h, mi));
  return t.getUTCFullYear() === y && t.getUTCMonth() === mo - 1 && t.getUTCDate() === d && h < 24 && mi < 60;
}
