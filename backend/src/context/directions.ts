/**
 * Directions and "places in <city>" turns, answered by the server instead of the model.
 *
 * "Directions to Lonavala", "Lonavala ka rasta", "how to reach Lonavala from Nalasopara" or just "Directions"
 * (the place comes from the chat so far) produce a Directions card straight away:
 *   Navigate      google.navigation:q=<destination>  (starts from the user's live location: no origin needed)
 *   Route in Maps https://www.google.com/maps/dir/?api=1&destination=..[&origin=..]&travelmode=driving
 *   Transit       the same link with travelmode=transit
 *   Share
 * Distance and time come from OSRM, only when a starting point is known (the user's, or their approximate city,
 * labelled as such). Nothing is guessed: without a route the card just has no numbers. Reading a map link needs no
 * device permission, so this does not depend on the client's `deviceActions`.
 */
import { lookupPlace, type PlaceInfo } from "./geocode.js";
import { drivingRoute, formatDistance, formatDuration, type LatLon, type RouteSummary } from "./route.js";
import { cardBlock, placeMatches, type Card, type CardAction } from "./cards.js";
import { clip, mapsDirUrl, mapsSearchUrl, navigateIntent, sanitizeIntent, shareIntent } from "./cardLinks.js";

export type DirectionsAsk = {
  destination: string;
  /** A starting point the user named. */
  origin?: string;
  /** The place came from earlier messages ("Directions" alone). */
  fromHistory: boolean;
  /** Nothing but directions was asked: the server answers with no model call. */
  pure: boolean;
};

// ---- parsing -----------------------------------------------------------------

const BAD_PLACE = /^(?:there|here|it|that|this|me|my|home|current location|my location|my current location|where i am|you|use|the way|goals?|targets?|customers?|users?|people|audience|success|them|him|her|a|an|the|one|some|something|somewhere|anywhere|directions?|route|rasta)$/i;
const STOP = /\s+(?:from|with|and|also|plus|please|pls|plz|by|via|using|today|tomorrow|tonight|now|which|that|if|so|what|how|ka|ki|ke|se|me|mein|kaise|wala|bhi|batao|bata|dikhao)\b.*$/i;
const LEAD = /^(?:(?:the|a|an|go(?:ing)?|travel(?:l?ing)?|visit(?:ing)?|to|for|till|tak|get|me|us|show|give|find|need|want|please|pls|plz|and|also|hotels? and)\b|\W)+\s*/i;

