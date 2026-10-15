/**
 * "Playlist" rich card: several songs suggested in one answer.
 *
 * The model writes a compact ```sparky-playlist block (music turns only):
 *   title: Rainy day Hindi
 *   app: spotify            (only when the user named an app)
 *   - Tum Hi Ho | Arijit Singh
 * Weak models write a plain numbered "Song - Artist" list instead; the
 * post-pass `convertSongList` turns it into the same block.
 *
 * The card then asks POST /playlist/enrich for covers, durations and 30 s
 * previews (iTunes Search API, no key) and POST /playlist/youtube for video ids
 * (keyless web search scoped to youtube.com) behind "Play all"
 * (youtube.com/watch_videos?video_ids=...). Everything is cached in
 * memory and in web_cache; lookups are capped, lightly paced and never throw.
 */
import { TtlLru } from "../web/lru.js";
import { normalizeQuery, readPersistedValue, writePersisted } from "../web/cacheStore.js";
import { youtubeId } from "./linkMeta.js";

export const PLAYLIST_FENCE = "sparky-playlist";
/** Songs per card (and lookups per playlist). */
export const MAX_TRACKS = 12;

export type Song = { title: string; artist: string };
export type PlaylistSpec = { title: string; app?: string; items: Song[] };

const clip = (s: string, n: number) => s.replace(/\s+/g, " ").trim().slice(0, n);

// ---- the block --------------------------------------------------------------

/** The items of a ```sparky-playlist body (null when it holds no song). */
export function parsePlaylistBlock(source: string): PlaylistSpec | null {
  let title = "";
  let app: string | undefined;
  const items: Song[] = [];
  for (const raw of source.split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    const head = /^(title|app):\s*(.*)$/i.exec(line);
    if (head) {
      if (head[1].toLowerCase() === "title") title = clip(head[2], 80);
      else app = clip(head[2], 30).toLowerCase().replace(/\s+/g, "_") || undefined;
      continue;
    }
    const m = /^(?:[-*•]|\d{1,2}[.)])?\s*(.+?)\s*\|\s*(.*)$/.exec(line);
    if (!m) continue;
    const song = { title: clip(m[1], 90), artist: clip(m[2], 70) };
    if (song.title) items.push(song);
    if (items.length >= MAX_TRACKS) break;
  }
  return items.length ? { title: title || "Playlist", ...(app ? { app } : {}), items } : null;
}

/** A song cell never holds the block's own separators or fence. */
const cell = (s: string) => s.replace(/[|\n`]/g, " ").replace(/\s+/g, " ").trim();

/** The fenced block for [spec]. */
export function playlistBlock(spec: PlaylistSpec): string {
  const lines = [`title: ${cell(spec.title)}`, ...(spec.app ? [`app: ${spec.app}`] : []), ...spec.items.slice(0, MAX_TRACKS).map((s) => `- ${cell(s.title)} | ${cell(s.artist)}`)];
  return `\`\`\`${PLAYLIST_FENCE}\n${lines.join("\n")}\n\`\`\``;
}

export const hasPlaylistBlock = (text: string) => text.includes("```" + PLAYLIST_FENCE);

// ---- music turns ------------------------------------------------------------

const MUSIC_RE = /\b(songs?|playlist|tracks?|music|gaan[ae]|gane|gana|tunes?|albums?|lofi|lo-fi|bollywood|punjabi|hip-?hop|soundtrack|setlist|mixtape|singers?)\b/i;

/** Whether the user's text is about music (the playlist rule and the list conversion apply). */
export const isMusicTurn = (userText: string): boolean => MUSIC_RE.test(userText);

/** "songs like Kesariya" -> "Songs like Kesariya". */
export function playlistTitleFor(userText: string): string {
  const like = /\b(?:songs?|music|tracks?|gaane)\s+(?:like|similar to)\s+(.{2,50}?)\s*[?.!]*$/i.exec(userText.trim());
  if (like) return `Songs like ${clip(like[1].replace(/^["“']|["”']$/g, ""), 50)}`;
  return "Playlist";
}

// ---- a plain song list ------------------------------------------------------

const ITEM_RE = /^\s*(?:\d{1,2}[.)]|[-*•])\s+(.+?)\s*$/;
const SEP_RE = /\s+(?:[-–—]|by)\s+/i;

