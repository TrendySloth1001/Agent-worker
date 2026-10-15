/**
 * Offline IP-to-city lookup: DB-IP "IP to City Lite" (CC BY 4.0, no key), an MMDB file read with the
 * `maxmind` package. The file is never in git: it is downloaded at start into a writable folder when
 * it is missing or older than [MAX_AGE_DAYS], and re-checked daily, so it is refreshed about monthly.
 * Every failure is quiet (the lookup just returns null); the app works without the file.
 *
 * Attribution (required by the licence): "IP geolocation by DB-IP" (https://db-ip.com), shown on the
 * privacy page and in the app's credits.
 */
import { createWriteStream } from "node:fs";
import { mkdir, rename, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { createGunzip } from "node:zlib";
import maxmind, { type CityResponse } from "maxmind";
import { log } from "../util/logger.js";

export const MAX_AGE_DAYS = 35;
const DAY_MS = 24 * 3_600_000;
const DOWNLOAD_TIMEOUT_MS = 10 * 60_000;

/** The slice of a DB-IP city record that is used. Coordinates are deliberately not read. */
export type IpPlace = { city?: string; region?: string; countryCode?: string };
/** What a reader must offer (the maxmind Reader satisfies it; tests pass a stub). */
export type CityReader = {
  get(ip: string): { city?: { names?: { en?: string } }; subdivisions?: Array<{ names?: { en?: string } }>; country?: { iso_code?: string } } | null;
};

let reader: CityReader | null = null;
let updating: Promise<void> | null = null;
let timer: NodeJS.Timeout | null = null;

export const geoDir = (): string => process.env.GEOIP_DIR?.trim() || join(tmpdir(), "sparky-geoip");
export const geoFile = (): string => join(geoDir(), "dbip-city-lite.mmdb");
export const geoDisabled = (): boolean => /^(1|true|yes)$/i.test(process.env.GEOIP_DISABLED ?? "");

/** DB-IP's monthly download URL: https://download.db-ip.com/free/dbip-city-lite-YYYY-MM.mmdb.gz */
export const dbUrl = (d: Date): string => `https://download.db-ip.com/free/dbip-city-lite-${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}.mmdb.gz`;
/** This month's file, then the previous month's (a new month's file appears a day or so late). */
export function candidateUrls(now = new Date()): string[] {
  const prev = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  return [dbUrl(now), dbUrl(prev)];
}

/** Test hook: use [r] as the reader (null clears it). */
export function setCityReader(r: CityReader | null) {
  reader = r;
}

/** The place for a public [ip], or null (no database, unknown address, any error). */
export function lookupIp(ip: string): IpPlace | null {
  if (!reader) return null;
  try {
    const r = reader.get(ip);
    if (!r) return null;
    const city = r.city?.names?.en;
    const region = r.subdivisions?.[0]?.names?.en;
    const countryCode = r.country?.iso_code?.toUpperCase();
    if (!city && !region && !countryCode) return null;
    return { ...(city ? { city } : {}), ...(region ? { region } : {}), ...(countryCode ? { countryCode } : {}) };
  } catch {
    return null;
  }
}

export const geoDbReady = (): boolean => reader !== null;

const openFile = (path: string) => maxmind.open<CityResponse>(path);

async function ageDays(path: string): Promise<number | null> {
  try {
    return (Date.now() - (await stat(path)).mtimeMs) / DAY_MS;
  } catch {
    return null;
  }
}

/** Downloads one gzip'd MMDB to [dest] through a temp file, validated before it replaces the old one. */
async function download(url: string, dest: string, fetcher: typeof fetch): Promise<boolean> {
  const res = await fetcher(url, { signal: AbortSignal.timeout(DOWNLOAD_TIMEOUT_MS), headers: { "User-Agent": "sparky-geoip/1.0" } });
  if (!res.ok || !res.body) return false;
  const tmp = `${dest}.${process.pid}.tmp`;
  try {
    await pipeline(Readable.fromWeb(res.body as never), createGunzip(), createWriteStream(tmp));
    const fresh = await openFile(tmp); // throws on a corrupt file: the old one stays
    await rename(tmp, dest);
    reader = fresh;
    return true;
  } finally {
    await rm(tmp, { force: true }).catch(() => undefined);
  }
}

/**
 * Loads the file on disk, and downloads a fresh one when it is missing or older than [MAX_AGE_DAYS].
 * Never throws; one run at a time.
 */
export function refreshGeoDb(o: { fetch?: typeof fetch; now?: Date } = {}): Promise<void> {
  if (geoDisabled()) return Promise.resolve();
  if (updating) return updating;
  updating = (async () => {
    const file = geoFile();
    const age = await ageDays(file);
    if (age !== null && !reader) reader = await openFile(file).catch(() => null);
    if (age !== null && age <= MAX_AGE_DAYS && reader) return;
    try {
      await mkdir(geoDir(), { recursive: true });
      for (const url of candidateUrls(o.now)) {
        if (await download(url, file, o.fetch ?? fetch).catch(() => false)) {
          log.info("geoip database updated");
          return;
        }
      }
    } catch {
      // offline, read-only disk...: quiet; IP lookup stays off (or keeps the old file)
    }
  })().finally(() => {
    updating = null;
  });
  return updating;
}

/** Called once at server start: loads or fetches the database in the background, then re-checks daily. */
export function startGeoDb(): void {
  if (geoDisabled() || timer) return;
  void refreshGeoDb();
  timer = setInterval(() => void refreshGeoDb(), DAY_MS);
  timer.unref();
}
