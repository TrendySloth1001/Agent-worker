/**
 * "Open it on YouTube Music", "play this on Spotify", "show it in Maps",
 * "open in music app", "gaana chalao": deterministic open actions. The turn
 * is answered without a model (one short sentence and the action card), so
 * weak models can neither echo the request nor add images, widgets or
 * sources to it. The link comes from, in order:
 *   1. the sources of the conversation (the last answer's citations),
 *   2. a site-scoped web search for the subject on that app's site,
 *   3. the app's own search page (a deep link the app opens when installed).
 * A generic target ("my music app", "play it") becomes the user's installed
 * app of that kind (the phone sends which known apps are installed); with
 * none installed, the reply asks which app to use.
 * The result is a ```sparky-action url block the app shows as a rich card
 * (cover, title, subtitle, the app's logo); it names the app and its Android
 * package so the phone opens the app directly when it is installed.
 */
import { ACTION_FENCE } from "./deviceActions.js";
import { linkMeta, type LinkMeta } from "./linkMeta.js";
import type { WebResult } from "../web/types.js";

/** Kinds of apps a generic request ("music app", "video app", "shopping app") can name. */
export type AppCategory = "music" | "video" | "shopping" | "maps";

export type MediaApp = {
  key: string;
  /** Shown on the card: "Open in YouTube Music". */
  label: string;
  /** How users name it, longest first within the app (matched as whole words). */
  aliases: string[];
  /** Hosts of the app's own links, preferred first. */
  hosts: string[];
  /** A direct item (track, video, product, place), not a search or home page. */
  item: RegExp;
  /** Android package that opens these links. */
  package: string;
  /** The app's search page for a query (fallback when no item link is found). */
  search: (q: string) => string;
  /** What kind of app it is: "play it in my music app" picks an installed one of the kind. */
  category: AppCategory;
};

const q = encodeURIComponent;

/** Media, shopping and maps apps the phone can open links in. Order matters: "youtube music" before "youtube". */
export const MEDIA_APPS: MediaApp[] = [
  {
    key: "youtube_music",
    label: "YouTube Music",
    aliases: ["youtube music", "yt music", "ytmusic", "youtube musik"],
    hosts: ["music.youtube.com"],
    item: /\/(watch\?(.*&)?v=|playlist\?(.*&)?list=|browse\/)/,
    package: "com.google.android.apps.youtube.music",
    search: (s) => `https://music.youtube.com/search?q=${q(s)}`,
    category: "music",
  },
  {
    key: "youtube",
    label: "YouTube",
    aliases: ["youtube", "yt"],
    hosts: ["youtube.com", "m.youtube.com", "youtu.be"],
    item: /(\/watch\?(.*&)?v=|\/shorts\/|\/playlist\?(.*&)?list=|youtu\.be\/[\w-]{6,})/,
    package: "com.google.android.youtube",
    search: (s) => `https://www.youtube.com/results?search_query=${q(s)}`,
    category: "video",
  },
  {
    key: "spotify",
    label: "Spotify",
    aliases: ["spotify"],
    hosts: ["open.spotify.com"],
    item: /\/(intl-[\w-]+\/)?(track|album|playlist|artist|episode|show)\/\w+/,
    package: "com.spotify.music",
    search: (s) => `https://open.spotify.com/search/${q(s)}`,
    category: "music",
  },
  {
    key: "jiosaavn",
    label: "JioSaavn",
    aliases: ["jiosaavn", "jio saavn", "saavn"],
    hosts: ["jiosaavn.com"],
    item: /\/(song|album|featured|artist|s\/playlist)\//,
    package: "com.jio.media.jiobeats",
    search: (s) => `https://www.jiosaavn.com/search/${q(s)}`,
    category: "music",
  },
  {
    key: "gaana",
    label: "Gaana",
    aliases: ["gaana"],
    hosts: ["gaana.com"],
    item: /\/(song|album|artist|playlist)\//,
    package: "com.gaana",
    search: (s) => `https://gaana.com/search/${q(s)}`,
    category: "music",
  },
  {
    key: "apple_music",
    label: "Apple Music",
    aliases: ["apple music", "itunes"],
    hosts: ["music.apple.com"],
    item: /\/(album|song|playlist|artist|music-video)\//,
    package: "com.apple.android.music",
    search: (s) => `https://music.apple.com/search?term=${q(s)}`,
    category: "music",
  },
  {
    key: "amazon",
    label: "Amazon",
    aliases: ["amazon"],
    hosts: ["amazon.in", "amazon.com", "amazon.co.uk", "amzn.in", "amzn.to"],
    item: /(\/dp\/|\/gp\/product\/|amzn\.(in|to)\/)/,
    package: "in.amazon.mShop.android.shopping",
    search: (s) => `https://www.amazon.in/s?k=${q(s)}`,
    category: "shopping",
  },
  {
    key: "flipkart",
    label: "Flipkart",
    aliases: ["flipkart"],
    hosts: ["flipkart.com", "dl.flipkart.com"],
    item: /\/p\/itm/,
    package: "com.flipkart.android",
    search: (s) => `https://www.flipkart.com/search?q=${q(s)}`,
    category: "shopping",
  },
  {
    key: "maps",
    label: "Google Maps",
    aliases: ["google maps", "maps", "map"],
    hosts: ["google.com/maps", "maps.google.com", "maps.app.goo.gl", "goo.gl/maps"],
    item: /(\/maps\/place\/|maps\.app\.goo\.gl\/|goo\.gl\/maps\/|[?&](q|query)=)/,
    package: "com.google.android.apps.maps",
    search: (s) => `https://www.google.com/maps/search/?api=1&query=${q(s)}`,
    category: "maps",
  },
];

