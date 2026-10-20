import {
  enrichResponseSchema,
  youtubeResponseSchema,
  type PlaylistSong,
  type PlaylistTrack,
} from "../parsers/playlist";

const BASE = "/api/sparky/playlist";

export const playlistKeys = {
  tracks: (items: readonly PlaylistSong[]) =>
    ["playlist", "tracks", JSON.stringify(items)] as const,
  playAll: (items: readonly PlaylistSong[]) =>
    ["playlist", "youtube", JSON.stringify(items)] as const,
};

async function post(
  path: string,
  items: readonly PlaylistSong[],
  fetcher: typeof fetch,
): Promise<unknown> {
  const response = await fetcher(`${BASE}/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ items }),
  });
  if (!response.ok) throw new Error(`playlist ${path} failed (${response.status})`);
  return response.json();
}

export async function fetchTracks(
  items: readonly PlaylistSong[],
  fetcher: typeof fetch = fetch,
): Promise<PlaylistTrack[]> {
  return enrichResponseSchema.parse(await post("enrich", items, fetcher)).tracks;
}

export async function fetchPlayAll(
  items: readonly PlaylistSong[],
  fetcher: typeof fetch = fetch,
): Promise<string | null> {
  return youtubeResponseSchema.parse(await post("youtube", items, fetcher)).playAll;
}
