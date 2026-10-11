import type { ContextItem } from "../prompts/system.js";
import { log } from "../util/logger.js";
import { gh, ghAuth } from "./client.js";
import * as svc from "./service.js";
import { graph as commitGraph } from "./graph.js";

/**
 * GitHub grounding for chat: when the user's message is clearly about GitHub
 * (a github.com link, an owner/repo next to repo words, or "find a repo /
 * library for X"), live GitHub data is fetched and added as [G#] sources.
 * Pure regex intent, so unrelated questions never trigger API calls.
 *
 * Personal questions ("my repos", "my PRs", "my GitHub activity") use the
 * caller's connected GitHub account (the owner may fall back to the server
 * token). Without one, and for "connect my GitHub", the reply is the
 * ```github-connect``` card instead of a guess.
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
  /** "git graph", "branch history", "how did the branches merge". */
  graph: boolean;
  /** "review this PR" with a PR link or owner/repo#n. */
  review: (RepoRef & { number: number }) | null;
  /** A pull request named by link or owner/repo#n (without a review ask). */
  pr: (RepoRef & { number: number }) | null;
  /** "my repos", "my private repos": the token owner's repositories. */
  mine: { visibility: "all" | "private" | "public" } | null;
  /** "my repo X": a repository of the token owner, by name only. */
  myRepo: string | null;
  /** "my PRs", "PRs waiting for my review". */
  myPulls: boolean;
  /** "my GitHub issues", "issues assigned to me". */
  myIssues: boolean;
  /** "my recent GitHub activity", "my commits". */
  myActivity: boolean;
};

