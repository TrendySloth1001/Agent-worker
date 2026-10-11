import { USER_AGENT } from "../ingest/fetcher.js";

/** Iconify sets drawn in brand colors, then the monochrome brand set. */
const BRAND_SETS = ["logos", "devicon", "skill-icons", "simple-icons", "vscode-icons"];
/** General-purpose line icon sets, best match first. */
const GENERIC_SETS = ["hugeicons", "tabler", "lucide", "mdi", "ph"];

const NAME_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const TTL_MS = 24 * 60 * 60_000;
const cache = new Map<string, { at: number; id: string | null; svg: string | null }>();

const headers = { "User-Agent": `${USER_AGENT} (engineering chat app)` };

async function fetchSvg(id: string): Promise<string | null> {
  const [set, name] = id.split(":");
  const res = await fetch(`https://api.iconify.design/${set}/${name}.svg`, { headers, signal: AbortSignal.timeout(6000) });
  if (!res.ok) return null;
  const svg = await res.text();
  return svg.startsWith("<svg") ? svg : null;
}

async function search(query: string, sets: string[]): Promise<string[]> {
  const params = new URLSearchParams({ query, prefixes: sets.join(","), limit: "32" });
  const res = await fetch(`https://api.iconify.design/search?${params}`, { headers, signal: AbortSignal.timeout(6000) });
  if (!res.ok) return [];
  const icons = ((await res.json()) as { icons?: string[] }).icons ?? [];
  // Keep the set order we asked for: brand colors before monochrome, etc.
  return [...icons].sort((a, b) => sets.indexOf(a.split(":")[0]) - sets.indexOf(b.split(":")[0]));
}

/** "globe-01" -> "globe", "docker-icon" -> "docker", "chart-line-data-01" -> "chart line data". */
function searchTerms(name: string): string[] {
  const words = name.split("-").filter((w) => !/^\d+$/.test(w) && !["icon", "logo", "outline", "filled", "solid", "light", "dark"].includes(w));
  const full = words.join(" ");
  return [...new Set([full, words[0]].filter(Boolean))];
}

/**
 * Turns the icon id a model wrote into a real Iconify icon: the exact one if
 * it exists, otherwise the closest match from the same family of sets.
 * Returns null when nothing fits. Results are cached for a day.
 */
export async function resolveIcon(set: string, name: string): Promise<{ id: string; svg: string } | null> {
  if (!NAME_RE.test(set) || !NAME_RE.test(name)) return null;
  const key = `${set}:${name}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.id && hit.svg ? { id: hit.id, svg: hit.svg } : null;

  let id: string | null = null;
  let svg = await fetchSvg(key).catch(() => null);
  if (svg) id = key;
  else {
    const family = BRAND_SETS.includes(set) ? BRAND_SETS : [set, ...GENERIC_SETS.filter((s) => s !== set)];
    outer: for (const term of searchTerms(name)) {
      for (const sets of [[set], family]) {
        const found = await search(term, sets).catch(() => [] as string[]);
        const exact = found.find((i) => i.split(":")[1] === term.replace(/ /g, "-"));
        for (const candidate of exact ? [exact, ...found] : found) {
          svg = await fetchSvg(candidate).catch(() => null);
          if (svg) {
            id = candidate;
            break outer;
          }
        }
      }
    }
  }
  cache.set(key, { at: Date.now(), id, svg });
  if (cache.size > 2000) cache.delete(cache.keys().next().value as string);
  return id && svg ? { id, svg } : null;
}
