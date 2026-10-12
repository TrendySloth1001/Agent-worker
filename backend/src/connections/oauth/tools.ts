import type { ContextItem } from "../../prompts/system.js";
import { db } from "../../db/prisma.js";
import { log } from "../../util/logger.js";
import { drive as liveDrive } from "./drive.js";
import { notionApi as liveNotion } from "./notion.js";
import { PROVIDERS, providerConfigured, type ProviderId } from "./providers.js";

/**
 * Read-only chat tools over the connected apps: drive_search, drive_read,
 * notion_search, notion_read. The harness runs them for the model (like the
 * GitHub grounding) when the user's message is about their Drive or Notion,
 * or when the app attached an item ("Ask Sparky about this page"). Results
 * become numbered sources (the chat route numbers them as [D#] documents). Nothing here writes: saving to Drive or Notion is
 * always an explicit tap in the app.
 */

export type AppRef = { provider: ProviderId; id: string; title?: string };

export type AppTools = {
  drive_search: (userId: string, q: string) => Promise<Array<{ id: string; title: string; url: string; note: string }>>;
  drive_read: (userId: string, id: string, maxChars: number) => Promise<{ title: string; url: string; text: string }>;
  notion_search: (userId: string, q: string) => Promise<Array<{ id: string; title: string; url: string; note: string }>>;
  notion_read: (userId: string, id: string, maxChars: number) => Promise<{ title: string; url: string; text: string }>;
};

export const liveTools: AppTools = {
  async drive_search(userId, q) {
    const r = await liveDrive.list(userId, { q, pageSize: 5 });
    return r.files.map((f) => ({ id: f.id, title: f.name, url: f.webViewLink ?? "", note: `${f.mimeType}${f.modifiedTime ? `, modified ${f.modifiedTime.slice(0, 10)}` : ""}` }));
  },
  async drive_read(userId, id, maxChars) {
    const c = await liveDrive.read(userId, id, maxChars);
    return { title: c.file.name, url: c.file.webViewLink ?? "", text: c.text };
  },
  async notion_search(userId, q) {
    const r = await liveNotion.search(userId, { q, pageSize: 5 });
    return r.items.map((i) => ({ id: i.id, title: i.title, url: i.url, note: `${i.object}${i.lastEdited ? `, edited ${i.lastEdited.slice(0, 10)}` : ""}` }));
  },
  async notion_read(userId, id, maxChars) {
    const p = await liveNotion.read(userId, id, maxChars);
    return { title: p.title, url: p.url, text: p.markdown };
  },
};

const DRIVE_RE = /\b(?:google\s+drive|g\s?drive|my\s+drive|(?:in|from|on)\s+(?:my\s+)?drive)\b|\bdrive\s+(?:files?|docs?|folder)\b/i;
const NOTION_RE = /\bnotion\b/i;
/** Words that say nothing about which file or page is meant. */
const STOP = new Set(
  (
    "a an the my me i you your in on from of to for with about what whats what's is are was were do does did can could would " +
    "please tell show find search look get read summarize summarise summary explain give list any some all this that these those " +
    "google drive gdrive notion page pages file files doc docs document documents note notes workspace there here and or it its " +
    "say says said say? have has had into"
  ).split(" "),
);

export type AppsIntent = { drive: boolean; notion: boolean; query: string };

/** Which connected app the message is about, and the search words. Null when neither. */
export function appsIntent(text: string): AppsIntent | null {
  const t = (text ?? "").slice(0, 600);
  const drive = DRIVE_RE.test(t);
  const notion = NOTION_RE.test(t);
  if (!drive && !notion) return null;
  const quoted = t.match(/["“']([^"”']{2,80})["”']/);
  const query = quoted
    ? quoted[1]
    : t
        .toLowerCase()
        .replace(/[^\p{L}\p{N}\s.-]/gu, " ")
        .split(/\s+/)
        .filter((w) => w.length > 1 && !STOP.has(w))
        .slice(0, 6)
        .join(" ");
  return { drive, notion, query };
}

export type AppsGrounding = { items: ContextItem[]; hint: string | null; used: ProviderId[] };

export type GroundDeps = {
  tools: AppTools;
  /** Providers the user has connected (and not flagged for Reconnect). */
  connected: (userId: string) => Promise<Set<ProviderId>>;
  configured: (p: ProviderId) => boolean;
};

const READ_CHARS = 8_000;
const READ_TOP = 2;
const ATTACHED_CHARS = 24_000;