const URL_REF = /github\.com\/([A-Za-z0-9][\w-]{0,38})\/([\w.-]{1,100})/gi;
const BARE_REF = /(?<![\w./@:-])([A-Za-z0-9][\w-]{0,38})\/([A-Za-z0-9_.-]{1,100})(?![\w/])/g;
const GH_WORDS =
  /\b(github|gh|repos?|repositor(?:y|ies)|git graph|(?:branch|commit) graph|commits?|commit history|pull requests?|prs?|issues?|releases?|branch(?:es)?|contributors?|maintainers?|stars?|forks?|source code|codebase|readme|file tree|changelog)\b/i;
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
const PR_URL = /github\.com\/([A-Za-z0-9][\w-]{0,38})\/([\w.-]{1,100})\/pull\/(\d{1,7})/i;
const PR_HASH = /(?<![\w./@:-])([A-Za-z0-9][\w-]{0,38})\/([A-Za-z0-9_.-]{1,100})#(\d{1,7})\b/;
const REVIEW = /\b(review|code[- ]review|critique|audit|look (?:over|at the (?:diff|changes))|any (?:bugs|issues|problems) in|is (?:it|this) (?:safe|ok|good) to merge)\b/i;
const MINE = /\b(?:my|mine|i own|i have)\b[^.?!\n]{0,24}\b(repos?|repositor(?:y|ies)|projects? on github|github projects?)\b/i;
const MY_REPO_NAMED = /\bmy\s+(?:own\s+)?(?:private\s+|public\s+)?(?:github\s+)?(?:repo|repository|project)\s+(?:called\s+|named\s+)?[`"']?([A-Za-z0-9_.-]{2,100})/i;
const MY_REPO_STOP = new Set(["list", "and", "or", "on", "in", "with", "that", "which", "is", "are", "the", "a", "for", "to", "from", "please", "github"]);
const MY_PULLS =
  /\bmy\s+(?:own\s+|open\s+|recent\s+|latest\s+|pending\s+)?(?:github\s+)?(?:prs|pull requests)\b|\b(?:prs?|pull requests?)\b[^.?!\n]{0,30}\b(?:i (?:opened|authored|created|made|submitted)|assigned to me|(?:waiting )?for my review|requested? (?:my review|me)|review requests?)\b|\bmy review requests\b/i;
const MY_ISSUES =
  /\bmy\s+(?:open\s+|recent\s+)?github\s+issues\b|\bissues\b[^.?!\n]{0,30}\b(?:assigned to me|i (?:opened|created|filed|reported))\b/i;
const MY_ACTIVITY =
  /\bmy\s+(?:(?:recent|latest)\s+(?:github\s+)?|github\s+)(?:activity|contributions|commits|pushes)\b|\bwhat (?:have|did) i (?:been )?(?:working on|work on|push(?:ed)?|commit(?:ted)?)\b[^.?!\n]{0,30}\b(?:github|lately|recently|this week)\b/i;
const MY_GITHUB = /\bmy\s+(?:github|gh)(?:\s+(?:account|profile|code|stuff|projects?))?\b|\bmy code on github\b/i;
/** "connect my GitHub", "link github", "sign in to GitHub" (not "connect GitHub Actions to AWS"). */
const CONNECT =
  /\b(?:re-?)?(?:connect|link|hook up|authori[sz]e|integrate|log ?in|sign ?in|set up|setup|add)\s+(?:(?:to|with|into)\s+)?(?:my\s+)?git ?hub(?:\s+account)?\b/i;
const CONNECT_NOT =
  /^\s*(?:actions?|pages|copilot|codespaces?|webhooks?|apps?|packages|ci|repo|repository|repositories|cli|desktop|sso|oauth|ssh|keys?)\b|^\s*(?:to|with|into|and)\s+(?!(?:you|sparky|this app|the app|here|this chat|chat)\b)\w/i;
const GRAPH =
  /\b(git ?graph|(?:branch|commit|merge) (?:graph|history|tree)|branch(?:ing)? history|how (?:did|do|were|have) (?:the |its |these |those )?branch(?:es)? (?:get |been )?merg(?:e|ed|ing)|how (?:the )?branches merged?)\b/i;
const TREE = /\b(file tree|folder structure|directory structure|project structure|files in|structure of|tree)\b/i;

/** "connect my GitHub": show the connect card. */
export function wantsGithubConnect(text: string): boolean {
  const t = (text ?? "").slice(0, 400);
  const m = t.match(CONNECT);
  if (!m) return false;
  return !CONNECT_NOT.test(t.slice((m.index ?? 0) + m[0].length));
}

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

function prRef(text: string): (RepoRef & { number: number }) | null {
  const m = text.match(PR_URL) ?? text.match(PR_HASH);
  if (!m) return null;
  return { owner: m[1], repo: m[2].replace(/\.git$/, ""), number: Number(m[3]) };
}

export function githubIntent(text: string): GithubIntent | null {
  const t = (text ?? "").slice(0, 800);
  if (!t.trim()) return null;
  const pr = prRef(t);
  const review = pr && REVIEW.test(t) ? pr : null;
  const named = t.match(MY_REPO_NAMED)?.[1]?.replace(/[.,;:]+$/, "") ?? null;
  const myRepo = named && !MY_REPO_STOP.has(named.toLowerCase()) && !/^repos?$/i.test(named) ? named : null;
  const myPulls = MY_PULLS.test(t);
  const myIssues = !myPulls && MY_ISSUES.test(t);
  const myActivity = MY_ACTIVITY.test(t);
  const mine =
    !myRepo && (MINE.test(t) || (MY_GITHUB.test(t) && !myPulls && !myIssues && !myActivity))
      ? { visibility: /\bprivate\b/i.test(t) ? ("private" as const) : /\bpublic\b/i.test(t) ? ("public" as const) : ("all" as const) }
      : null;
  const repos = repoRefs(t.replace(/#\d+/g, ""));
  if (pr && !repos.some((r) => r.owner.toLowerCase() === pr.owner.toLowerCase() && r.repo.toLowerCase() === pr.repo.toLowerCase())) {
    repos.unshift({ owner: pr.owner, repo: pr.repo });
  }
  let search: GithubIntent["search"] = null;
  const personal = !!mine || !!myRepo || myPulls || myIssues || myActivity;
  if (repos.length === 0 && !personal) {
    const wantsSearch = (STRONG.test(t) && FINDISH.test(t)) || FIND_LIB.test(t);
    if (!wantsSearch) return null;
    search = searchQuery(t);
    if (!search) return null;
  }
  return {
    repos,
    search,
    commits: COMMITS.test(t),
    pulls: PULLS.test(t) && !myPulls,
    issues: ISSUES.test(t) && !PULLS.test(t) && !myIssues,
    releases: RELEASES.test(t),
    contributors: CONTRIB.test(t),
    tree: TREE.test(t),
    graph: GRAPH.test(t),
    review,
    pr: review ? null : pr,
    mine,
    myRepo,
    myPulls,
    myIssues,
    myActivity,
  };
}

const CONNECT_BLOCK = "```github-connect\ngithub\n```";

const n = (v: number | null | undefined) => (v == null ? "?" : v >= 1000 ? `${(v / 1000).toFixed(v >= 10_000 ? 0 : 1)}k` : String(v));
const day = (iso: string | null | undefined) => (iso ? iso.slice(0, 10) : "?");

export type GithubGrounding = { items: ContextItem[]; hint: string | null };

type Push = (title: string, url: string, body: string) => void;

/** The caller's own PRs, issues and recent activity. */
async function personalSources(intent: GithubIntent, login: string, push: Push, blocks: string[], signal?: AbortSignal) {
  const tasks: Promise<void>[] = [];
  const issueLine = (i: Awaited<ReturnType<typeof svc.searchIssues>>["items"][number]) =>
    `${i.repo}#${i.number} [${i.state}] ${i.title} (updated ${day(i.updatedAt)})`;
  if (intent.myPulls) {
    const authored = `is:pr author:${login} is:open archived:false`;
    tasks.push(
      Promise.all([svc.searchIssues(authored, 15), svc.searchIssues(`is:pr review-requested:${login} is:open archived:false`, 10)]).then(([mine, review]) => {
        push(
          `Open pull requests by ${login} (GitHub)`,
          `https://github.com/pulls?q=${encodeURIComponent(authored)}`,
          [`${mine.total} open PRs authored by ${login}.`, ...mine.items.map(issueLine)].join("\n"),
        );
        push(
          `Pull requests waiting for ${login}'s review (GitHub)`,
          "https://github.com/pulls/review-requested",
          [`${review.total} open PRs request ${login}'s review.`, ...review.items.map(issueLine)].join("\n"),
        );
        blocks.push(`\`\`\`github-search\ntype: issues\nq: ${authored}\n\`\`\``);
      }),
    );
  }
  if (intent.myIssues) {
    const assigned = `is:issue assignee:${login} is:open archived:false`;
    tasks.push(
      Promise.all([svc.searchIssues(assigned, 15), svc.searchIssues(`is:issue author:${login} is:open archived:false`, 10)]).then(([a, b]) => {
        push(`Open issues assigned to ${login} (GitHub)`, `https://github.com/issues/assigned`, [`${a.total} open.`, ...a.items.map(issueLine)].join("\n"));
        push(`Open issues opened by ${login} (GitHub)`, `https://github.com/issues/created`, [`${b.total} open.`, ...b.items.map(issueLine)].join("\n"));
        blocks.push(`\`\`\`github-search\ntype: issues\nq: ${assigned}\n\`\`\``);
      }),
    );
  }
  if (intent.myActivity) {
    tasks.push(
      gh<any[]>(`/users/${encodeURIComponent(login)}/events?per_page=40`, { ttlMs: 60_000, signal }).then((events) => {
        const lines = (Array.isArray(events) ? events : []).map(eventLine).filter(Boolean).slice(0, 30);
        push(`Recent GitHub activity of ${login}`, `https://github.com/${login}`, lines.join("\n") || "No recent public or private events.");
      }),
    );
  }
  const results = await Promise.allSettled(tasks);
  for (const r of results) if (r.status === "rejected") log.warn("github personal source failed", { message: String(r.reason?.message ?? r.reason).slice(0, 120) });
}

