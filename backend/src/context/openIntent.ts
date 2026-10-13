/**
 * "Open it on YouTube Music", "play this on Spotify", "show it in Maps":
 * deterministic open actions, so they work even when the model answers in
 * prose (weak or vision models often do). The link comes from, in order:
 *   1. the sources of the conversation (the last answer's citations),
 *   2. a site-scoped web search for the subject on that app's site,
 *   3. the app's own search page (a deep link the app opens when installed).
 * The result is a ```sparky-action url block the app shows as a card; it
 * names the app and its Android package so the phone can open the app
 * directly when it is installed, or the browser when it is not.
 */
import { ACTION_FENCE } from "./deviceActions.js";
import type { WebResult } from "../web/types.js";

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
  },
  {
    key: "youtube",
    label: "YouTube",
    aliases: ["youtube", "yt"],
    hosts: ["youtube.com", "m.youtube.com", "youtu.be"],
    item: /(\/watch\?(.*&)?v=|\/shorts\/|\/playlist\?(.*&)?list=|youtu\.be\/[\w-]{6,})/,
    package: "com.google.android.youtube",
    search: (s) => `https://www.youtube.com/results?search_query=${q(s)}`,
  },
  {
    key: "spotify",
    label: "Spotify",
    aliases: ["spotify"],
    hosts: ["open.spotify.com"],
    item: /\/(intl-[\w-]+\/)?(track|album|playlist|artist|episode|show)\/\w+/,
    package: "com.spotify.music",
    search: (s) => `https://open.spotify.com/search/${q(s)}`,
  },
  {
    key: "jiosaavn",
    label: "JioSaavn",
    aliases: ["jiosaavn", "jio saavn", "saavn"],
    hosts: ["jiosaavn.com"],
    item: /\/(song|album|featured|artist|s\/playlist)\//,
    package: "com.jio.media.jiobeats",
    search: (s) => `https://www.jiosaavn.com/search/${q(s)}`,
  },
  {
    key: "gaana",
    label: "Gaana",
    aliases: ["gaana"],
    hosts: ["gaana.com"],
    item: /\/(song|album|artist|playlist)\//,
    package: "com.gaana",
    search: (s) => `https://gaana.com/search/${q(s)}`,
  },
  {
    key: "apple_music",
    label: "Apple Music",
    aliases: ["apple music", "itunes"],
    hosts: ["music.apple.com"],
    item: /\/(album|song|playlist|artist|music-video)\//,
    package: "com.apple.android.music",
    search: (s) => `https://music.apple.com/search?term=${q(s)}`,
  },
  {
    key: "amazon",
    label: "Amazon",
    aliases: ["amazon"],
    hosts: ["amazon.in", "amazon.com", "amazon.co.uk", "amzn.in", "amzn.to"],
    item: /(\/dp\/|\/gp\/product\/|amzn\.(in|to)\/)/,
    package: "in.amazon.mShop.android.shopping",
    search: (s) => `https://www.amazon.in/s?k=${q(s)}`,
  },
  {
    key: "flipkart",
    label: "Flipkart",
    aliases: ["flipkart"],
    hosts: ["flipkart.com", "dl.flipkart.com"],
    item: /\/p\/itm/,
    package: "com.flipkart.android",
    search: (s) => `https://www.flipkart.com/search?q=${q(s)}`,
  },
  {
    key: "maps",
    label: "Google Maps",
    aliases: ["google maps", "maps", "map"],
    hosts: ["google.com/maps", "maps.google.com", "maps.app.goo.gl", "goo.gl/maps"],
    item: /(\/maps\/place\/|maps\.app\.goo\.gl\/|goo\.gl\/maps\/|[?&](q|query)=)/,
    package: "com.google.android.apps.maps",
    search: (s) => `https://www.google.com/maps/search/?api=1&query=${q(s)}`,
  },
];

export type OpenIntent = { app: MediaApp; query: string; explicit: boolean };

const VERBS = String.raw`open|play|listen(?:\s+to)?|watch|stream|go\s+to|take\s+me\s+to|show(?:\s+me)?|launch|start|find|search(?:\s+for)?|look\s+up|buy|order|get|put\s+on`;
const ALIASES = MEDIA_APPS.flatMap((a) => a.aliases.map((alias) => ({ alias, app: a }))).sort((x, y) => y.alias.length - x.alias.length);
const ALIAS_RE = ALIASES.map((x) => x.alias.replace(/\s+/g, String.raw`\s*`)).join("|");
const LEAD = String.raw`^\s*(?:(?:hey|ok|okay)\s+sparky[,\s]*)?(?:(?:please|pls|can\s+you|could\s+you|would\s+you|will\s+you|now|then|and|just)\s+)*`;
/** "open it on youtube music", "play I Met Her Again on Spotify please". */
const WITH_APP = new RegExp(`${LEAD}(?:${VERBS})\\b\\s*(.*?)\\s*\\b(?:on|in|with|using|via|at|from)\\s+(?:the\\s+)?(${ALIAS_RE})(?:\\s+app)?\\b[\\s.!?,]*(?:please|pls|now|for\\s+me)?[\\s.!?]*$`, "i");
/** "open youtube music". */
const APP_ONLY = new RegExp(`${LEAD}(?:${VERBS})\\s+(?:the\\s+)?(${ALIAS_RE})(?:\\s+app)?[\\s.!?]*(?:please|pls|now)?[\\s.!?]*$`, "i");
/** A query that only points back at the conversation: "it", "this song", "that one". */
const PRONOUN_RE = /^(?:(?:it|this|that|these|those|them|the|same|one|song|track|music|video|album|playlist|product|item|place|thing|there|here)\b\s*)*$/i;

