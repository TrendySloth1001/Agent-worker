/**
 * Approximate location (city / state / country) with no Android location permission and no API key.
 *
 * Signals, best first:
 *  1. "My city", typed by the user in the app (it travels with the request like the rest of the profile; nothing is stored here).
 *  2. Cloudflare's visitor-location headers (cf-ipcity, cf-region, cf-ipcountry, cf-timezone), present only after the owner turns on
 *     the "Add visitor location headers" managed transform. cf-iplatitude / cf-iplongitude are never read.
 *  3. An offline lookup of `cf-connecting-ip` in the DB-IP Lite city database (./ipdb.ts).
 *  4. Phone hints the app sends: SIM / network country, time zone id, locale (no permission needed).
 *
 * The result never claims more than the signals support: when they disagree (say the IP is in one country and the phone's network in
 * another: a VPN, roaming, a carrier hub) the city and state are dropped and only the country stays, with low confidence.
 *
 * Privacy: IPs, cities and coordinates are never stored or logged here, and nothing in this file touches the database. Callers log at most
 * `source` and `countryCode` (see [locationLog]).
 */
import { BlockList, isIP } from "node:net";
import type { Request } from "express";
import { z } from "zod";
import { clientIp } from "../util/rateLimit.js";
import { lookupIp } from "./ipdb.js";

export type GeoSource = "user" | "cloudflare" | "ip" | "phone";
export type GeoConfidence = "high" | "medium" | "low";
export type GeoLocation = {
  city?: string;
  region?: string;
  /** English country name; empty when unknown (a typed city with no country signal). */
  country: string;
  /** ISO 3166-1 alpha-2, upper case; empty when unknown. */
  countryCode: string;
  timezone?: string;
  confidence: GeoConfidence;
  source: GeoSource;
};

// ---- phone hints ------------------------------------------------------------------------------

const iso2 = z
  .string()
  .trim()
  .regex(/^[A-Za-z]{2}$/)
  .transform((s) => s.toUpperCase());
/** What the app sends under `locationHints`; every field is optional and bad ones are dropped, never an error. */
export const locationHintsSchema = z
  .object({
    simCountry: iso2.optional().catch(undefined),
    networkCountry: iso2.optional().catch(undefined),
    timeZone: z.string().trim().regex(/^[A-Za-z0-9_+\-/]{1,64}$/).optional().catch(undefined),
    locale: z.string().trim().regex(/^[A-Za-z0-9_-]{2,20}$/).optional().catch(undefined),
  })
  .catch({});
export type LocationHints = z.infer<typeof locationHintsSchema>;

// ---- addresses --------------------------------------------------------------------------------

const reserved = new BlockList();
for (const [net, bits] of [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10], // carrier-grade NAT
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["198.51.100.0", 24],
  ["203.0.113.0", 24],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
] as const) {
  reserved.addSubnet(net, bits, "ipv4");
}
for (const [net, bits] of [
  ["::", 128],
  ["::1", 128],
  ["fc00::", 7],
  ["fe80::", 10],
  ["ff00::", 8],
  ["2001:db8::", 32],
] as const) {
  reserved.addSubnet(net, bits, "ipv6");
}

/** True for anything that cannot be looked up: not an address, private, loopback, link-local, CGNAT, documentation, multicast. */
export function isPrivateIp(ip: string): boolean {
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(ip.trim());
  const addr = mapped ? mapped[1] : ip.trim();
  const v = isIP(addr);
  if (!v) return true;
  return reserved.check(addr, v === 4 ? "ipv4" : "ipv6");
}

// ---- reading the request ----------------------------------------------------------------------

type CfPlace = { city?: string; region?: string; countryCode?: string; timezone?: string };

