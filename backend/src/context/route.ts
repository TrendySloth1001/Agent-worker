/**
 * Distance and time between two points: the free public OSRM demo router (no key).
 *
 * Demo-server etiquette (github.com/Project-OSRM/osrm-backend/wiki/Demo-server): light use only, at most one
 * request per second, an identifying User-Agent. So requests share one queue (>= 1.1 s apart), answers are
 * cached for a week (coordinates rounded to ~1 km), the timeout is 4 s, and nothing here throws: on any failure
 * the caller gets null and shows no numbers.
 */
import { TtlLru } from "../web/lru.js";
import { userAgent } from "./geocode.js";

export type LatLon = { lat: number; lon: number };
export type RouteSummary = { meters: number; seconds: number };

export const osrmUrl = (a: LatLon, b: LatLon): string => `https://router.project-osrm.org/route/v1/driving/${a.lon},${a.lat};${b.lon},${b.lat}?overview=false`;

/** The first route of an OSRM response, or null. */
export function mapOsrm(json: unknown): RouteSummary | null {
  const j = json as { code?: string; routes?: Array<{ distance?: number; duration?: number }> } | null;
  if (!j || j.code !== "Ok" || !Array.isArray(j.routes)) return null;
  const r = j.routes[0];
  if (!r || !Number.isFinite(r.distance) || !Number.isFinite(r.duration) || (r.distance as number) < 0 || (r.duration as number) < 0) return null;
  return { meters: Math.round(r.distance as number), seconds: Math.round(r.duration as number) };
}

/** "105 km" (whole km from 100, one decimal below, "850 m" under 1 km). */
export function formatDistance(meters: number): string {
  if (meters < 1000) return `${Math.max(10, Math.round(meters / 10) * 10)} m`;
  const km = meters / 1000;
  return km >= 100 ? `${Math.round(km)} km` : `${Math.round(km * 10) / 10} km`;
}

/** "45 min", "1 h 20 min", "2.5 h" (from 2 h, to the nearest half hour). */
export function formatDuration(seconds: number): string {
  const min = Math.max(1, Math.round(seconds / 60));
  if (min < 60) return `${min} min`;
  if (min >= 120) return `${Math.round(min / 30) / 2} h`;
  const m5 = Math.round(min / 5) * 5;
  const h = Math.floor(m5 / 60);
  const mm = m5 % 60;
  return `${h} h${mm ? ` ${mm} min` : ""}`;
}

export type RouteFetch = (url: string, headers: Record<string, string>, signal?: AbortSignal) => Promise<unknown>;

const defaultFetch: RouteFetch = async (url, headers, signal) => {
  const ctl = AbortSignal.timeout(4_000);
  const r = await fetch(url, { signal: signal ? AbortSignal.any([signal, ctl]) : ctl, headers });
  if (!r.ok) throw new Error(`osrm ${r.status}`);
  return r.json();
};

export const ROUTE_GAP_MS = 1_100;
let chain: Promise<unknown> = Promise.resolve();
let lastAt = 0;

function paced<T>(fn: () => Promise<T>, now: () => number, sleep: (ms: number) => Promise<void>): Promise<T> {
  const run = async () => {
    const wait = lastAt + ROUTE_GAP_MS - now();
    if (wait > 0) await sleep(wait);
    lastAt = now();
    return fn();
  };
  const next = chain.then(run, run);
  chain = next.catch(() => undefined);
  return next;
}

const TTL = 7 * 24 * 3_600_000;
const mem = new TtlLru<RouteSummary>(300);
const r2 = (n: number) => (Math.round(n * 100) / 100).toFixed(2);
export const routeKey = (a: LatLon, b: LatLon) => `${r2(a.lat)},${r2(a.lon)}>${r2(b.lat)},${r2(b.lon)}`;

export type RouteOpts = { fetch?: RouteFetch; signal?: AbortSignal; now?: () => number; sleep?: (ms: number) => Promise<void> };

/** Driving distance and time from [a] to [b]; null when unknown or the router is unavailable (never guessed). */
export async function drivingRoute(a: LatLon, b: LatLon, o: RouteOpts = {}): Promise<RouteSummary | null> {
  const key = routeKey(a, b);
  const shared = !o.fetch;
  if (shared) {
    const hit = mem.get(key);
    if (hit) return hit;
  }
  try {
    const json = await paced(
      () => (o.fetch ?? defaultFetch)(osrmUrl(a, b), { "User-Agent": userAgent(), Accept: "application/json" }, o.signal),
      o.now ?? Date.now,
      o.sleep ?? ((ms) => new Promise<void>((r) => setTimeout(r, ms))),
    );
    const route = mapOsrm(json);
    if (route && shared) mem.set(key, route, TTL);
    return route;
  } catch {
    return null;
  }
}

/** Test hook. */
export function resetRoute() {
  mem.clear();
  chain = Promise.resolve();
  lastAt = 0;
}