export const appByKey = (key: string) => MEDIA_APPS.find((a) => a.key === key) ?? null;

/**
 * Apps of a kind, preferred first, for a generic request. YouTube closes the
 * music list: nearly every Android phone has it, and it plays any song.
 */
export const CATEGORY_APPS: Record<AppCategory, string[]> = {
  music: ["youtube_music", "spotify", "jiosaavn", "gaana", "apple_music", "youtube"],
  video: ["youtube"],
  shopping: ["amazon", "flipkart"],
  maps: ["maps"],
};

/**
 * What to open and where. [app] is the named app; null for a generic target
 * ("my music app", "play it"), then [category] says which kind of app (null:
 * whatever the conversation is about).
 */
export type OpenIntent = { app: MediaApp | null; category: AppCategory | null; query: string; explicit: boolean; implied?: boolean };

// ---- parsing ----------------------------------------------------------------

/** Verbs of an open request, with common typos ("opne", "paly"). */
const VERBS = String.raw`open|opne|oepn|opn|play|paly|plya|listen(?:\s+to)?|lisen(?:\s+to)?|watch|wacth|whatch|stream|go\s+to|take\s+me\s+to|show(?:\s+me)?|launch|start|find|search(?:\s+for)?|look\s+up|buy|order|get|put\s+on|resume|continue`;
const LEAD = String.raw`^\s*(?:(?:hey|ok|okay|hi)\s+sparky[,\s]*)?(?:(?:please|pls|plz|can\s+you|could\s+you|would\s+you|will\s+you|now|then|and|just|ok|okay|so)[,\s]+)*`;
const VERB_RE = new RegExp(`${LEAD}(${VERBS})\\b`, "i");
/** Questions about apps are answered, never acted on: "is it on Spotify?", "what app is this". */
const QUESTION = /^\s*(?:is|are|was|were|does|do|did|what|what's|whats|which|where|who|whom|why|how|when|should|shall|has|have|can\s+i|could\s+i|kya|kaun|kaunsa|kahan)\b/i;
const TAIL = /[\s.!?,]*(?:\b(?:please|pls|plz|now|for\s+me|na|yaar|bhai|thanks|thank\s+you)\b[\s.!?,]*)*$/i;
/** Words that point back at the conversation: "it", "this song", "that one", Hindi "isko", "ye gaana". */
const POINTER = String.raw`it|this|that|these|those|them|the|same|one|song|songs|track|tune|music|video|album|playlist|product|item|place|thing|there|here|again|now|up|is|isko|ise|isse|ye|yeh|ya|woh|wo|vo|usko|use|gaana|gana|gaane|gane|geet|wala|vala|wali|ko|bhi|zara|jara|ek|baar|bar|fir|phir|se|dobara|for|me|wahi|vahi`;
const POINTER_RE = new RegExp(`^(?:(?:${POINTER})\\b\\s*)*$`, "i");
/** Prepositions before a target: "on Spotify", "in my music app". */
const PREP = /(?:^|\s)(?:on|in|with|using|via|at|from|through|into|inside)\s+/gi;
/** Hindi / Hinglish verbs: "chalao", "bajao", "kholo", "play karo". */
const HI_VERBS = String.raw`chalao|chala\s*do|chala\s*de|chalaiye|chalana|bajao|baja\s*do|baja\s*de|bajaiye|sunao|suna\s*do|suna\s*de|kholo|khol\s*do|khol\s*de|kholiye|kholna|lagao|laga\s*do|laga\s*de|dikhao|dikha\s*do|(?:open|play|start|search)\s*(?:karo|kar\s*do|kar\s*de|kijiye|karna)`;
const HI_RE = new RegExp(`^(.*?)\\s*\\b(${HI_VERBS})$`, "i");
/** Hindi postpositions before a verb: "spotify pe", "music app mein". */
const HI_POST = /\s+(?:pe|par|pr|mein|me|mai|main|mei|se)$/i;

const ALIASES = MEDIA_APPS.flatMap((a) => a.aliases.map((alias) => ({ alias: alias.replace(/\s+/g, ""), app: a }))).sort(
  (x, y) => y.alias.length - x.alias.length,
);

/** Edit distance with transpositions (optimal string alignment), stopping early past [max]. */
function editDistance(a: string, b: string, max: number): number {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  const d: number[][] = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    let best = Infinity;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
      best = Math.min(best, d[i][j]);
    }
    if (best > max) return max + 1;
  }
  return d[a.length][b.length];
}