/** Keeps a place name readable and harmless in a prompt: letters, marks, digits, spaces and a little punctuation. */
export function cleanPlace(raw: unknown, max = 60): string | undefined {
  if (typeof raw !== "string") return undefined;
  let s = raw;
  try {
    s = decodeURIComponent(s);
  } catch {
    // keep as is
  }
  const out = s.replace(/[^\p{L}\p{M}\p{N} .,'()\-]/gu, " ").replace(/\s+/g, " ").trim().slice(0, max).trim();
  return out.length >= 2 ? out : undefined;
}

const header = (req: Pick<Request, "headers">, name: string): string | undefined => {
  const v = req.headers?.[name];
  return typeof v === "string" && v.trim() ? v.trim() : undefined;
};

/** Cloudflare's visitor-location headers. XX (unknown) and T1 (Tor) are not countries. Latitude and longitude are not read. */
export function cloudflarePlace(req: Pick<Request, "headers">): CfPlace | null {
  const cc = header(req, "cf-ipcountry")?.toUpperCase();
  const countryCode = cc && /^[A-Z]{2}$/.test(cc) && cc !== "XX" && cc !== "T1" ? cc : undefined;
  const city = cleanPlace(header(req, "cf-ipcity"));
  const region = cleanPlace(header(req, "cf-region"));
  const tz = header(req, "cf-timezone");
  const timezone = tz && /^[A-Za-z0-9_+\-/]{1,64}$/.test(tz) ? tz : undefined;
  if (!countryCode && !city && !region) return null;
  return { city, region, countryCode, timezone };
}

// ---- combining --------------------------------------------------------------------------------

const names = (() => {
  try {
    return new Intl.DisplayNames(["en"], { type: "region" });
  } catch {
    return null;
  }
})();
export const countryName = (code: string): string => {
  try {
    const n = names?.of(code);
    return n && n !== code ? n : code;
  } catch {
    return code;
  }
};

export type Signals = {
  /** The user's typed city. */
  city?: string;
  /** Cloudflare headers, or the offline IP lookup when there are none. */
  network?: { place: CfPlace; via: "cloudflare" | "ip" } | null;
  hints?: LocationHints;
};

/**
 * One location from whatever signals exist, or null. Pure: no I/O.
 * City and state are only kept when the network place and the phone agree (or the phone says nothing);
 * the typed city is always kept.
 */
export function combine(s: Signals): GeoLocation | null {
  const hints = s.hints ?? {};
  const place = s.network?.place;
  const ipCountry = place?.countryCode?.toUpperCase();
  const net = hints.networkCountry;
  const sim = hints.simCountry;
  const countryCode = net ?? ipCountry ?? sim ?? "";
  const phoneSaysOther = (!!net && !!ipCountry && net !== ipCountry) || (!!sim && !!ipCountry && sim !== ipCountry);
  const timezone = hints.timeZone ?? place?.timezone;

  const supporters = [ipCountry, net, sim].filter((c) => c && c === countryCode).length;
  const countryConfidence: GeoConfidence = phoneSaysOther || !countryCode ? "low" : supporters >= 2 ? "high" : sim && !net && !ipCountry ? "low" : "medium";

  const typed = cleanPlace(s.city);
  if (typed) {
    // A typed city is the user's word. The state is only added when the network place is the same city.
    const sameCity = !phoneSaysOther && place?.city && place.city.toLowerCase() === typed.toLowerCase();
    return {
      city: typed,
      ...(sameCity && place?.region ? { region: place.region } : {}),
      country: countryCode && !phoneSaysOther ? countryName(countryCode) : "",
      countryCode: countryCode && !phoneSaysOther ? countryCode : "",
      ...(timezone ? { timezone } : {}),
      confidence: "high",
      source: "user",
    };
  }

  if (!countryCode && !place?.city) return null;
  const keepCity = !phoneSaysOther && !!ipCountry && !!(place?.city || place?.region);
  const networkSource: GeoSource = s.network?.via ?? "ip";
  const countryFromPhone = !!countryCode && countryCode !== ipCountry;
  return {
    ...(keepCity && place?.city ? { city: place.city } : {}),
    ...(keepCity && place?.region ? { region: place.region } : {}),
    country: countryCode ? countryName(countryCode) : "",
    countryCode,
    ...(timezone ? { timezone } : {}),
    // A city or state is a guess from an address range: never "high".
    confidence: keepCity && countryConfidence === "high" ? "medium" : countryConfidence,
    source: keepCity || (!countryFromPhone && ipCountry) ? networkSource : "phone",
  };
}

/** The user-set "My city" is honoured even when approximate location is off. */
export type ResolveOpts = { enabled: boolean; hints?: LocationHints; city?: string };

/** The location for this request. Looks at headers only; the IP is used for the lookup and then forgotten. */
export function resolveLocation(req: Pick<Request, "headers" | "ip" | "socket">, o: ResolveOpts): GeoLocation | null {
  if (!o.enabled) {
    const typed = cleanPlace(o.city);
    return typed ? { city: typed, country: "", countryCode: "", confidence: "high", source: "user" } : null;
  }
  let network: Signals["network"] = null;
  const cf = cloudflarePlace(req);
  if (cf) network = { place: cf, via: "cloudflare" };
  if (!network || (!network.place.city && !network.place.region)) {
    // No (useful) Cloudflare headers: look the address up offline, unless it is private or reserved.
    const ip = clientIp(req as Request);
    const found = ip !== "unknown" && !isPrivateIp(ip) ? lookupIp(ip) : null;
    if (found) network = { place: { ...found, countryCode: found.countryCode ?? network?.place.countryCode, timezone: network?.place.timezone }, via: "ip" };
  }
  return combine({ city: o.city, network, hints: o.hints });
}

/** What may go in a log line about a location: the source and the country, nothing else. */
export const locationLog = (loc: GeoLocation | null): { geoSource: GeoSource | "none"; geoCountry: string } => ({ geoSource: loc?.source ?? "none", geoCountry: loc?.countryCode ?? "" });

// ---- using it in a turn -----------------------------------------------------------------------

// Weather, local news, "near me", prices and currency, time, holidays and festivals, places, events, "here", "in my city".
const LOCATION_TURN_RE = new RegExp(
  [
    String.raw`\b(weather|forecast|temperature|humidity|rain(?:ing|fall)?|monsoon|air quality|aqi|sunrise|sunset)\b`,
    String.raw`\b(local|nearby|nearest|closest)\b`,
    String.raw`\bnear(?: ?(?:me|us|here|my))\b`,
    String.raw`\baround (?:me|here|us)\b`,
    String.raw`\b(?:in|at|from|around|near|over) here\b`,
    String.raw`\bwhere i am\b`,
    String.raw`\bmy (?:city|town|area|location|locality|neighbou?rhood|state|country|region|place)\b`,
    String.raw`\b(?:news|headlines)\b.*\b(?:today|local|city|state|country|here)\b`,
    String.raw`\b(?:price|prices|cost|rate|rates|fare|fares|petrol|diesel|gold|fuel|currency|exchange rate|rupees?|inr|dollars?|usd|euros?)\b`,
    String.raw`\bwhat(?:'s| is)? the time\b|\btime (?:now|here|zone)\b|\bwhat time is it\b`,
    String.raw`\b(?:holiday|holidays|festival|festivals|diwali|eid|holi|christmas|public holiday|long weekend)\b`,
    String.raw`\b(?:restaurants?|cafes?|caf[eé]s?|hospitals?|pharmac(?:y|ies)|atms?|banks?|shops?|stores?|malls?|gyms?|salons?|clinics?|petrol pump|supermarkets?|places? to (?:eat|visit|go)|things to do|open now|events?|concerts?|movies? (?:playing|showtimes?)|showtimes?)\b`,
    String.raw`\b(?:mausam|aas ?paas|mere paas|yahan|yaha)\b`,
  ].join("|"),
  "i",
);
// The subset where the user plainly means "close to me" (used for place look-ups).
const NEAR_ME_RE = /\b(?:near(?: ?(?:me|us|here|my\b))?|nearby|nearest|closest|around (?:me|here|us)|(?:in|at|around) here|my (?:city|town|area|locality|neighbou?rhood)|aas ?paas|mere paas)\b/i;

/** Whether this user text calls for the user's location. The line is added to the prompt only then. */
export const isLocationTurn = (text: string): boolean => LOCATION_TURN_RE.test(text.slice(0, 2000));
/** Whether the text asks for something close to the user (a place card is then looked up in their country first). */
export const isNearMe = (text: string): boolean => NEAR_ME_RE.test(text.slice(0, 2000));

const EURO = new Set("DE FR ES IT NL BE AT IE PT FI GR LU SK SI EE LV LT HR CY MT".split(" "));
const CURRENCY: Record<string, string> = {
  IN: "INR", US: "USD", GB: "GBP", CA: "CAD", AU: "AUD", NZ: "NZD", JP: "JPY", CN: "CNY", SG: "SGD", AE: "AED", SA: "SAR", PK: "PKR", BD: "BDT", LK: "LKR", NP: "NPR",
  ID: "IDR", MY: "MYR", TH: "THB", PH: "PHP", VN: "VND", KR: "KRW", BR: "BRL", MX: "MXN", ZA: "ZAR", NG: "NGN", KE: "KES", EG: "EGP", TR: "TRY", CH: "CHF", SE: "SEK",
  NO: "NOK", DK: "DKK", PL: "PLN", RU: "RUB",
};
const IMPERIAL = new Set(["US", "LR", "MM"]);

/** Default currency code for a country, or undefined when not known. */
export const currencyOf = (code: string): string | undefined => (EURO.has(code) ? "EUR" : CURRENCY[code]);

const HOW: Record<GeoSource, string> = { user: "set by the user", cloudflare: "from network", ip: "from network", phone: "from phone settings" };

/** The one context line for a location-relevant turn; null when there is nothing worth saying. */
export function locationLine(loc: GeoLocation | null): string | null {
  if (!loc) return null;
  const where = [loc.city, loc.region, loc.country].filter(Boolean).join(", ");
  if (!where) return null;
  const caveat =
    loc.source === "user"
      ? "set by the user as their city; use it for local questions"
      : `${HOW[loc.source]}${loc.confidence === "low" ? ", low confidence" : ""}; may be off, so don't state it as fact unless relevant; ask if precision matters`;
  const cur = loc.countryCode ? currencyOf(loc.countryCode) : undefined;
  const defaults = loc.countryCode
    ? ` Default to ${cur ? `${cur}, ` : ""}${IMPERIAL.has(loc.countryCode) ? "US customary" : "metric"} units unless the user says otherwise.`
    : "";
  return `User's approximate location: ${where} (${caveat}).${defaults}`;
}

/** Lower-case region code for search engines and Nominatim, or undefined. */
export const regionOf = (loc: GeoLocation | null): string | undefined => (loc?.countryCode ? loc.countryCode.toLowerCase() : undefined);
