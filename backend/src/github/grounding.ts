import type { ContextItem } from "../prompts/system.js";
import { log } from "../util/logger.js";
import { githubEnabled } from "./client.js";
import * as svc from "./service.js";

/**
 * GitHub grounding for chat: when the user's message is clearly about GitHub
 * (a github.com link, an owner/repo next to repo words, or "find a repo /
 * library for X"), live GitHub data is fetched and added as [G#] sources.
 * Pure regex intent, so unrelated questions never trigger API calls.
 */

export type RepoRef = { owner: string; repo: string };
export type GithubIntent = {
  repos: RepoRef[];
  search: { q: string; sort?: "stars" } | null;
  commits: boolean;
  pulls: boolean;
  issues: boolean;
  releases: boolean;
  contributors: boolean;
  tree: boolean;
};

const URL_REF = /github\.com\/([A-Za-z0-9][\w-]{0,38})\/([\w.-]{1,100})/gi;
const BARE_REF = /(?<![\w./@:-])([A-Za-z0-9][\w-]{0,38})\/([A-Za-z0-9_.-]{1,100})(?![\w/])/g;
const GH_WORDS =
  /\b(github|gh|repos?|repositor(?:y|ies)|commits?|commit history|pull requests?|prs?|issues?|releases?|branch(?:es)?|contributors?|maintainers?|stars?|forks?|source code|codebase|readme|file tree|changelog)\b/i;
const STRONG = /\b(github|repos?|repositor(?:y|ies)|open[- ]?source)\b/i;
const FINDISH =
  /\b(find|search|look(?:ing)? for|recommend|suggest|show|list|discover|best|top|popular|good|alternatives?|which|what are|any)\b/i;
const FIND_LIB =
  /\b(find|search|look(?:ing)? for|recommend|suggest)\b[^.?!\n]{0,60}\b(librar(?:y|ies)|packages?|projects?|sdks?|clis?)\b|\b(librar(?:y|ies)|packages?|sdks?)\b[^.?!\n]{0,60}\b(recommend|suggest)/i;
const NOT_REPO = new Set([
  "and", "or", "i", "o", "tcp", "ip", "input", "output", "read", "write", "client", "server", "yes", "no", "true", "false",
  "a", "b", "n", "x", "y", "on", "off", "km", "h", "s", "ms", "kg", "per", "w", "with", "without", "he", "she", "him", "her",
  "src", "lib", "app", "usr", "etc", "bin", "dev", "home", "var", "tmp", "api", "docs", "test", "tests",
]);
const POPULAR = /\b(popular|best|top|most (?:starred|used|popular)|famous|well[- ]known|trending)\b/i;
const LANGS: Record<string, string> = {
  rust: "rust", go: "go", golang: "go", python: "python", typescript: "typescript", ts: "typescript", javascript: "javascript",
  js: "javascript", java: "java", kotlin: "kotlin", swift: "swift", dart: "dart", flutter: "dart", ruby: "ruby", php: "php",
  elixir: "elixir", haskell: "haskell", scala: "scala", zig: "zig", "c++": "c++", cpp: "c++", "c#": "c#", csharp: "c#",
};
const STOP = new Set(
  (
    "find me search look looking for recommend suggest show list discover some any a an the best top popular good great most " +
    "starred star stars famous well known trending open source opensource open-source on in at from github repo repos repository " +
    "repositories library libraries project projects package packages please can could would you i want need that which what are " +
    "is of to with written there give get alternatives alternative some me? me. for? a? some? any? lists list? options using use " +
    "used do does tell about one ones something"
  ).split(" "),
);

const COMMITS = /\b(commits?|commit history|recent changes|latest changes|what changed|history)\b/i;
const PULLS = /\b(pull requests?|prs?|merge requests?)\b/i;
const ISSUES = /\b(issues?|bugs?|bug reports?)\b/i;
const RELEASES = /\b(releases?|latest version|changelog|release notes)\b/i;
const CONTRIB = /\b(contributors?|maintainers?|who (?:wrote|maintains|built))\b/i;
const TREE = /\b(file tree|folder structure|directory structure|project structure|files in|structure of|tree)\b/i;