/** A place name from the loose text after "directions to": at most five words, no filler. */
export function cleanDestination(raw: string): string | null {
  let s = raw.replace(/[?!.,;:()"“”]+/g, " ").replace(/\s+/g, " ").trim();
  s = s.replace(LEAD, "").replace(STOP, "").trim();
  s = s.replace(/\s+(?:ka|ki|ke|the|of|for|to)$/i, "").trim();
  if (s.length < 2 || BAD_PLACE.test(s)) return null;
  if (s.split(" ").length > 5 || !/\p{L}/u.test(s)) return null;
  return s;
}

const ORIGIN_RE = /\bfrom\s+(.+)$/i;

/** Splits "<dest> from <origin>" (either may be missing). */
function splitFrom(rest: string): { destination: string | null; origin: string | null } {
  const m = ORIGIN_RE.exec(rest);
  const destPart = m ? rest.slice(0, m.index) : rest;
  return { destination: cleanDestination(destPart), origin: m ? cleanDestination(m[1]) : null };
}

const WORD = String.raw`(?:directions?|route|routes|rasta|raasta|navigate|navigation|way)`;
const RE_FROM_TO = new RegExp(String.raw`\b${WORD}\s+from\s+(.+?)\s+(?:to|till|tak)\s+(.+)$`, "i");
const RE_WORD_TO = new RegExp(String.raw`\b${WORD}\s+(?:to|till|tak)\s+(.+)$`, "i");
const RE_NAV = /\bnavigate\s+(?:me\s+)?(?:to\s+)?(.+)$/i;
const RE_HOW = /\bhow\s+(?:do\s+i\s+|to\s+|can\s+i\s+|should\s+i\s+|would\s+i\s+|could\s+i\s+)?(?:reach|get\s+to|get\s+there|go\s+to|drive\s+to|travel\s+to)\s*(.*)$/i;
const RE_HINDI_SE = /(.+?)\s+se\s+(.+?)\s+(?:ka|ke|ki)\s+(?:rasta|raasta|route)\b/i;
const RE_HINDI_KAISE = /(.+?)\s+(?:kaise|kese|kaisey)\s+(?:jaye|jaaye|jayein|jaen|jau|jaun|jana|pahunche|pahuche|pahunchu|pahunchen|pahunchna|pohoche|pohchu)\b/i;
const RE_PREFIX = new RegExp(String.raw`^(.{2,40}?)\s+(?:ka\s+|ke\s+|ki\s+)?${WORD}\b`, "i");
const RE_BARE = /^\s*(?:(?:get|show|give)\s+(?:me\s+)?)?(?:the\s+)?(?:directions?|route|rasta|raasta|navigate|navigation|how\s+to\s+reach|how\s+do\s+i\s+get\s+there|map|maps)\s*[.!?]*\s*$/i;

/** Words that make a message more than a plain route request (the model answers too, the card is added). */
const EXTRA_RE = /\b(hotels?|resorts?|restaurants?|caf[eé]s?|stay|stays|homestays?|contact|phone|number|weather|price|prices|cost|budget|itinerary|things to do|places to|best time|plan|packing|safe|distance|tickets?|fare)\b/i;
/** Messages that merely answer an earlier "where are you starting from?". */
const STARTING_Q = /(?:starting|start) (?:from|point|location)|where are you (?:starting|coming|travel+ing|leaving)|from where|which city are you (?:in|leaving)/i;

const PLAIN_ANSWER_RE = /^\s*(?:from\s+)?([\p{L}][\p{L} .'-]{1,38})\s*[.!?]?\s*$/u;

/** The destination of the last few earlier user messages that talk about a trip or directions. */
export function destinationFromHistory(history: string[]): string | null {
  for (const h of history.slice(0, 6)) {
    const direct = parseDirections(h, [], undefined, true);
    if (direct?.destination) return direct.destination;
    const trip = /\b(?:go(?:ing)?|travel(?:l?ing)?|trip|visit(?:ing)?|plan(?:ning)?|head(?:ing)?|drive|driving|ride|riding|jaa?na|jaa?ne)\s+(?:to|for)\s+(.+)$/i.exec(h);
    if (trip) {
      const d = cleanDestination(trip[1].replace(/\b(?:any idea|do you know|where|can you|could you|and)\b.*$/i, ""));
      if (d) return d;
    }
  }
  return null;
}

/**
 * The route request in [text], or null. [history] holds the earlier user messages, newest first (the place of a bare
 * "Directions"); [prevAssistant] is the last answer (a bare place after "where are you starting from?" is the origin).
 * [strict] skips the history and the bare forms (used when scanning history itself).
 */
export function parseDirections(text: string, history: string[], prevAssistant?: string, strict = false): DirectionsAsk | null {
  const t = text.trim().slice(0, 400);
  if (!t) return null;
  const pure = !EXTRA_RE.test(t);
  const found = (destination: string | null, origin: string | null | undefined): DirectionsAsk | null =>
    destination ? { destination, ...(origin ? { origin } : {}), fromHistory: false, pure } : null;
  let m: RegExpExecArray | null;
  if ((m = RE_FROM_TO.exec(t))) return found(cleanDestination(m[2]), cleanDestination(m[1]));
  if ((m = RE_HINDI_SE.exec(t))) return found(cleanDestination(m[2]), cleanDestination(m[1]));
  if ((m = RE_WORD_TO.exec(t))) {
    const r = splitFrom(m[1]);
    const hit = found(r.destination, r.origin);
    if (hit) return hit;
  }
  if ((m = RE_HOW.exec(t)) && m[1].trim()) {
    const r = splitFrom(m[1]);
    const hit = found(r.destination, r.origin);
    if (hit) return hit;
  }
  if ((m = RE_NAV.exec(t)) && !/^(?:to\s*)?$/i.test(m[1])) {
    const r = splitFrom(m[1]);
    const hit = found(r.destination, r.origin);
    if (hit) return hit;
  }
  if ((m = RE_HINDI_KAISE.exec(t))) {
    const parts = m[1].split(/\s+se\s+/i);
    return found(cleanDestination(parts[parts.length - 1]), parts.length > 1 ? cleanDestination(parts[0]) : null);
  }
  if (strict) {
    if ((m = RE_PREFIX.exec(t))) return found(cleanDestination(m[1]), null);
    return null;
  }
  if (RE_BARE.test(t) || /^\s*how\s+(?:to\s+|do\s+i\s+)?(?:reach|get\s+there)\s*[.!?]*\s*$/i.test(t)) {
    const dest = destinationFromHistory(history);
    return dest ? { destination: dest, fromHistory: true, pure: true } : null;
  }
  if ((m = RE_PREFIX.exec(t))) {
    const dest = cleanDestination(m[1].replace(/^(?:show|give|get|find)\s+(?:me\s+)?/i, ""));
    if (dest && !/\b(?:how|what|where|when|why|who|is|are|can|could|do|does)\b/i.test(dest)) return { destination: dest, fromHistory: false, pure };
  }
  // "Nalasopara" (or "from Nalasopara") right after the assistant asked where the trip starts.
  if (prevAssistant && STARTING_Q.test(prevAssistant) && (m = PLAIN_ANSWER_RE.exec(t))) {
    const origin = cleanDestination(m[1]);
    const dest = destinationFromHistory(history);
    if (origin && dest) return { destination: dest, origin, fromHistory: true, pure: true };
  }
  return null;
}

// ---- places lists ------------------------------------------------------------

const CATEGORY_RE = /\b(hotels?|resorts?|restaurants?|caf[eé]s?|homestays?|hostels?|guest ?houses?|hospitals?|clinics?|pharmac(?:y|ies)|atms?|banks?|petrol pumps?|temples?|malls?|gyms?|salons?)\b/i;
const IN_RE = /\b(?:in|near|around|at|close to)\s+([\p{L}][\p{L} .'-]{1,30}?)(?=\s*(?:[.,?!]|$|\bwith\b|\band\b|\bplease\b))/iu;

/** "hotels in Lonavala": the Maps search for a "find hotels/restaurants/... in <place>" request, or null. */
export function placesQuery(text: string, destination?: string): string | null {
  const cat = CATEGORY_RE.exec(text);
  if (!cat) return null;
  if (!/\b(find|show|suggest|list|recommend|best|top|any|good|where|search|nearby|near)\b|\bin\b|\bhotels? (?:and|&)\b/i.test(text)) return null;
  const inPlace = IN_RE.exec(text);
  const place = inPlace ? cleanDestination(inPlace[1]) : destination ?? null;
  const category = cat[1].toLowerCase();
  return place ? clip(`${category} in ${place}`, 80) : null;
}

// ---- prompt rules ------------------------------------------------------------

/** The rule for turns about a route (the card is added by the app) and/or a list of places. */
export function routeNote(o: { directions: boolean; places: string | null }): string {
  const lines: string[] = ["Maps and contact details:"];
  if (o.directions) {
    lines.push(
      "- The app adds a Directions card (Navigate, Route in Maps, Transit) to this reply. Do not write directions, turn-by-turn steps, roads, train or bus interchanges, distances or travel times from memory; at most one sentence pointing to the card.",
      "- Never ask where the user is starting from: Maps starts from their current location. Ask at most once, and only if they want a route from a specific other place without naming it.",
    );
  }
  if (o.places) {
    lines.push(
      `- For hotels, restaurants and other places: name at most 3, each as its own \`\`\`sparky-card block {"type":"place","name":"...","query":"<name>, <area>, <city>"} after one short sentence. The app looks up the address and a phone number if OpenStreetMap has one and adds a Maps search for "${o.places}". Do not write a table or list of them.`,
    );
  }
  lines.push(
    "- Never write phone numbers, e-mail addresses, street addresses, links or prices from memory; only ones in the sources or in the user's messages. Otherwise say to check Maps or the official site.",
    "- Keep it short, no emoji, no emoji in headings.",
  );
  return lines.join("\n");
}

// ---- the card ----------------------------------------------------------------

const titleCase = (s: string) => s.replace(/\b\p{L}/gu, (c) => c.toUpperCase());

export type BuildDeps = {
  lookup?: typeof lookupPlace;
  route?: typeof drivingRoute;
  signal?: AbortSignal;
  /** Country (ISO alpha-2) to look places up in first. */
  countryCode?: string;
  /** The user's approximate city (and state), used as the starting point when they named none. */
  approx?: { city: string; region?: string } | null;
};

export type DirectionsResult = { text: string; card: Card };

async function find(q: string, d: BuildDeps): Promise<PlaceInfo | null> {
  const lookup = d.lookup ?? lookupPlace;
  const stop = AbortSignal.timeout(6_000);
  return lookup(q, { countryCode: d.countryCode, signal: d.signal ? AbortSignal.any([d.signal, stop]) : stop }).catch(() => null);
}

const point = (p: PlaceInfo | null): LatLon | null => (p ? { lat: p.lat, lon: p.lon } : null);
const coords = (p: LatLon) => `${p.lat},${p.lon}`;

/** The Directions card and its one or two sentences. Never throws; numbers only from OSRM. */
export async function buildDirections(ask: DirectionsAsk, d: BuildDeps = {}): Promise<DirectionsResult | null> {
  const typed = titleCase(clip(ask.destination, 80));
  const [destInfoRaw, originInfo] = await Promise.all([
    find(ask.destination, d),
    ask.origin ? find(ask.origin, d) : d.approx ? find([d.approx.city, d.approx.region].filter(Boolean).join(", "), d) : Promise.resolve(null),
  ]);
  const destInfo = destInfoRaw && placeMatches(ask.destination, destInfoRaw) ? destInfoRaw : null;
  const destName = destInfo ? destInfo.name : typed;
  const dest = destInfo ? coords(destInfo) : typed;
  const userOrigin = ask.origin ? titleCase(clip(ask.origin, 80)) : undefined;
  const originPoint = point(originInfo);
  const originLabel = userOrigin ?? (d.approx && originPoint ? `${d.approx.city} (approx.)` : undefined);
  const originForMaps = userOrigin ? (originInfo ? coords(originInfo) : userOrigin) : undefined;

  let summary: RouteSummary | null = null;
  const destPoint = point(destInfo);
  if (originPoint && destPoint && originLabel) summary = await (d.route ?? drivingRoute)(originPoint, destPoint, { signal: d.signal }).catch(() => null);

  const text = summary && originLabel
    ? `${destName} is about ${formatDistance(summary.meters)} from ${originLabel}, roughly ${formatDuration(summary.seconds)} by road without traffic. Tap Navigate for live traffic and directions.`
    : `Tap Navigate for live directions to ${destName} from where you are, or Transit for trains and buses.`;

  const share = [destName, destInfo?.address, mapsDirUrl({ destination: dest })].filter(Boolean).join("\n");
  const actions: CardAction[] = [
    { id: "navigate", label: "Navigate", app: "maps", primary: true, intent: navigateIntent(dest) },
    { id: "route", label: "Route in Maps", app: "maps", intent: { action: "view", uri: mapsDirUrl({ destination: dest, origin: originForMaps, mode: "driving" }) } },
    { id: "transit", label: "Transit", app: "maps", intent: { action: "view", uri: mapsDirUrl({ destination: dest, origin: originForMaps, mode: "transit" }) } },
    { id: "share", label: "Share", app: "share", intent: shareIntent(share) },
  ];
  const safe = actions.flatMap((a) => {
    const intent = sanitizeIntent(a.intent);
    return intent ? [{ ...a, intent }] : [];
  });
  const rows: Array<{ k: string; v: string }> = [];
  if (originLabel) rows.push({ k: "From", v: originLabel });
  if (summary) {
    rows.push({ k: "Distance", v: formatDistance(summary.meters) });
    rows.push({ k: "Drive", v: formatDuration(summary.seconds) });
  }
  const card: Card = { v: 1, type: "place", title: destName, ...(destInfo?.address ? { subtitle: destInfo.address } : {}), ...(rows.length ? { rows } : {}), actions: safe };
  return safe.length ? { text, card } : null;
}

/** A "<hotels in Lonavala>" Maps search card (no place data, nothing looked up). */
export function placesSearchCard(query: string): Card | null {
  const actions: CardAction[] = [
    { id: "search", label: "Search in Maps", app: "maps", primary: true, intent: { action: "view", uri: mapsSearchUrl(query) } },
    { id: "share", label: "Share", app: "share", intent: shareIntent(`${query}\n${mapsSearchUrl(query)}`) },
  ];
  const safe = actions.flatMap((a) => {
    const intent = sanitizeIntent(a.intent);
    return intent ? [{ ...a, intent }] : [];
  });
  return safe.length ? { v: 1, type: "place", title: titleCase(query), subtitle: "Search on Google Maps", actions: safe } : null;
}

export const directionsBlock = (r: DirectionsResult): string => `${r.text}\n\n${cardBlock(r.card)}`;