/** The named app, also with a typo ("youtub music", "spotfy"); short names must match exactly. */
function appByName(raw: string): MediaApp | null {
  const n = raw.toLowerCase().replace(/[^a-z0-9]+/g, "");
  if (!n) return null;
  const exact = ALIASES.find((x) => x.alias === n);
  if (exact) return exact.app;
  if (n.length < 5) return null;
  // Typos keep the first letter ("youtub music", "spotfy"); this also keeps "on youtube music" from matching.
  let best: { app: MediaApp; d: number } | null = null;
  for (const x of ALIASES) {
    if (x.alias.length < 5 || x.alias[0] !== n[0]) continue;
    const max = x.alias.length >= 9 ? 2 : 1;
    const d = editDistance(n, x.alias, max);
    if (d <= max && (!best || d < best.d)) best = { app: x.app, d };
  }
  return best?.app ?? null;
}

const CATEGORY_WORDS: Array<[RegExp, AppCategory]> = [
  [/^(?:music|song|songs|gaana|gaane|gana|gane|audio|music\s*streaming|streaming|mp3|songs?\s+streaming)$/i, "music"],
  [/^(?:video|videos|movie|movies)$/i, "video"],
  [/^(?:shopping|store|shop)$/i, "shopping"],
  [/^(?:navigation|map|maps|gps)$/i, "maps"],
];

type Target = { app: MediaApp | null; category: AppCategory | null };

/**
 * What a target phrase names: an app ("spotify", "the spotify app", "spotfy"),
 * a kind of app ("my music app", "a video app"), or just "the app" (category
 * null: the conversation decides). Null when it names neither.
 */
