/**
 * `content` is the short text given to the model; `full` is the longer page text kept only for matching citations to their supporting passage.
 * `site` is the page's host (no www), used for the citation's label and favicon.
 */
export type WebResult = { title: string; url: string; content: string; full?: string; source?: string; published?: string; site?: string };

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

export type SearchCtx = { signal?: AbortSignal; fresh: Freshness; limit: number; /** BCP-47-ish language of the query ("hi" for Devanagari), when not English. */ lang?: string;
  /** Lower-case ISO country code to bias engines toward (only on location-relevant turns). */
  region?: string };
