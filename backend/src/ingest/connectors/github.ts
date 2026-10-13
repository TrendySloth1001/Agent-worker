import { AppError } from "../../util/errors.js";
import { config } from "../../config.js";
import { fetchJson, fetchText } from "../fetcher.js";
import type { Connector } from "../types.js";

const MAX_FILE_BYTES = 100_000;
const DOC_EXT = /\.(md|mdx|markdown|rst|adoc)$/i;
const CODE_EXT: Record<string, string> = {
  ts: "typescript", tsx: "tsx", js: "javascript", jsx: "jsx", mjs: "javascript", py: "python", go: "go", rs: "rust",
  java: "java", kt: "kotlin", swift: "swift", dart: "dart", rb: "ruby", php: "php", c: "c", h: "c", cpp: "cpp", cs: "csharp",
  sh: "bash", sql: "sql", yaml: "yaml", yml: "yaml", toml: "toml",
};
const SKIP = /(^|\/)(fixtures?|__fixtures__|testdata|node_modules|dist|build|vendor|third_party|\.git|\.github\/workflows|__pycache__|coverage|\.next|target)\//i;
const SKIP_FILE = /(\.min\.|\.lock$|-lock\.|lock\.json$|\.map$|\.snap$|\.d\.ts$|package-lock|pnpm-lock|yarn\.lock|CHANGELOG|LICENSE|\.generated\.)/i;

const ghHeaders = (): Record<string, string> => ({
  Accept: "application/vnd.github+json",
  "X-GitHub-Api-Version": "2022-11-28",
  ...(config.githubToken ? { Authorization: `Bearer ${config.githubToken}` } : {}),
});

function parse(input: string): { owner: string; repo: string; branch?: string; path?: string } {
  const s = input.trim().replace(/\.git$/, "");
  let m = s.match(/^(?:https?:\/\/(?:www\.)?github\.com\/)?([\w-]+)\/([\w.-]+?)(?:\/(?:tree|blob)\/([^/]+)(?:\/(.+?))?)?\/?$/);
  if (!m) throw new AppError(400, "bad_request", "Enter a repository like owner/repo or paste its GitHub link.");
  return { owner: m[1], repo: m[2], branch: m[3], path: m[4]?.replace(/\/$/, "") };
}

function priority(p: string): number {
  const base = p.split("/").pop()!;
  const depth = p.split("/").length - 1;
  if (/^readme/i.test(base) && depth === 0) return 0;
  if (/^(docs?|documentation)\//i.test(p) && DOC_EXT.test(p)) return 10 + depth;
  if (DOC_EXT.test(p)) return 30 + depth;
  return 50 + depth * 2 + (/(^|\/)(test|tests|__tests__|spec|examples?)\//i.test(p) ? 20 : 0);
}

export const github: Connector = {
  async resolve(input) {
    const { owner, repo, branch, path } = parse(input);
    const uri = `${owner}/${repo}${branch ? `/tree/${branch}${path ? `/${path}` : ""}` : ""}`;
    return { uri, title: `${owner}/${repo}`, options: { owner, repo, branch, path } };
  },

  async run(source, ctx) {
    const { owner, repo, branch: wantBranch, path: sub } = parse(source.uri);
    const api = `https://api.github.com/repos/${owner}/${repo}`;
    let meta: { default_branch: string; description: string | null; full_name: string };
    try {
      meta = (await fetchJson(api, { headers: ghHeaders() })).data;
    } catch (e) {
      const st = (e as { status?: number }).status;
      if (st === 404) throw new AppError(502, "upstream_failed", "Couldn't find that repository — it may be private.");
      if (st === 403 || st === 429) throw new AppError(502, "upstream_failed", "GitHub needs a short break — try again in a few minutes.");
      throw e;
    }
    ctx.setTitle(meta.full_name);
    const branch = wantBranch ?? meta.default_branch;
    const br = (await fetchJson<{ commit: { sha: string } }>(`${api}/branches/${encodeURIComponent(branch)}`, { headers: ghHeaders() })).data;
    const sha = br.commit.sha;
    const tree = (await fetchJson<{ tree: Array<{ path: string; type: string; size?: number }>; truncated?: boolean }>(`${api}/git/trees/${sha}?recursive=1`, { headers: ghHeaders() })).data;

    const files = tree.tree
      .filter((f) => f.type === "blob" && (f.size ?? 0) > 0 && (f.size ?? 0) <= MAX_FILE_BYTES)
      .filter((f) => !sub || f.path === sub || f.path.startsWith(`${sub}/`))
      .filter((f) => !SKIP.test(`/${f.path}`) && !SKIP_FILE.test(f.path))
      .filter((f) => DOC_EXT.test(f.path) || CODE_EXT[f.path.split(".").pop()!.toLowerCase()] !== undefined || /^readme/i.test(f.path.split("/").pop()!))
      .sort((a, b) => priority(a.path) - priority(b.path) || a.path.localeCompare(b.path))
      .slice(0, Math.min(ctx.limit, 300));

    if (!files.length) throw new AppError(502, "upstream_failed", "No documentation or source files found in this repository");
    ctx.setTotal(files.length);

    for (const f of files) {
      try {
        const raw = await fetchText(`https://raw.githubusercontent.com/${owner}/${repo}/${sha}/${f.path.split("/").map(encodeURIComponent).join("/")}`, {
          delayMs: 50,
          anyType: true,
        });
        const ext = f.path.split(".").pop()!.toLowerCase();
        const isDoc = DOC_EXT.test(f.path);
        const text = raw.body;
        let markdown: string;
        let title: string;
        if (isDoc && /\.(md|mdx|markdown)$/i.test(f.path)) {
          markdown = text;
          title = `${repo}/${f.path}`;
        } else if (isDoc) {
          markdown = `# ${f.path}\n\n${text}`;
          title = `${repo}/${f.path}`;
        } else {
          const fence = text.includes("```") ? "~~~~" : "```";
          markdown = `# ${f.path}\n\n${fence}${CODE_EXT[ext] ?? ""}\n${text.replace(/\n+$/, "")}\n${fence}`;
          title = `${repo}/${f.path}`;
        }
        await ctx.emit({
          url: `https://github.com/${owner}/${repo}/blob/${sha}/${f.path}`,
          title,
          markdown,
          meta: { path: f.path, sha, branch },
        });
      } catch (e) {
        ctx.skip((e as Error).message);
      }
    }
  },
};