function resolveTarget(raw: string): Target | null {
  let t = raw.toLowerCase().replace(/[.!?,"'“”]+/g, " ").replace(/\s+/g, " ").trim();
  t = t.replace(/^(?:the|my|your|a|an|any|some|our)\s+/, "");
  const withApp = /\s*\b(?:app|apps|application|player)$/.test(t);
  t = t.replace(/\s*\b(?:app|apps|application|player)$/, "").trim();
  t = t.replace(/^(?:the|my|your|a|an|any|some|our|default|favourite|favorite)\s+/, "").trim();
  if (!t) return withApp ? { app: null, category: null } : null;
  // "gaana" alone is the Gaana app; "gaana app" too.
  const named = appByName(t);
  if (named) return { app: named, category: null };
  if (!withApp && !/^(?:music|video|shopping)\s*$/.test(t)) {
    // "in music" / "on video" without "app" still reads as the kind of app.
    if (!CATEGORY_WORDS.some(([re]) => re.test(t))) return null;
  }
  for (const [re, category] of CATEGORY_WORDS) if (re.test(t)) return { app: null, category };
  return null;
}

/** The kind of app a verb implies when no target is named: "watch it" is a video, "listen to it" music. */
function verbCategory(verb: string, rest: string): AppCategory | null {
  const v = verb.toLowerCase();
  if (/^(?:watch|wacth|whatch|dikha)/.test(v) || /\bvideo\b/i.test(rest)) return "video";
  if (/^(?:listen|lisen|bajao|baja|sunao|suna)/.test(v) || /\b(?:song|track|tune|music|gaana|gana|gaane|geet|album)\b/i.test(rest)) return "music";
  if (/^(?:play|paly|plya|put|stream|resume|chala)/.test(v)) return "music";
  return null;
}

const cleanQuery = (raw: string) => raw.replace(/^["'“”]+|["'“”]+$/g, "").replace(/\s+ko$/i, "").trim();
const queryOf = (raw: string) => {
  const c = cleanQuery(raw);
  return POINTER_RE.test(c) ? "" : c.slice(0, 120);
};

/** "<query> on <target>": the last preposition whose rest names a target. */
function splitTarget(rest: string): { query: string; target: Target } | null {
  const starts = [...rest.matchAll(PREP)].map((m) => ({ at: m.index ?? 0, end: (m.index ?? 0) + m[0].length }));
  for (let i = starts.length - 1; i >= 0; i--) {
    const target = resolveTarget(rest.slice(starts[i].end));
    if (target) return { query: rest.slice(0, starts[i].at), target };
  }
  return null;
}

function parseEnglish(t: string): OpenIntent | null {
  const m = VERB_RE.exec(t);
  if (!m) return null;
  const verb = m[1];
  const rest = t.slice(m[0].length).trim();
  const split = splitTarget(rest);
  if (split) {
    const query = queryOf(split.query);
    return { app: split.target.app, category: split.target.app ? null : (split.target.category ?? verbCategory(verb, split.query)), query, explicit: true };
  }
  // "open youtube music", "open the music app".
  const whole = rest ? resolveTarget(rest) : null;
  if (whole) return { app: whole.app, category: whole.app ? null : whole.category, query: "", explicit: false };
  // "play it", "play this song", "watch it again", "open it": the conversation's subject.
  if (rest && POINTER_RE.test(rest)) {
    const category = verbCategory(verb, rest);
    if (!category && !/^(?:open|opne|oepn|opn|launch|start|resume|continue)$/i.test(verb)) return null;
    return { app: null, category, query: "", explicit: true, implied: true };
  }
  return null;
}

/** "gaana chalao", "isko chalao", "music app mein kholo", "Kesariya spotify pe bajao". */
function parseHinglish(t: string): OpenIntent | null {
  const m = HI_RE.exec(t);
  if (!m) return null;
  const verb = m[2];
  let left = m[1].trim();
  let target: Target | null = null;
  const post = HI_POST.exec(left);
  if (post) {
    const before = left.slice(0, post.index).trim();
    const words = before.split(/\s+/);
    // The target is the last 1-3 words before the postposition ("music app", "youtube music", "spotify").
    for (let n = Math.min(3, words.length); n >= 1 && !target; n--) {
      const found = resolveTarget(words.slice(-n).join(" "));
      if (found) {
        target = found;
        left = words.slice(0, -n).join(" ");
      }
    }
    if (!target) return null;
  }
  if (!target && left && !POINTER_RE.test(left)) {
    // "spotify chalao": the app itself ("gaana chalao" is "play the song").
    const whole = resolveTarget(left);
    if (whole?.app) return { app: whole.app, category: null, query: "", explicit: false };
  }
  const query = queryOf(left);
  if (!target && query && !/^(?:bajao|baja|sunao|suna|chala)/i.test(verb)) return null;
  const category = target?.app ? null : (target?.category ?? verbCategory(verb, left));
  if (!target && !category && !/^(?:khol|open)/i.test(verb)) return null;
  return { app: target?.app ?? null, category, query, explicit: true, ...(target ? {} : { implied: true }) };
}

/** The app and what to open in it, or null when the message is not an open request. */
export function parseOpenIntent(text: string): OpenIntent | null {
  const raw = text.trim().slice(0, 300);
  if (!raw || raw.includes("\n") || QUESTION.test(raw)) return null;
  const t = raw.replace(TAIL, "").trim();
  if (!t) return null;
  return parseEnglish(t) ?? parseHinglish(t);
}

// ---- links ------------------------------------------------------------------

export type SourceLink = { url: string; title?: string };

function hostPath(url: string): { host: string; full: string } | null {
  try {
    const u = new URL(url);
    if (u.protocol !== "https:" && u.protocol !== "http:") return null;
    const host = u.hostname.toLowerCase().replace(/^www\./, "");
    return { host, full: `${host}${u.pathname}${u.search}` };
  } catch {
    return null;
  }
}

/** Whether [url] is on one of [app]'s hosts (index of the host, -1 when not). */
function hostRank(app: MediaApp, url: string): number {
  const hp = hostPath(url);
  if (!hp) return -1;
  return app.hosts.findIndex((h) => (h.includes("/") ? hp.full.startsWith(h) || hp.full.startsWith(`www.${h}`) : hp.host === h || hp.host.endsWith(`.${h}`)));
}

/** A direct item link of [app]: on its host and an item page (not search/home). */
export function isAppItem(app: MediaApp, url: string): boolean {
  return hostRank(app, url) >= 0 && app.item.test(url);
}

/** The app whose item page [url] is (YouTube Music before YouTube). */
export function appOfLink(url: string): MediaApp | null {
  return MEDIA_APPS.find((a) => isAppItem(a, url)) ?? null;
}

const YT_ID = /(?:[?&]v=|youtu\.be\/|\/shorts\/)([\w-]{6,})/;

/**
 * The best direct link for [app] among [links]: its own item links first (in
 * the app's host order); for YouTube Music a YouTube video also works (the
 * same id opens in YouTube Music).
 */
export function pickAppLink(app: MediaApp, links: SourceLink[]): string | null {
  const items = links.filter((l) => isAppItem(app, l.url)).sort((a, b) => hostRank(app, a.url) - hostRank(app, b.url));
  if (items.length) return items[0].url;
  if (app.key === "youtube_music") {
    const yt = appByKey("youtube")!;
    for (const l of links) {
      const id = isAppItem(yt, l.url) ? YT_ID.exec(l.url)?.[1] : undefined;
      if (id) return `https://music.youtube.com/watch?v=${id}`;
    }
  }
  return null;
}

/** Site names that sources append to titles: "Song - Artist - YouTube", "… | JioSaavn". */
const TITLE_TAIL = /\s*[-|–—:]\s*(youtube( music)?|spotify|jiosaavn|gaana(\.com)?|apple music|amazon(\.\w+)?|flipkart(\.com)?|google maps|wikipedia|lyrics.*|official.*video.*|song download.*|listen.*)\s*$/i;

function cleanTitle(t: string): string {
  let s = t.replace(/\s+/g, " ").trim();
  for (let i = 0; i < 3; i++) s = s.replace(TITLE_TAIL, "").trim();
  return s.slice(0, 100);
}

/** What the conversation is about, as a name and (when known) who made it. */
export type Subject = { title: string; by?: string };

/**
 * What the conversation is about: the user's own words when they named it;
 * else the bold names of the last answer ("**I Met Her Again** by **Maan
 * Panu**"); else a quoted name; else the first source's title without its
 * site suffix ("Song - Artist").
 */
export function subjectOf(o: { query: string; lastAnswer: string; sources: SourceLink[] }): Subject | null {
  if (o.query.trim()) return { title: o.query.trim() };
  const bold = [...o.lastAnswer.matchAll(/\*\*([^*\n]{2,80})\*\*/g)].map((m) => m[1].trim()).filter((b) => !/[:]$/.test(b));
  if (bold.length) return { title: bold[0].slice(0, 100), ...(bold[1] ? { by: bold[1].slice(0, 80) } : {}) };
  const quoted = /["“]([^"”\n]{2,80})["”](?:\s+by\s+([^.,;\n[]{2,60}))?/.exec(o.lastAnswer);
  if (quoted) return { title: quoted[1].trim(), ...(quoted[2] ? { by: quoted[2].trim() } : {}) };
  const title = o.sources.map((s) => cleanTitle(s.title ?? "")).find((t) => t.length >= 2);
  if (!title) return null;
  const [name, by] = title.split(/\s+[-–—]\s+/);
  return { title: name, ...(by ? { by } : {}) };
}

/** The subject as one search string ("I Met Her Again Maan Panu"). */
export function openSubject(o: { query: string; lastAnswer: string; sources: SourceLink[] }): string {
  if (o.query.trim()) return o.query.trim();
  const bold = [...o.lastAnswer.matchAll(/\*\*([^*\n]{2,80})\*\*/g)].map((m) => m[1].trim()).filter((b) => !/[:]$/.test(b));
  if (bold.length) return bold.slice(0, 2).join(" ").slice(0, 120);
  const quoted = /["“]([^"”\n]{2,80})["”]/.exec(o.lastAnswer)?.[1];
  if (quoted) return quoted.trim();
  return o.sources.map((s) => cleanTitle(s.title ?? "")).find((t) => t.length >= 2) ?? "";
}

/** Searches the web; injectable for tests. */
export type SiteSearchFn = (queries: string[], signal?: AbortSignal) => Promise<WebResult[]>;

/** The site-scoped queries that find [subject] on [app]. */
export function siteQueries(app: MediaApp, subject: string): string[] {
  const host = app.hosts[0];
  return [`"${subject}" site:${host}`, `${subject} ${app.label}`];
}

// ---- resolution -------------------------------------------------------------

export type OpenAction =
  | {
      type: "url";
      url: string;
      /** The app the link is for (the card says "Open in <app>"). */
      app: string;
      /** Android package that opens it directly when installed. */
      package: string;
      /** Where the link came from: a source of the conversation, a web search, or the app's search page. */
      via: "source" | "search" | "app_search";
      /** Rich card: the item's name, who made it (or the site) and a cover image. */
      title?: string;
      subtitle?: string;
      image?: string;
      site?: string;
    }
  | { type: "app"; name: string; package: string }
  /** A generic target ("my music app") with none of its apps installed: the reply asks which one. */
  | { type: "choice"; category: AppCategory; apps: string[]; subject: string };

/** What the conversation's links and words say it is about: a cited app's kind, else song or video words. */
export function inferCategory(sources: SourceLink[], lastAnswer: string): AppCategory | null {
  for (const s of sources) {
    const app = appOfLink(s.url);
    if (app) return app.category === "video" ? "music" : app.category;
  }
  if (/\b(songs?|track|singer|album|lyrics|music|band|rapper|composer|soundtrack|gaana)\b/i.test(lastAnswer)) return "music";
  if (/\b(video|movie|film|trailer|episode|channel)\b/i.test(lastAnswer)) return "video";
  if (/\b(price|buy|product|deal|₹|\$)\b/i.test(lastAnswer)) return "shopping";
  return null;
}

/** The app the user named last in this conversation (their earlier messages, newest first). */
function lastNamedApp(history: string[], category: AppCategory): MediaApp | null {
  for (const text of [...history].reverse()) {
    const i = parseOpenIntent(text);
    if (i?.app && (i.app.category === category || CATEGORY_APPS[category].includes(i.app.key))) return i.app;
  }
  return null;
}

/**
 * The app for a generic target: among the installed apps of the kind, the
 * one the user named last in the conversation, then one the sources link to,
 * then the preferred order. [installed] null means unknown (all count).
 * Null when none of the kind is installed.
 */
export function pickGenericApp(o: { category: AppCategory; installed: string[] | null; sources: SourceLink[]; history: string[] }): MediaApp | null {
  const keys = CATEGORY_APPS[o.category];
  const ok = (a: MediaApp | null): a is MediaApp => !!a && keys.includes(a.key) && (o.installed == null || o.installed.includes(a.key));
  const named = lastNamedApp(o.history, o.category);
  if (ok(named)) return named;
  for (const s of o.sources) {
    const app = appOfLink(s.url);
    // A YouTube video of a song also opens in YouTube Music, which is preferred when installed.
    if (app?.key === "youtube" && o.category === "music" && ok(appByKey("youtube_music"))) return appByKey("youtube_music");
    if (ok(app)) return app;
  }
  return keys.map(appByKey).find(ok) ?? null;
}

/** Reads a link's card metadata; injectable for tests. */
export type MetaFn = (url: string, signal?: AbortSignal) => Promise<LinkMeta>;

/**
 * The action for an open request, or null when there is nothing to open (a
 * generic "open it" with no media in the conversation).
 * [search] runs only when no source holds a direct link and the request names
 * something (or the conversation has a subject).
 */
export async function resolveOpenAction(o: {
  intent: OpenIntent;
  sources: SourceLink[];
  lastAnswer: string;
  /** The user's earlier messages ("play it on spotify" earlier makes Spotify the music app). */
  history?: string[];
  /** Keys of the known apps installed on the phone; null or omitted when unknown. */
  installed?: string[] | null;
  search?: SiteSearchFn;
  meta?: MetaFn;
  signal?: AbortSignal;
}): Promise<OpenAction | null> {
  const subjectText = (explicit: boolean) =>
    explicit || o.sources.length ? openSubject({ query: o.intent.query, lastAnswer: o.lastAnswer, sources: o.sources }) : "";
  let app = o.intent.app;
  if (!app) {
    const context = inferCategory(o.sources, o.lastAnswer);
    // "play it" / "isko chalao" with no song, video or product in the conversation: the model answers instead.
    if (o.intent.implied && !context) return null;
    const category = o.intent.category ?? context;
    if (!category) return null;
    app = pickGenericApp({ category, installed: o.installed ?? null, sources: o.sources, history: o.history ?? [] });
    if (!app) {
      const subject = subjectOf({ query: o.intent.query, lastAnswer: o.lastAnswer, sources: o.sources })?.title ?? "";
      return { type: "choice", category, apps: CATEGORY_APPS[category].slice(0, 3).map((k) => appByKey(k)!.label), subject };
    }
  }
  const fromSource = o.intent.query ? null : pickAppLink(app, o.sources);
  const subject = subjectOf({ query: o.intent.query, lastAnswer: o.lastAnswer, sources: o.sources });
  const rich = async (url: string, via: "source" | "search"): Promise<OpenAction> => {
    const m = await (o.meta ?? ((u, signal) => linkMeta(u, { signal })))(url, o.signal).catch(() => ({}) as LinkMeta);
    const title = subject?.title ?? m.title;
    const subtitle = subject?.by ?? m.subtitle ?? (m.site && m.site !== app!.label ? m.site : undefined);
    return {
      type: "url",
      url,
      app: app!.label,
      package: app!.package,
      via,
      ...(title ? { title } : {}),
      ...(subtitle ? { subtitle } : {}),
      ...(m.image ? { image: m.image } : {}),
      ...(m.site ? { site: m.site } : {}),
    };
  };
  if (fromSource) return rich(fromSource, "source");
  // "Open YouTube Music" with nothing in the conversation to open: the app itself.
  const text = subjectText(o.intent.explicit);
  if (!text) return { type: "app", name: app.label, package: app.package };
  if (o.search) {
    try {
      const found = await o.search(siteQueries(app, text), o.signal);
      const link = pickAppLink(app, found.map((r) => ({ url: r.url, title: r.title })));
      if (link) return rich(link, "search");
    } catch {
      // Search failed: the app's own search page still gets the user there.
    }
  }
  return {
    type: "url",
    url: app.search(text),
    app: app.label,
    package: app.package,
    via: "app_search",
    ...(subject ? { title: subject.title } : {}),
    ...(subject?.by ? { subtitle: subject.by } : {}),
  };
}

/** The fenced block the app turns into a card (null for a choice, which has no card). */
export function actionBlock(a: OpenAction): string {
  if (a.type === "choice") return "";
  const json =
    a.type === "url"
      ? {
          type: "url",
          url: a.url,
          app: a.app,
          package: a.package,
          ...(a.title ? { title: a.title } : {}),
          ...(a.subtitle ? { subtitle: a.subtitle } : {}),
          ...(a.image ? { image: a.image } : {}),
          ...(a.site ? { site: a.site } : {}),
        }
      : { type: "app", name: a.name, package: a.package };
  return `\n\n\`\`\`${ACTION_FENCE}\n${JSON.stringify(json)}\n\`\`\``;
}

/** Whether the reply already proposes an action. */
export const hasActionBlock = (text: string) => text.includes("```" + ACTION_FENCE);

const VERB_OF: Record<AppCategory, string> = { music: "play", video: "play", shopping: "open", maps: "show" };

/**
 * The whole reply of an open turn: one short sentence (never the user's
 * request echoed back) followed by the card. A choice asks which app instead,
 * and [suggestions] are its answers ("Play it on Spotify").
 */
export function openReply(a: OpenAction): { text: string; suggestions: string[] } {
  if (a.type === "choice") {
    const what = a.subject ? `"${a.subject}"` : "it";
    return {
      text: `None of the usual ${a.category} apps seem to be installed. Which app should I ${VERB_OF[a.category]} ${what} in?`,
      suggestions: a.apps.map((label) => `${VERB_OF[a.category] === "play" ? "Play" : "Open"} it on ${label}`),
    };
  }
  if (a.type === "app") return { text: `Ready to open ${a.name}.${actionBlock(a)}`, suggestions: [] };
  const app = appByKey(MEDIA_APPS.find((x) => x.label === a.app)?.key ?? "");
  const verb = VERB_OF[app?.category ?? "shopping"];
  const name = a.title ? `"${a.title}"` : "it";
  const text =
    a.via === "app_search"
      ? `Ready to search for ${name} in ${a.app}.`
      : `Ready to ${verb} ${name} in ${a.app}.`;
  return { text: `${text}${actionBlock(a)}`, suggestions: [] };
}

/**
 * Told to the model when it still writes the reply (an open request with an
 * attachment): one sentence, the card is added for it.
 */
export function openActionNote(a: OpenAction): string {
  const what = a.type === "url" ? `an "Open in ${a.app}" card` : a.type === "app" ? `an "Open ${a.name}" card` : "a choice of apps";
  return `The app will show ${what} under your reply; the user taps it. Reply with ONE short sentence in your own words (never repeat the user's request), with no ${ACTION_FENCE} block, links, citations, images ({{image:}}), widgets or code blocks, and never say it is already open.`;
}

/** Links of the conversation's recent answers: the sources the client sent plus markdown links in the last answer. */
export function conversationLinks(sources: SourceLink[] | undefined, lastAnswer: string): SourceLink[] {
  const md = [...lastAnswer.matchAll(/\[([^\]\n]{1,120})\]\((https?:\/\/[^\s)]+)\)/g)].map((m) => ({ title: m[1], url: m[2] }));
  const bare = [...lastAnswer.matchAll(/(?<!\()https?:\/\/[^\s<>"')\]]+/g)].map((m) => ({ url: m[0] }));
  const seen = new Set<string>();
  return [...(sources ?? []), ...md, ...bare].filter((l) => {
    if (seen.has(l.url)) return false;
    seen.add(l.url);
    return true;
  });
}
