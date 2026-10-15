/**
 * Place lookup for the Place card: OpenStreetMap Nominatim (no key).
 *
 * Usage policy (operations.osmfoundation.org/policies/nominatim): at most one
 * request per second, a User-Agent that names the app and a contact, and
 * cached results. So every live request waits its turn in one queue
 * (>= 1.1 s apart), answers are cached for 30 days (misses for a day, in
 * memory and in web_cache), and nothing here ever throws. With
 * `extratags=1` Nominatim returns opening_hours and phone when OSM has them,
 * so no Overpass call is needed.
 */
import { TtlLru } from "../web/lru.js";
import { normalizeQuery, readPersistedValue, writePersisted } from "../web/cacheStore.js";
import { clip, normalizePhone } from "./cardLinks.js";

export type PlaceInfo = {
  name: string;
  address: string;
  lat: number;
  lon: number;
  hours?: string;
  phone?: string;
};

/** Sent with every request; override the contact with NOMINATIM_CONTACT (a URL or e-mail). */
export const userAgent = (): string => `sparky-chat/1.0 (${process.env.NOMINATIM_CONTACT?.trim() || "https://sparky.cloudnsofts.com"})`;

export const searchUrl = (query: string) => `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=jsonv2&limit=1&addressdetails=1&extratags=1&accept-language=en`;

type Row = {
  lat?: string;
  lon?: string;
  name?: string;
  display_name?: string;
  address?: Record<string, string>;
  extratags?: Record<string, string>;
};

/** "Mo-Fr 09:00-18:00; Sa 10:00-14:00" as "Mo-Fr 09:00-18:00 · Sa 10:00-14:00". */
export const humanHours = (raw: string): string => clip(raw.replace(/\s*;\s*/g, " · "), 160);

/** The address line: street, area, city, postcode (the name itself left out). */
function addressOf(r: Row): string {
  const a = r.address ?? {};
  const street = [a.house_number, a.road].filter(Boolean).join(" ");
  const area = a.suburb ?? a.neighbourhood ?? a.quarter ?? a.village;
  const city = a.city ?? a.town ?? a.municipality ?? a.county ?? a.state_district;
  const parts = [street, area, city, a.state, a.postcode].filter((p): p is string => !!p);
  const line = parts.join(", ");
  if (line) return clip(line, 200);
  return clip((r.display_name ?? "").split(",").slice(1, 5).join(","), 200);
}

/** The first Nominatim result as a place, or null when the response holds none. */
export function mapNominatim(json: unknown): PlaceInfo | null {
  const row = Array.isArray(json) ? (json[0] as Row | undefined) : undefined;
  if (!row || typeof row !== "object") return null;
  const lat = Number(row.lat);
  const lon = Number(row.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  const name = clip(row.name || (row.display_name ?? "").split(",")[0], 120);
  if (!name) return null;
  const x = row.extratags ?? {};
  const hours = x.opening_hours ? humanHours(x.opening_hours) : "";
  const phone = normalizePhone(x.phone ?? x["contact:phone"] ?? "") ?? undefined;
  return { name, address: addressOf(row), lat: Math.round(lat * 1e6) / 1e6, lon: Math.round(lon * 1e6) / 1e6, ...(hours ? { hours } : {}), ...(phone ? { phone } : {}) };
}

/** Fetches Nominatim JSON; injectable for tests. */
export type GeoFetch = (url: string, headers: Record<string, string>, signal?: AbortSignal) => Promise<unknown>;

const defaultFetch: GeoFetch = async (url, headers, signal) => {
  const ctl = AbortSignal.timeout(4_000);
  const r = await fetch(url, { signal: signal ? AbortSignal.any([signal, ctl]) : ctl, headers });
  if (!r.ok) throw new Error(`nominatim ${r.status}`);
  return r.json();
};

// ---- the one-request-per-second queue ---------------------------------------

export const MIN_GAP_MS = 1_100;
let chain: Promise<unknown> = Promise.resolve();
let lastAt = 0;

/** Runs [fn] after every earlier call, at least [MIN_GAP_MS] after the previous one started. */
export function paced<T>(fn: () => Promise<T>, o: { now?: () => number; sleep?: (ms: number) => Promise<void> } = {}): Promise<T> {
  const now = o.now ?? Date.now;
  const sleep = o.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const run = async () => {
    const wait = lastAt + MIN_GAP_MS - now();
    if (wait > 0) await sleep(wait);
    lastAt = now();
    return fn();
  };
  const next = chain.then(run, run);
  chain = next.catch(() => undefined);
  return next;
}

// ---- cache ------------------------------------------------------------------

const HIT_TTL = 30 * 24 * 3_600_000;
const MISS_TTL = 24 * 3_600_000;
const mem = new TtlLru<PlaceInfo | null>(500);
const isStored = (v: unknown): v is { place: PlaceInfo | null } => !!v && typeof v === "object" && "place" in (v as object);

/** Cache identity of a query. */
export const placeKey = (query: string) => `nominatim|${normalizeQuery(query).slice(0, 200)}`;

/**
 * The place for [query]: cache first, else one paced live request. Null when
 * unknown or when the request fails (a failure is not cached).
 */
export async function lookupPlace(query: string, o: { fetch?: GeoFetch; signal?: AbortSignal; shared?: boolean; sleep?: (ms: number) => Promise<void>; now?: () => number } = {}): Promise<PlaceInfo | null> {
  const q = clip(query, 200);
  if (q.length < 2) return null;
  const key = placeKey(q);
  const shared = o.shared ?? !o.fetch;
  if (shared) {
    const hit = mem.get(key);
    if (hit !== undefined) return hit;
    const stored = await readPersistedValue(key, isStored);
    if (stored) {
      mem.set(key, stored.place, stored.place ? HIT_TTL : MISS_TTL);
      return stored.place;
    }
  }
  try {
    const json = await paced(() => (o.fetch ?? defaultFetch)(searchUrl(q), { "User-Agent": userAgent(), Accept: "application/json" }, o.signal), { sleep: o.sleep, now: o.now });
    const place = mapNominatim(json);
    if (shared) {
      mem.set(key, place, place ? HIT_TTL : MISS_TTL);
      writePersisted(key, { place }, place ? HIT_TTL : MISS_TTL);
    }
    return place;
  } catch {
    return null;
  }
}

/** Test hook. */
export function resetGeocode() {
  mem.clear();
  chain = Promise.resolve();
  lastAt = 0;
}