function eventLine(e: any): string {
  const repo = e?.repo?.name ?? "?";
  const when = day(e?.created_at);
  const p = e?.payload ?? {};
  switch (e?.type) {
    case "PushEvent": {
      const msgs = (p.commits ?? []).slice(0, 3).map((c: any) => String(c.message ?? "").split("\n")[0].slice(0, 80));
      return `${when} pushed ${p.size ?? p.commits?.length ?? "?"} commit(s) to ${repo}${p.ref ? ` (${String(p.ref).replace("refs/heads/", "")})` : ""}${msgs.length ? `: ${msgs.join("; ")}` : ""}`;
    }
    case "PullRequestEvent":
      return `${when} ${p.action} PR ${repo}#${p.number ?? p.pull_request?.number}: ${p.pull_request?.title ?? ""}`;
    case "PullRequestReviewEvent":
      return `${when} reviewed PR ${repo}#${p.pull_request?.number}: ${p.pull_request?.title ?? ""}`;
    case "IssuesEvent":
      return `${when} ${p.action} issue ${repo}#${p.issue?.number}: ${p.issue?.title ?? ""}`;
    case "IssueCommentEvent":
      return `${when} commented on ${repo}#${p.issue?.number}: ${p.issue?.title ?? ""}`;
    case "CreateEvent":
      return `${when} created ${p.ref_type}${p.ref ? ` ${p.ref}` : ""} in ${repo}`;
    case "ReleaseEvent":
      return `${when} ${p.action} release ${p.release?.tag_name ?? ""} in ${repo}`;
    case "WatchEvent":
      return `${when} starred ${repo}`;
    case "ForkEvent":
      return `${when} forked ${repo}`;
    default:
      return "";
  }
}

