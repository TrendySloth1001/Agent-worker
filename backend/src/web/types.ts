/** `content` is the short text given to the model; `full` is the longer page text kept only for matching citations to their supporting passage. */
export type WebResult = { title: string; url: string; content: string; full?: string; source?: string; published?: string };

export type Freshness = "breaking" | "recent" | "evergreen";
export type Intent = "news" | "code" | "repo" | "academic" | "discussion" | "encyclopedic";

/** One raw hit from a provider, before merging. `text` is substantive body text (not just a snippet). */
export type Candidate = {
  title: string;
  url: string;
  snippet: string;
  text?: string;
  source: string;
  /** 0-based position in that provider's own ranking. */
  rank: number;
  published?: string;
};

export type SearchCtx = { signal?: AbortSignal; fresh: Freshness; limit: number };