/** "**Tum Hi Ho** - Arijit Singh (2013): soulful" -> { Tum Hi Ho, Arijit Singh }. */
export function parseSongLine(text: string): Song | null {
  const s = text.replace(/\*\*|__/g, "").replace(/\[([^\]]+)\]\([^)]*\)/g, "$1").trim();
  const quoted = /^["“]([^"”]{1,90})["”]\s*(?:[-–—,]|by)?\s*(.*)$/i.exec(s);
  let title: string;
  let rest: string;
  if (quoted) {
    title = quoted[1];
    rest = quoted[2];
  } else {
    const parts = s.split(SEP_RE);
    if (parts.length < 2) return null;
    title = parts[0];
    rest = parts[1];
  }
  // The artist ends at a note: "(2013)", ": soulful", " - great for...".
  const artist = rest.replace(/^["“]|["”]$/g, "").split(/\s*[(:[]|\s+[-–—]\s+|\s*,\s*(?=\d{4})/)[0].replace(/[.,;\s]+$/, "");
  title = title.replace(/\s*\((?:\d{4}|from [^)]*|feat[^)]*)\)\s*$/i, "").replace(/^["“]|["”]$/g, "").trim();
  if (!title || !artist.trim() || title.length > 90 || artist.length > 70) return null;
  // Prose with a dash is not a song: titles and artists are short.
  if (title.split(/\s+/).length > 9 || artist.split(/\s+/).length > 8 || /[.!?]$/.test(title)) return null;
  return { title, artist: artist.trim() };
}

/**
 * The first run of >= 3 list lines that each read "Song - Artist", as line
 * indexes and songs. Lines inside code fences are ignored.
 */