/**
 * Runs the app tools for one chat turn. [refs] are items the app attached
 * explicitly (read in full, up to a budget); otherwise a message about Drive
 * or Notion searches the connected app and reads the best matches.
 */
export async function appsGround(
  userId: string | null,
  text: string,
  refs: AppRef[] = [],
  opts: { prefix?: string; firstId?: number } = {},
  deps: GroundDeps = liveDeps,
): Promise<AppsGrounding | null> {
  const prefix = opts.prefix ?? "A";
  const firstId = opts.firstId ?? 1;
  if (!userId) return null;
  const intent = appsIntent(text);
  if (!intent && !refs.length) return null;
  const connected = await deps.connected(userId);
  const items: ContextItem[] = [];
  const used = new Set<ProviderId>();
  const notes: string[] = [];
  const push = (provider: ProviderId, title: string, url: string, body: string) => {
    used.add(provider);
    items.push({ id: `${prefix}${firstId + items.length}`, title: `${title} (${PROVIDERS[provider].name})`, url: url || PROVIDERS[provider].homeUrl, text: body });
  };
  const run = async <T>(what: string, fn: () => Promise<T>): Promise<T | null> => {
    try {
      return await fn();
    } catch (e) {
      log.info("app tool failed", { tool: what, message: (e as Error).message.slice(0, 100) });
      notes.push(`${what} failed: ${(e as Error).message.slice(0, 140)}`);
      return null;
    }
  };

  for (const ref of refs.slice(0, 3)) {
    if (!connected.has(ref.provider)) continue;
    const r = await run(`${ref.provider === "notion" ? "notion_read" : "drive_read"}`, () =>
      (ref.provider === "notion" ? deps.tools.notion_read : deps.tools.drive_read)(userId, ref.id, ATTACHED_CHARS),
    );
    if (r) push(ref.provider, r.title, r.url, r.text || "(empty)");
  }

  if (intent && !refs.length) {
    const wanted: ProviderId[] = [...(intent.drive ? (["google_drive"] as const) : []), ...(intent.notion ? (["notion"] as const) : [])];
    for (const p of wanted) {
      const name = PROVIDERS[p].name;
      if (!connected.has(p)) {
        notes.push(
          deps.configured(p)
            ? `${name} is not connected. If the user asks about their ${name} content, say in one short sentence that they can connect ${name} in Apps (sidebar → Apps → ${name}); do not invent its contents.`
            : `${name} is not available on this server; do not claim to read it.`,
        );
        continue;
      }
      const search = p === "notion" ? deps.tools.notion_search : deps.tools.drive_search;
      const read = p === "notion" ? deps.tools.notion_read : deps.tools.drive_read;
      const hits = await run(p === "notion" ? "notion_search" : "drive_search", () => search(userId, intent.query));
      if (!hits) continue;
      if (!hits.length) {
        notes.push(
          p === "notion"
            ? `notion_search found nothing for "${intent.query}". Only pages the user shared with sparky are visible; say so and suggest sharing the page with sparky in Notion.`
            : `drive_search found nothing for "${intent.query}". sparky only sees Drive files the user picked in the app (Apps → Google Drive → Pick files) or saved from sparky; say so briefly.`,
        );
        continue;
      }
      push(p, `Search results for "${intent.query || "recent"}"`, PROVIDERS[p].homeUrl, hits.map((h) => `- ${h.title} (${h.note}) ${h.url}`).join("\n"));
      for (const h of hits.slice(0, READ_TOP)) {
        const r = await run(p === "notion" ? "notion_read" : "drive_read", () => read(userId, h.id, READ_CHARS));
        if (r) push(p, r.title, r.url || h.url, r.text || "(empty)");
      }
    }
  }

  if (!items.length && !notes.length) return null;
  const hint =
    (items.length
      ? `Connected apps: sources ${items.map((i) => `[${i.id}]`).join(", ")} are the user's own Google Drive files or Notion pages, read live with their permission. Answer from them and cite those tags. You can only read; never say you changed, created or saved anything in Drive or Notion (the user does that with the app's Save buttons).\n`
      : "") + notes.join("\n");
  return { items, hint: hint.trim() || null, used: [...used] };
}

export const liveDeps: GroundDeps = {
  tools: liveTools,
  connected: async (userId) => {
    const rows = await db().connection.findMany({
      where: { userId, provider: { in: ["google_drive", "notion"] }, needsReauth: false },
      select: { provider: true },
    });
    return new Set(rows.map((r) => r.provider as ProviderId));
  },
  configured: (p) => providerConfigured(PROVIDERS[p]),
};
