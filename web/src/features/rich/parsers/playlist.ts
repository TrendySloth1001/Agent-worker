import { z } from "zod";
import { readKeyed, splitLines } from "../lib/text";

const MAX_TRACKS = 12;

const clip = (value: string, max: number) => value.replace(/\s+/g, " ").trim().slice(0, max);

const playlistSchema = z.object({
  title: z.string().min(1).max(80),
  app: z.string().max(30).optional(),
  items: z
    .array(z.object({ title: z.string().min(1).max(90), artist: z.string().max(70) }))
    .min(1)
    .max(MAX_TRACKS),
});
export type PlaylistData = z.infer<typeof playlistSchema>;
export type PlaylistSong = PlaylistData["items"][number];

export function parsePlaylist(code: string): PlaylistData | null {
  let title = "";
  let app: string | undefined;
  const items: PlaylistSong[] = [];
  for (const raw of splitLines(code)) {
    const line = raw.trim();
    if (!line) continue;
    const name = readKeyed(line, "title");
    const player = readKeyed(line, "app");
    if (name !== null) title = clip(name, 80);
    else if (player !== null)
      app = clip(player, 30).toLowerCase().replace(/\s+/g, "_") || undefined;
    else {
      const song = /^(?:[-*•]|\d{1,2}[.)])?\s*(.+?)\s*\|\s*(.*)$/.exec(line);
      if (song && items.length < MAX_TRACKS)
        items.push({ title: clip(song[1] ?? "", 90), artist: clip(song[2] ?? "", 70) });
    }
  }
  const result = playlistSchema.safeParse({ title: title || "Playlist", app, items });
  return result.success ? result.data : null;
}

const trackSchema = z.object({
  title: z.string(),
  artist: z.string(),
  art: z.string().optional(),
  durationMs: z.number().optional(),
  previewUrl: z.string().optional(),
  album: z.string().optional(),
  year: z.number().optional(),
  link: z.string().optional(),
});
export type PlaylistTrack = z.infer<typeof trackSchema>;

export const enrichResponseSchema = z.object({ tracks: z.array(trackSchema) });
export const youtubeResponseSchema = z.object({
  ids: z.array(z.string().nullable()),
  playAll: z.string().nullable(),
});