export function detectSongList(text: string): { from: number; to: number; items: Song[] } | null {
  const lines = text.split("\n");
  let fenced = false;
  let run: { from: number; to: number; items: Song[] } | null = null;
  const flush = () => (run && run.items.length >= 3 ? run : null);
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*```/.test(lines[i])) {
      fenced = !fenced;
      const hit = flush();
      if (hit) return hit;
      run = null;
      continue;
    }
    if (fenced) continue;
    if (!lines[i].trim()) continue; // blank lines inside a loose list
    const m = ITEM_RE.exec(lines[i]);
    const song = m ? parseSongLine(m[1]) : null;
    if (song) {
      if (!run) run = { from: i, to: i, items: [] };
      run.to = i;
      run.items.push(song);
    } else {
      const hit = flush();
      if (hit) return hit;
      run = null;
    }
  }
  return flush();
}

/**
 * [text] with its song list replaced by a playlist block, or null when it has
 * no such list (or already holds a playlist). Only for music turns.
 */
export function convertSongList(text: string, userText: string): string | null {
  if (hasPlaylistBlock(text) || !isMusicTurn(userText)) return null;
  const found = detectSongList(text);
  if (!found) return null;
  const lines = text.split("\n");
  const block = playlistBlock({ title: playlistTitleFor(userText), items: found.items });
  const out = [...lines.slice(0, found.from), block, ...lines.slice(found.to + 1)];
  return out.join("\n").replace(/\n{3,}/g, "\n\n");
}

// ---- iTunes (no key) --------------------------------------------------------

export type Track = {
  title: string;
  artist: string;
  /** 300x300 cover. */
  art?: string;
  durationMs?: number;
  /** 30 s AAC preview. */
  previewUrl?: string;
  album?: string;
  year?: number;
  link?: string;
};

type ItunesRow = {
  kind?: string;
  trackName?: string;
  artistName?: string;
  collectionName?: string;
  artworkUrl100?: string;
  trackTimeMillis?: number;
  previewUrl?: string;
  releaseDate?: string;
  trackViewUrl?: string;
};

const words = (s: string) => new Set(normalizeQuery(s.replace(/\([^)]*\)|\[[^\]]*\]/g, " ")).split(" ").filter((w) => w.length > 1));
const overlap = (a: Set<string>, b: Set<string>) => {
  if (!a.size || !b.size) return 0;
  let n = 0;
  for (const w of a) if (b.has(w)) n++;
  return n / Math.min(a.size, b.size);
};

/** A 100x100 iTunes cover as 300x300. */
export const bigArt = (url: string): string => url.replace(/\/\d+x\d+(bb)?\.(jpg|png)$/i, "/300x300bb.$2");

/**
 * The best iTunes result for [want] (its title must match; its artist too when
 * given), mapped to a track. Null when none fits, so a wrong cover never shows.
 */
export function mapItunes(json: unknown, want: Song): Track | null {
  const results = json && typeof json === "object" ? (json as { results?: unknown }).results : undefined;
  const rows = (Array.isArray(results) ? (results as ItunesRow[]) : []).filter((r) => r && typeof r === "object" && r.trackName && (!r.kind || r.kind === "song"));
  const wantTitle = words(want.title);
  const wantArtist = words(want.artist);
  let best: { row: ItunesRow; score: number } | null = null;
  for (const row of rows) {
    const t = overlap(wantTitle, words(row.trackName!));
    const a = wantArtist.size ? overlap(wantArtist, words(row.artistName ?? "")) : 1;
    if (t < 0.6 || a < 0.5) continue;
    if (!best || t + a > best.score) best = { row, score: t + a };
  }
  if (!best) return null;
  const r = best.row;
  const year = r.releaseDate ? Number(r.releaseDate.slice(0, 4)) : NaN;
  const https = (u: string | undefined) => (u && u.startsWith("https://") ? u : undefined);
  const art = https(r.artworkUrl100);
  const previewUrl = https(r.previewUrl);
  const link = https(r.trackViewUrl);
  return {
    title: clip(r.trackName!, 120),
    artist: clip(r.artistName ?? want.artist, 100),
    ...(art ? { art: bigArt(art) } : {}),
    ...(r.trackTimeMillis && r.trackTimeMillis > 0 ? { durationMs: Math.round(r.trackTimeMillis) } : {}),
    ...(previewUrl ? { previewUrl } : {}),
    ...(r.collectionName ? { album: clip(r.collectionName, 120) } : {}),
    ...(year >= 1900 && year <= 2100 ? { year } : {}),
    ...(link ? { link } : {}),
  };
}

export const itunesUrl = (s: Song) => `https://itunes.apple.com/search?term=${encodeURIComponent(`${s.title} ${s.artist}`.trim())}&entity=song&limit=3&country=IN`;

/** Fetches iTunes JSON; injectable for tests. */
export type ItunesFetch = (url: string, signal?: AbortSignal) => Promise<unknown>;

const defaultItunes: ItunesFetch = async (url, signal) => {
  const ctl = AbortSignal.timeout(4_000);
  const r = await fetch(url, { signal: signal ? AbortSignal.any([signal, ctl]) : ctl, headers: { Accept: "application/json" } });
  if (!r.ok) throw new Error(`itunes ${r.status}`);
  return r.json();
};

const ITUNES_PER_MIN = 18; // Apple allows about 20 a minute per IP
const stamps: number[] = [];
/** Whether another live iTunes request fits in the rolling minute (and takes the slot). */
export function takeItunesSlot(now = Date.now()): boolean {
  while (stamps.length && stamps[0] <= now - 60_000) stamps.shift();
  if (stamps.length >= ITUNES_PER_MIN) return false;
  stamps.push(now);
  return true;
}

const TRACK_TTL = 30 * 24 * 3_600_000;
const MISS_TTL = 24 * 3_600_000;
const trackMem = new TtlLru<Track | null>(1000);
const idMem = new TtlLru<string | null>(1000);

/** Cache identity of a song: normalized "title artist". */
export const songKey = (s: Song) => normalizeQuery(`${s.title} ${s.artist}`).slice(0, 160);

const isStoredTrack = (v: unknown): v is { track: Track | null } => !!v && typeof v === "object" && "track" in (v as object);
const isStoredId = (v: unknown): v is { id: string | null } => !!v && typeof v === "object" && "id" in (v as object);

/** Runs [fn] over [items], [n] at a time, keeping order. */
export async function pool<T, R>(items: T[], n: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const out = new Array<R>(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(n, items.length) }, async () => {
      while (next < items.length) {
        const i = next++;
        out[i] = await fn(items[i]);
      }
    }),
  );
  return out;
}