function appByAlias(alias: string): MediaApp | null {
  const norm = alias.toLowerCase().replace(/\s+/g, "");
  return ALIASES.find((x) => x.alias.replace(/\s+/g, "") === norm)?.app ?? null;
}

/** The app and what to open in it, or null when the message is not an open request. */
export function parseOpenIntent(text: string): OpenIntent | null {
  const t = text.trim().slice(0, 300);
  if (!t || t.includes("\n")) return null;
  const m = WITH_APP.exec(t);
  if (m) {
    const app = appByAlias(m[2]);
    if (!app) return null;
    const raw = m[1].replace(/^["'“”]+|["'“”]+$/g, "").trim();
    return { app, query: PRONOUN_RE.test(raw) ? "" : raw.slice(0, 120), explicit: true };
  }
  const o = APP_ONLY.exec(t);
  if (o) {
    const app = appByAlias(o[1]);
    return app ? { app, query: "", explicit: false } : null;
  }
  return null;
}

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
    const yt = MEDIA_APPS.find((a) => a.key === "youtube")!;
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

/**
 * What the conversation is about, for the search: the user's own words when
 * they named it; else the bold names of the last answer ("**I Met Her Again**
 * by **Maan Panu**"); else the first source's title without its site suffix.
 */
export function openSubject(o: { query: string; lastAnswer: string; sources: SourceLink[] }): string {
  if (o.query.trim()) return o.query.trim();
  const bold = [...o.lastAnswer.matchAll(/\*\*([^*\n]{2,80})\*\*/g)].map((m) => m[1].trim()).filter((b) => !/[:]$/.test(b));
  if (bold.length) return bold.slice(0, 2).join(" ").slice(0, 120);
  const quoted = /["“]([^"”\n]{2,80})["”]/.exec(o.lastAnswer)?.[1];
  if (quoted) return quoted.trim();
  const title = o.sources.map((s) => cleanTitle(s.title ?? "")).find((t) => t.length >= 2);
  return title ?? "";
}

/** Searches the web; injectable for tests. */
export type SiteSearchFn = (queries: string[], signal?: AbortSignal) => Promise<WebResult[]>;

/** The site-scoped queries that find [subject] on [app]. */
export function siteQueries(app: MediaApp, subject: string): string[] {
  const host = app.hosts[0];
  return [`"${subject}" site:${host}`, `${subject} ${app.label}`];
}

export type OpenAction = {
  type: "url";
  url: string;
  /** The app the link is for (the card says "Open in <app>"). */
  app: string;
  /** Android package that opens it directly when installed. */
  package: string;
  /** Where the link came from: a source of the conversation, a web search, or the app's search page. */
  via: "source" | "search" | "app_search";
} | { type: "app"; name: string; package: string };

/**
 * The action for an open request, or null when there is nothing to open.
 * [search] runs only when no source holds a direct link and the request names
 * something (or the conversation has a subject).
 */
export async function resolveOpenAction(o: {
  intent: OpenIntent;
  sources: SourceLink[];
  lastAnswer: string;
  search?: SiteSearchFn;
  signal?: AbortSignal;
}): Promise<OpenAction | null> {
  const { app } = o.intent;
  const fromSource = o.intent.query ? null : pickAppLink(app, o.sources);
  if (fromSource) return { type: "url", url: fromSource, app: app.label, package: app.package, via: "source" };
  // "Open YouTube Music" with nothing in the conversation to open: the app itself.
  const subject = o.intent.explicit || o.sources.length ? openSubject({ query: o.intent.query, lastAnswer: o.lastAnswer, sources: o.sources }) : "";
  if (!subject) return { type: "app", name: app.label, package: app.package };
  if (o.search) {
    try {
      const found = await o.search(siteQueries(app, subject), o.signal);
      const link = pickAppLink(app, found.map((r) => ({ url: r.url, title: r.title })));
      if (link) return { type: "url", url: link, app: app.label, package: app.package, via: "search" };
    } catch {
      // Search failed: the app's own search page still gets the user there.
    }
  }
  return { type: "url", url: app.search(subject), app: app.label, package: app.package, via: "app_search" };
}

/** The fenced block the app turns into a card. */
export function actionBlock(a: OpenAction): string {
  const json = a.type === "url" ? { type: "url", url: a.url, app: a.app, package: a.package } : { type: "app", name: a.name, package: a.package };
  return `\n\n\`\`\`${ACTION_FENCE}\n${JSON.stringify(json)}\n\`\`\``;
}

/** Whether the reply already proposes an action. */
export const hasActionBlock = (text: string) => text.includes("```" + ACTION_FENCE);

/** Told to the model when the card is added for it: one sentence, no block of its own. */
export function openActionNote(a: OpenAction): string {
  const what = a.type === "url" ? `an "Open in ${a.app}" card for ${a.url}` : `an "Open ${a.name}" card`;
  return `The app will show ${what} under your reply; the user taps it to open. Reply with ONE short sentence (e.g. that it is ready to open in ${a.type === "url" ? a.app : a.name}). Do not write a ${ACTION_FENCE} block, a link or citations, and never say it is already open.`;
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