function repoRefs(text: string): RepoRef[] {
  const out: RepoRef[] = [];
  const add = (owner: string, repo: string) => {
    repo = repo.replace(/\.git$/, "").replace(/[.,;:]+$/, "");
    if (!repo || out.some((r) => r.owner.toLowerCase() === owner.toLowerCase() && r.repo.toLowerCase() === repo.toLowerCase())) return;
    out.push({ owner, repo });
  };
  for (const m of text.matchAll(URL_REF)) {
    if (["orgs", "topics", "search", "settings", "features", "marketplace", "sponsors", "collections"].includes(m[1].toLowerCase())) continue;
    add(m[1], m[2]);
  }
  if (GH_WORDS.test(text)) {
    const noUrls = text.replace(/https?:\/\/\S+/g, " ");
    for (const m of noUrls.matchAll(BARE_REF)) {
      const [owner, repo] = [m[1], m[2]];
      if (/^\d+$/.test(owner) || /^\d+$/.test(repo)) continue;
      if (NOT_REPO.has(owner.toLowerCase()) || NOT_REPO.has(repo.toLowerCase())) continue;
      if (owner.length < 2) continue;
      add(owner, repo);
    }
  }
  return out.slice(0, 2);
}

function searchQuery(text: string): { q: string; sort?: "stars" } | null {
  let lang: string | null = null;
  const terms: string[] = [];
  for (const raw of text.toLowerCase().replace(/https?:\/\/\S+/g, " ").split(/[\s,!?;:()"'`]+/)) {
    const w = raw.replace(/^[.]+|[.]+$/g, "");
    if (!w) continue;
    if (LANGS[w]) {
      lang ??= LANGS[w];
      continue;
    }
    if (STOP.has(w) || w.length < 2) continue;
    // "databases" -> "database": GitHub search does not stem.
    terms.push(w.length > 4 && w.endsWith("s") && !/(ss|is|us|os)$/.test(w) ? (w.endsWith("ies") ? `${w.slice(0, -3)}y` : w.slice(0, -1)) : w);
  }
  const q = terms.slice(0, 6).join(" ");
  if (!q) return null;
  return { q: lang ? `${q} language:${lang}` : q, sort: POPULAR.test(text) ? "stars" : undefined };
}

export function githubIntent(text: string): GithubIntent | null {
  const t = (text ?? "").slice(0, 800);
  if (!t.trim()) return null;
  const repos = repoRefs(t);
  let search: GithubIntent["search"] = null;
  if (repos.length === 0) {
    const wantsSearch = (STRONG.test(t) && FINDISH.test(t)) || FIND_LIB.test(t);
    if (!wantsSearch) return null;
    search = searchQuery(t);
    if (!search) return null;
  }
  return {
    repos,
    search,
    commits: COMMITS.test(t),
    pulls: PULLS.test(t),
    issues: ISSUES.test(t) && !PULLS.test(t),
    releases: RELEASES.test(t),
    contributors: CONTRIB.test(t),
    tree: TREE.test(t),
  };
}

const n = (v: number | null | undefined) => (v == null ? "?" : v >= 1000 ? `${(v / 1000).toFixed(v >= 10_000 ? 0 : 1)}k` : String(v));
const day = (iso: string | null | undefined) => (iso ? iso.slice(0, 10) : "?");

export type GithubGrounding = { items: ContextItem[]; hint: string | null };

/** Fetches the GitHub sources for [text]; null when it is not about GitHub. */
export async function githubGround(text: string, signal?: AbortSignal): Promise<GithubGrounding | null> {
  if (!githubEnabled()) return null;
  const intent = githubIntent(text);
  if (!intent) return null;
  const items: ContextItem[] = [];
  const push = (title: string, url: string, body: string) => items.push({ id: `G${items.length + 1}`, title, url, text: body });
  const blocks: string[] = [];

  if (intent.search) {
    const { q, sort } = intent.search;
    try {
      const res = await svc.searchRepos(q, sort, 6, signal);
      for (const r of res.items) {
        push(
          `${r.fullName} (GitHub, ${n(r.stars)} stars)`,
          r.url,
          [
            r.description,
            `Stars: ${r.stars}. Forks: ${r.forks}. Open issues: ${r.openIssues}. Language: ${r.language ?? "n/a"}. License: ${r.license ?? "n/a"}.`,
            r.topics.length ? `Topics: ${r.topics.join(", ")}.` : "",
            `Last push: ${day(r.pushedAt)}.${r.archived ? " Archived." : ""}${r.homepage ? ` Homepage: ${r.homepage}` : ""}`,
          ]
            .filter(Boolean)
            .join("\n"),
        );
      }
      if (res.items.length) blocks.push(`\`\`\`github-search\ntype: repos\nq: ${q}${sort ? "\nsort: stars" : ""}\n\`\`\``);
    } catch (e) {
      log.warn("github search failed", { message: (e as Error).message.slice(0, 120) });
    }
  }

  for (const { owner, repo } of intent.repos) {
    let full = `${owner}/${repo}`;
    try {
      const d = await svc.repoDetail(owner, repo, signal);
      full = d.fullName;
      push(
        `${d.fullName} (GitHub repository)`,
        d.url,
        [
          d.description,
          `Stars: ${d.stars}. Forks: ${d.forks}. Watchers: ${d.watchers ?? "?"}. Open issues and PRs: ${d.openIssues}. Default branch: ${d.defaultBranch}. License: ${d.license ?? "n/a"}.`,
          d.languages.length ? `Languages: ${d.languages.map((l) => `${l.name} ${l.pct}%`).join(", ")}.` : "",
          d.topics.length ? `Topics: ${d.topics.join(", ")}.` : "",
          d.latestRelease ? `Latest release: ${d.latestRelease.name} (${day(d.latestRelease.publishedAt)}).` : "",
          `Created ${day(d.createdAt)}, last push ${day(d.pushedAt)}.${d.archived ? " Archived." : ""}`,
          d.readme ? `README excerpt:\n${d.readme.slice(0, 900)}` : "",
        ]
          .filter(Boolean)
          .join("\n"),
      );
    } catch (e) {
      // A bare "word/word" that is not a repository: not GitHub after all.
      log.info("github repo skipped", { repo: `${owner}/${repo}`, message: (e as Error).message.slice(0, 80) });
      continue;
    }
    const [o, r] = full.split("/");
    const extra: Promise<void>[] = [];
    if (intent.commits) {
      extra.push(
        svc.commits(o, r, { perPage: 10, stats: false }, signal).then((list) => {
          push(
            `Recent commits in ${full}`,
            `https://github.com/${full}/commits`,
            list.map((c) => `${c.shortSha} ${day(c.date)} ${c.author?.login ?? c.authorName}: ${c.message}`).join("\n"),
          );
        }),
      );
    }
    if (intent.pulls) {
      extra.push(
        svc.pulls(o, r, "open", 10).then((p) => {
          push(
            `Open pull requests in ${full}`,
            `https://github.com/${full}/pulls`,
            p.items.map((i) => `#${i.number} [${i.state}] ${i.title} (by ${i.user?.login ?? "?"}, updated ${day(i.updatedAt)})`).join("\n"),
          );
        }),
      );
    }
    if (intent.issues) {
      extra.push(
        svc.issues(o, r, "open", 10).then((p) => {
          push(
            `Open issues in ${full}`,
            `https://github.com/${full}/issues`,
            p.items.map((i) => `#${i.number} ${i.title}${i.labels.length ? ` [${i.labels.map((l) => l.name).join(", ")}]` : ""} (${i.comments ?? 0} comments, updated ${day(i.updatedAt)})`).join("\n"),
          );
        }),
      );
    }
    if (intent.releases) {
      extra.push(
        svc.releases(o, r, 5).then((p) => {
          push(
            `Releases of ${full}`,
            `https://github.com/${full}/releases`,
            p.items.map((i) => `${i.name} (${day(i.publishedAt)})${i.prerelease ? " prerelease" : ""}: ${i.body.slice(0, 200).replace(/\n+/g, " ")}`).join("\n"),
          );
        }),
      );
    }
    if (intent.contributors) {
      extra.push(
        svc.contributors(o, r, 10).then((p) => {
          push(`Top contributors of ${full}`, `https://github.com/${full}/graphs/contributors`, p.items.map((c) => `${c.login}: ${c.contributions} commits`).join("\n"));
        }),
      );
    }
    await Promise.allSettled(extra);
    if (intent.commits) blocks.push(`\`\`\`github-commits\n${full}\n\`\`\``);
    else if (intent.pulls) blocks.push(`\`\`\`github-prs\n${full} open\n\`\`\``);
    else if (intent.issues) blocks.push(`\`\`\`github-issues\n${full} open\n\`\`\``);
    else if (intent.tree) blocks.push(`\`\`\`github-tree\n${full}\n\`\`\``);
    else blocks.push(`\`\`\`github-repo\n${full}\n\`\`\``);
  }

  if (!items.length) return null;
  const hint =
    "GitHub: the <github> block holds live GitHub API data for this question; cite it with its [G#] tags. " +
    (blocks.length
      ? `Right after your opening sentence, include this live card exactly as written (the app renders it with fresh data), then continue with your answer (for lists of commits, PRs or issues: a short summary of 3-5 notable items citing [G#], no table that repeats the card); do not add any other github-* card:\n${blocks[0]}`
      : "");
  return { items, hint };
}