/** One song's iTunes track from cache, else a live (paced) lookup. A song iTunes does not know stays a title/artist row. */
export async function lookupTrack(song: Song, o: { fetch?: ItunesFetch; signal?: AbortSignal; shared?: boolean } = {}): Promise<Track> {
  const plain: Track = { title: song.title, artist: song.artist };
  const key = `itunes|${songKey(song)}`;
  const shared = o.shared ?? !o.fetch;
  if (shared) {
    const hit = trackMem.get(key);
    if (hit !== undefined) return hit ?? plain;
    const stored = await readPersistedValue(key, isStoredTrack);
    if (stored) {
      trackMem.set(key, stored.track, stored.track ? TRACK_TTL : MISS_TTL);
      return stored.track ?? plain;
    }
  }
  if (!takeItunesSlot()) return plain; // over the minute budget: not cached, tried again next time
  try {
    const track = mapItunes(await (o.fetch ?? defaultItunes)(itunesUrl(song), o.signal), song);
    if (shared) {
      trackMem.set(key, track, track ? TRACK_TTL : MISS_TTL);
      writePersisted(key, { track }, track ? TRACK_TTL : MISS_TTL);
    }
    return track ?? plain;
  } catch {
    return plain;
  }
}

/** Enriches up to [MAX_TRACKS] songs (3 at a time). */
export async function enrichTracks(songs: Song[], o: { fetch?: ItunesFetch; signal?: AbortSignal } = {}): Promise<Track[]> {
  return pool(songs.slice(0, MAX_TRACKS), 3, (s) => lookupTrack(s, o));
}

// ---- YouTube ids and "Play all" ---------------------------------------------

/** Keyless web search; injectable for tests. */
export type YoutubeSearch = (query: string, signal?: AbortSignal) => Promise<Array<{ url: string; title?: string }>>;

/** The video id of the best youtube.com hit for [song] (a plain video, not a playlist or channel). */
export function pickYoutubeId(results: Array<{ url: string; title?: string }>, song: Song): string | null {
  const want = words(song.title);
  const videos = results
    .map((r) => ({ id: /\/(?:watch|shorts)|youtu\.be\//.test(r.url) ? youtubeId(r.url) : null, title: r.title ?? "" }))
    .filter((v): v is { id: string; title: string } => !!v.id && v.id.length === 11);
  if (!videos.length) return null;
  return (videos.find((v) => overlap(want, words(v.title)) >= 0.6) ?? videos[0]).id;
}

/** One song's YouTube video id (cached), or null. */
export async function lookupYoutubeId(song: Song, o: { search: YoutubeSearch; signal?: AbortSignal; shared?: boolean }): Promise<string | null> {
  const key = `ytid|${songKey(song)}`;
  const shared = o.shared ?? true;
  if (shared) {
    const hit = idMem.get(key);
    if (hit !== undefined) return hit;
    const stored = await readPersistedValue(key, isStoredId);
    if (stored) {
      idMem.set(key, stored.id, stored.id ? TRACK_TTL : MISS_TTL);
      return stored.id;
    }
  }
  try {
    const id = pickYoutubeId(await o.search(`${song.title} ${song.artist} site:youtube.com`, o.signal), song);
    if (shared) {
      idMem.set(key, id, id ? TRACK_TTL : MISS_TTL);
      writePersisted(key, { id }, id ? TRACK_TTL : MISS_TTL);
    }
    return id;
  } catch {
    return null;
  }
}

/** youtube.com's anonymous temporary playlist (opens in YouTube / YouTube Music). */
export const playAllUrl = (ids: string[]): string => `https://www.youtube.com/watch_videos?video_ids=${ids.join(",")}`;

/** Play all needs most tracks resolved (and at least two). */
export function playAllFor(ids: Array<string | null>): string | null {
  const found = [...new Set(ids.filter((i): i is string => !!i))];
  return found.length >= 2 && found.length >= Math.ceil(ids.length * 0.6) ? playAllUrl(found) : null;
}

/** Resolves ids for up to [MAX_TRACKS] songs (3 at a time) and the Play all link. */
export async function resolvePlayAll(songs: Song[], o: { search: YoutubeSearch; signal?: AbortSignal; shared?: boolean }): Promise<{ ids: Array<string | null>; playAll: string | null }> {
  const ids = await pool(songs.slice(0, MAX_TRACKS), 3, (s) => lookupYoutubeId(s, o));
  return { ids, playAll: playAllFor(ids) };
}

/** Test hook: forget what memory holds. */
export function resetPlaylistCaches() {
  trackMem.clear();
  idMem.clear();
  stamps.length = 0;
}