/** Fetches the GitHub sources for [text]; null when it is not about GitHub. */
export async function githubGround(text: string, signal?: AbortSignal): Promise<GithubGrounding | null> {
  const auth = await ghAuth();
  const canSeePrivate = !auth.publicOnly;
  const intent = githubIntent(text);

  if (wantsGithubConnect(text)) {
    return {
      items: [],
      hint:
        auth.kind === "user"
          ? `GitHub: the user's GitHub account is already connected as @${auth.login}. Say so in one short sentence and include this card on its own line (it shows the connection and lets them disconnect); write nothing after it:\n${CONNECT_BLOCK}`
          : "GitHub: the user wants to connect their GitHub account. Reply with one short sentence (connecting lets you read their repositories, pull requests and issues, private ones included, with their permission), then include this card on its own line; it runs the sign-in in the app. Write nothing after the card:\n" +
            CONNECT_BLOCK,
    };
  }
  if (!intent) return null;
  const personal = !!intent.mine || !!intent.myRepo || intent.myPulls || intent.myIssues || intent.myActivity;
  if (personal && !canSeePrivate) {
    return {
      items: [],
      hint:
        "GitHub: the user asked about their own GitHub data (their repositories, code, pull requests, issues or activity), but has not connected a GitHub account, so you cannot see it. Do not guess, list or invent repositories. Say in one short sentence that they need to connect GitHub first, then include this card on its own line and write nothing after it:\n" +
        CONNECT_BLOCK,
    };
  }
  if (auth.kind === "none") return null;
  const items: ContextItem[] = [];
  const push = (title: string, url: string, body: string) => items.push({ id: `G${items.length + 1}`, title, url, text: body });
  const blocks: string[] = [];

  // "my repos" / "my private repo X" / "my PRs": resolved against the caller's
  // connected account (or, for the owner, the server token's account).
  if (personal && canSeePrivate) {
    try {
      const me = await svc.me(signal);
      await personalSources(intent, me.login, push, blocks, signal);
      if (intent.myRepo && !intent.repos.some((r) => r.repo.toLowerCase() === intent.myRepo!.toLowerCase())) {
        const list = await svc.myRepos({ visibility: "all", sort: "updated", perPage: 100 }, signal).catch(() => null);
        const hit = list?.items.find((r) => r.name.toLowerCase() === intent.myRepo!.toLowerCase());
        const [o, r] = (hit?.fullName ?? `${me.login}/${intent.myRepo}`).split("/");
        intent.repos.unshift({ owner: o, repo: r });
        intent.repos.splice(2);
      }
      if (intent.mine) {
        const list = await svc.myRepos({ visibility: intent.mine.visibility, sort: "updated", perPage: 30 }, signal);
        push(
          `Repositories of ${me.login} (${intent.mine.visibility}, GitHub)`,
          `https://github.com/${me.login}?tab=repositories`,
          [
            `Signed in as ${me.login}. Public repos: ${me.publicRepos}. Private repos: ${me.privateRepos ?? "not visible to this token"}.`,
            ...list.items.map(
              (r) =>
                `${r.fullName}${r.private ? " (private)" : ""}: ${r.description || "no description"}. ${r.language ?? "n/a"}, ${r.stars} stars, last push ${day(r.pushedAt)}.`,
            ),
          ].join("\n"),
        );
        blocks.push(`\`\`\`github-my-repos\n${intent.mine.visibility}\n\`\`\``);
      }
    } catch (e) {
      log.warn("github my repos failed", { message: (e as Error).message.slice(0, 120) });
    }
  }

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
      if (d.private && !canSeePrivate) continue;
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
    const pr = [intent.review, intent.pr].find((x) => x && x.owner.toLowerCase() === owner.toLowerCase() && x.repo.toLowerCase() === repo.toLowerCase());
    if (pr) {
      extra.push(
        svc.pull(o, r, pr.number).then((d) => {
          push(
            `Pull request ${full}#${d.number}: ${d.title}`,
            d.url,
            [
              `State: ${d.state}. By ${d.user?.login ?? "?"}. ${d.head} -> ${d.base}. ${d.commits} commits, ${d.changedFiles} files, +${d.additions} -${d.deletions}.`,
              d.body ? `Description:\n${d.body.slice(0, 1_200)}` : "",
              `Files: ${d.files.slice(0, 30).map((f) => `${f.filename} (+${f.additions} -${f.deletions})`).join(", ")}`,
            ]
              .filter(Boolean)
              .join("\n"),
          );
        }),
      );
    }
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
    if (intent.graph) {
      extra.push(
        commitGraph(o, r, { limit: 100 }, signal).then((g) => {
          const merges = g.commits.filter((c) => c.parents.length > 1).slice(0, 8);
          push(
            `Branch graph of ${full}`,
            `https://github.com/${full}/network`,
            [
              `Default branch: ${g.defaultBranch}. Branches shown: ${g.branches.map((b) => b.name).join(", ")}.`,
              `Last ${g.commits.length} commits, ${g.commits.filter((c) => c.parents.length > 1).length} merge commits.`,
              ...merges.map((c) => `merge ${c.sha.slice(0, 7)} ${day(c.date)} ${c.author}: ${c.subject}`),
            ].join("\n"),
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
    if (intent.review && pr === intent.review) blocks.push(`\`\`\`github-review\n${full}#${intent.review.number}\n\`\`\``);
    else if (intent.graph) blocks.push(`\`\`\`github-graph\n${full}\n\`\`\``);
    else if (intent.commits) blocks.push(`\`\`\`github-commits\n${full}\n\`\`\``);
    else if (intent.pulls) blocks.push(`\`\`\`github-prs\n${full} open\n\`\`\``);
    else if (intent.issues) blocks.push(`\`\`\`github-issues\n${full} open\n\`\`\``);
    else if (intent.tree) blocks.push(`\`\`\`github-tree\n${full}\n\`\`\``);
    else blocks.push(`\`\`\`github-repo\n${full}\n\`\`\``);
  }

  if (!items.length) return null;
  const reviewHint = intent.review
    ? " The review card runs a full AI code review of the diff in the app (it takes a minute): introduce it in one or two sentences from the PR source (what the PR changes), do not write your own line-by-line review."
    : "";
  const hint =
    "GitHub: the <github> block holds live GitHub API data for this question; cite it with its [G#] tags. " +
    (blocks.length
      ? `Right after your opening sentence, include this live card exactly as written (the app renders it with fresh data), then continue with your answer (for lists of commits, PRs or issues: a short summary of 3-5 notable items citing [G#], no table that repeats the card); do not add any other github-* card:\n${blocks[0]}`
      : "") +
    reviewHint;
  return { items, hint };
}
