import { Router } from "express";
import { z } from "zod";
import { AppError } from "../util/errors.js";
import { researchWeb } from "../web/pipeline.js";
import { enrichTracks, MAX_TRACKS, resolvePlayAll, type YoutubeSearch } from "../context/playlist.js";

export const playlistRouter = Router();

const songs = z.object({
  items: z
    .array(z.object({ title: z.string().trim().min(1).max(120), artist: z.string().trim().max(100).default("") }))
    .min(1)
    .max(MAX_TRACKS),
});

function parse(body: unknown) {
  const r = songs.safeParse(body);
  if (!r.success) throw new AppError(400, "bad_request", `items must be 1-${MAX_TRACKS} songs with a title`);
  return r.data.items;
}

// Covers, durations and 30 s previews for the playlist card (iTunes Search, no key; cached).
playlistRouter.post("/enrich", async (req, res) => {
  const tracks = await enrichTracks(parse(req.body), { signal: AbortSignal.timeout(15_000) });
  res.setHeader("Cache-Control", "private, max-age=3600");
  res.json({ tracks });
});

const search: YoutubeSearch = (query, signal) =>
  researchWeb({ question: query, preplanned: { queries: [query], fresh: null }, maxResults: 6, fetchTop: 0, signal }).then((r) => r.map((x) => ({ url: x.url, title: x.title })));

// YouTube video ids and the "Play all" link (keyless web search scoped to youtube.com; cached).
playlistRouter.post("/youtube", async (req, res) => {
  const out = await resolvePlayAll(parse(req.body), { search, signal: AbortSignal.timeout(25_000) });
  res.setHeader("Cache-Control", "private, max-age=3600");
  res.json(out);
});
