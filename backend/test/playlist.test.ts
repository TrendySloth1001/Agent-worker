import { test } from "node:test";
import assert from "node:assert/strict";
import {
  bigArt,
  convertSongList,
  detectSongList,
  enrichTracks,
  isMusicTurn,
  itunesUrl,
  lookupTrack,
  lookupYoutubeId,
  mapItunes,
  MAX_TRACKS,
  parsePlaylistBlock,
  parseSongLine,
  pickYoutubeId,
  playAllFor,
  playAllUrl,
  playlistBlock,
  playlistTitleFor,
  resetPlaylistCaches,
  resolvePlayAll,
  takeItunesSlot,
  type ItunesFetch,
} from "../src/context/playlist.js";
import { buildSystemPrompt, promptNeeds } from "../src/prompts/system.js";

// A trimmed real iTunes Search response (country=IN, entity=song).
const ITUNES = {
  resultCount: 2,
  results: [
    {
      wrapperType: "track",
      kind: "song",
      artistName: "Arijit Singh",
      collectionName: "Aashiqui 2 (Original Motion Picture Soundtrack)",
      trackName: "Tum Hi Ho",
      trackViewUrl: "https://music.apple.com/in/album/tum-hi-ho/1?i=2&uo=4",
      previewUrl: "https://audio-ssl.itunes.apple.com/itunes-assets/x/preview.m4a",
      artworkUrl100: "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/source/100x100bb.jpg",
      trackTimeMillis: 262_000,
      releaseDate: "2013-04-08T07:00:00Z",
    },
    { wrapperType: "track", kind: "song", artistName: "Someone Else", trackName: "Tum Hi Ho (Cover)", artworkUrl100: "http://insecure/100x100bb.jpg" },
  ],
};

const LIST = ["Here are some picks:", "", "1. **Tum Hi Ho** - Arijit Singh", "2. **Kesariya** - Arijit Singh (2022): dreamy", "3. \"Raataan Lambiyan\" by Jubin Nautiyal", "", "Enjoy!"].join("\n");

test("block: parses title, app and songs; ignores junk; caps at 12", () => {
  const spec = parsePlaylistBlock("title: Rainy day\napp: Apple Music\n- Tum Hi Ho | Arijit Singh\n2. Kesariya | Arijit Singh\nnot a song\n- Solo |");
  assert.equal(spec?.title, "Rainy day");
  assert.equal(spec?.app, "apple_music");
  assert.deepEqual(spec?.items, [
    { title: "Tum Hi Ho", artist: "Arijit Singh" },
    { title: "Kesariya", artist: "Arijit Singh" },
    { title: "Solo", artist: "" },
  ]);
  assert.equal(parsePlaylistBlock("title: nothing"), null);
  const many = Array.from({ length: 30 }, (_, i) => `- S${i} | A`).join("\n");
  assert.equal(parsePlaylistBlock(many)?.items.length, MAX_TRACKS);
});

test("block: round trip, separators in names cannot break rows", () => {
  const block = playlistBlock({ title: "Mix", items: [{ title: "A | B", artist: "C" }, { title: "D", artist: "E" }] });
  assert.match(block, /^```sparky-playlist\ntitle: Mix\n- A B \| C\n- D \| E\n```$/);
  assert.equal(parsePlaylistBlock(block.split("\n").slice(1, -1).join("\n"))?.items.length, 2);
});

test("song lines: dash, by, quotes, notes are dropped; prose is not a song", () => {
  assert.deepEqual(parseSongLine("**Tum Hi Ho** - Arijit Singh"), { title: "Tum Hi Ho", artist: "Arijit Singh" });
  assert.deepEqual(parseSongLine("Kesariya — Arijit Singh (2022): dreamy"), { title: "Kesariya", artist: "Arijit Singh" });
  assert.deepEqual(parseSongLine("\"Raataan Lambiyan\" by Jubin Nautiyal"), { title: "Raataan Lambiyan", artist: "Jubin Nautiyal" });
  assert.deepEqual(parseSongLine("Blinding Lights by The Weeknd"), { title: "Blinding Lights", artist: "The Weeknd" });
  assert.equal(parseSongLine("Make sure you sleep well before the exam begins tomorrow morning - it helps a lot."), null);
  assert.equal(parseSongLine("Just a title"), null);
});

test("list detection: needs 3 consecutive song lines, skips code fences", () => {
  const found = detectSongList(LIST);
  assert.equal(found?.items.length, 3);
  assert.equal(found?.from, 2);
  assert.equal(detectSongList("1. A - B\n2. C - D"), null);
  assert.equal(detectSongList("```\n1. A - B\n2. C - D\n3. E - F\n```"), null);
  assert.equal(detectSongList("1. Install node - then run it\n2. Open the terminal window now - and type\n3. Done"), null);
});

test("conversion: only in music turns, replaces the list, keeps the prose", () => {
  const out = convertSongList(LIST, "songs like Kesariya?")!;
  assert.match(out, /Here are some picks:\n\n```sparky-playlist\ntitle: Songs like Kesariya\n- Tum Hi Ho \| Arijit Singh\n- Kesariya \| Arijit Singh\n- Raataan Lambiyan \| Jubin Nautiyal\n```\n\nEnjoy!/);
  assert.doesNotMatch(out, /1\. \*\*Tum/);
  assert.equal(convertSongList(LIST, "what are the steps to deploy"), null);
  assert.equal(convertSongList(out, "songs like Kesariya"), null); // already a card
});

test("music turn + title", () => {
  assert.ok(isMusicTurn("suggest some Hindi songs"));
  assert.ok(isMusicTurn("make me a gym playlist"));
  assert.ok(!isMusicTurn("how do I deploy my app"));
  assert.equal(playlistTitleFor("recommend songs like Tum Hi Ho"), "Songs like Tum Hi Ho");
  assert.equal(playlistTitleFor("gym playlist please"), "Playlist");
});

test("prompt: the playlist rule only appears on music turns", () => {
  const music = promptNeeds("suggest 5 songs like Kesariya");
  const other = promptNeeds("explain closures");
  assert.equal(music.playlist, true);
  assert.equal(other.playlist, false);
  assert.match(buildSystemPrompt("default", undefined, undefined, music), /sparky-playlist/);
  assert.doesNotMatch(buildSystemPrompt("default", undefined, undefined, other), /sparky-playlist/);
  assert.doesNotMatch(buildSystemPrompt("default"), /sparky-playlist/);
});

test("iTunes mapping: art upscaled, https only, best match, year and duration", () => {
  const t = mapItunes(ITUNES, { title: "Tum Hi Ho", artist: "Arijit Singh" })!;
  assert.equal(t.title, "Tum Hi Ho");
  assert.equal(t.artist, "Arijit Singh");
  assert.equal(t.art, "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/source/300x300bb.jpg");
  assert.equal(t.durationMs, 262_000);
  assert.equal(t.year, 2013);
  assert.match(t.previewUrl!, /^https:\/\/audio-ssl/);
  assert.match(t.album!, /Aashiqui 2/);
  assert.ok(t.link!.startsWith("https://music.apple.com/"));
  // a different artist or a missing song is not forced onto the row
  assert.equal(mapItunes(ITUNES, { title: "Tum Hi Ho", artist: "Lata Mangeshkar" }), null);
  assert.equal(mapItunes(ITUNES, { title: "Unrelated Thing", artist: "Arijit Singh" }), null);
  assert.equal(mapItunes({}, { title: "x", artist: "y" }), null);
  assert.equal(mapItunes(null, { title: "x", artist: "y" }), null);
  assert.equal(bigArt("https://x/y/100x100bb.png"), "https://x/y/300x300bb.png");
  assert.match(itunesUrl({ title: "Tum Hi Ho", artist: "Arijit Singh" }), /term=Tum%20Hi%20Ho%20Arijit%20Singh&entity=song&limit=3&country=IN/);
});

test("lookup: not found keeps a title/artist row; failures never throw; cached per song", async () => {
  resetPlaylistCaches();
  let calls = 0;
  const fetch: ItunesFetch = async () => {
    calls++;
    return ITUNES;
  };
  const a = await lookupTrack({ title: "Tum Hi Ho", artist: "Arijit Singh" }, { fetch, shared: true });
  const b = await lookupTrack({ title: "tum hi ho!", artist: "ARIJIT SINGH" }, { fetch, shared: true });
  assert.equal(calls, 1, "the normalized title+artist hits the cache");
  assert.deepEqual(a, b);
  assert.equal(a.durationMs, 262_000);
  const miss = await lookupTrack({ title: "Zzz Nope", artist: "Nobody" }, { fetch, shared: true });
  assert.deepEqual(miss, { title: "Zzz Nope", artist: "Nobody" });
  await lookupTrack({ title: "Zzz Nope", artist: "Nobody" }, { fetch, shared: true });
  assert.equal(calls, 2, "a miss is cached too");
  const boom = await lookupTrack({ title: "Fails", artist: "X" }, { fetch: async () => Promise.reject(new Error("net")), shared: true });
  assert.deepEqual(boom, { title: "Fails", artist: "X" });
});

test("enrich: capped at 12 songs, at most 3 requests at once, rate budget respected", async () => {
  resetPlaylistCaches();
  let live = 0;
  let peak = 0;
  let calls = 0;
  const fetch: ItunesFetch = async () => {
    calls++;
    live++;
    peak = Math.max(peak, live);
    await new Promise((r) => setTimeout(r, 5));
    live--;
    return { results: [] };
  };
  const songs = Array.from({ length: 20 }, (_, i) => ({ title: `Song ${i}`, artist: "A" }));
  const out = await enrichTracks(songs, { fetch });
  assert.equal(out.length, MAX_TRACKS);
  assert.equal(calls, MAX_TRACKS);
  assert.ok(peak <= 3);
  // the minute budget (18) is shared: after 12 used, only 6 more live lookups fit
  resetPlaylistCaches();
  let allowed = 0;
  for (let i = 0; i < 40; i++) if (takeItunesSlot(1_000)) allowed++;
  assert.equal(allowed, 18);
  assert.equal(takeItunesSlot(1_000 + 61_000), true, "the window rolls");
});

const YT = [
  { url: "https://www.youtube.com/playlist?list=PL123", title: "Best songs playlist" },
  { url: "https://www.youtube.com/channel/UCabc", title: "Arijit Singh" },
  { url: "https://www.youtube.com/watch?v=aaaaaaaaaaa", title: "Random vlog" },
  { url: "https://www.youtube.com/watch?v=Rbm6GXllBiw&t=3", title: "Tum Hi Ho Full Video | Aashiqui 2 | Arijit Singh" },
  { url: "https://youtu.be/bbbbbbbbbbb", title: "Tum Hi Ho (Lyrics)" },
];

test("youtube id: skips playlists and channels, prefers a title match, falls back to the first video", () => {
  assert.equal(pickYoutubeId(YT, { title: "Tum Hi Ho", artist: "Arijit Singh" }), "Rbm6GXllBiw");
  assert.equal(pickYoutubeId(YT, { title: "Unmatched", artist: "X" }), "aaaaaaaaaaa");
  assert.equal(pickYoutubeId([YT[0], YT[1]], { title: "x", artist: "y" }), null);
  assert.equal(pickYoutubeId([{ url: "https://example.com/watch?v=Rbm6GXllBiw" }], { title: "x", artist: "y" }), null);
});

test("Play all: url building and the 'most tracks resolved' rule", () => {
  assert.equal(playAllUrl(["a", "b"]), "https://www.youtube.com/watch_videos?video_ids=a,b");
  assert.equal(playAllFor(["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc"]), "https://www.youtube.com/watch_videos?video_ids=aaaaaaaaaaa,bbbbbbbbbbb,ccccccccccc");
  assert.equal(playAllFor(["a", null, "b", null]), null, "half is not most");
  assert.ok(playAllFor(["a", "b", "c", null, null]) !== null, "three of five is enough");
  assert.equal(playAllFor(["a", null, null]), null);
  assert.equal(playAllFor(["a", "a"]), null, "one distinct video is not a playlist");
});

test("resolvePlayAll: caches ids per song, caps lookups, hides Play all when ids are missing", async () => {
  resetPlaylistCaches();
  let calls = 0;
  const queries: string[] = [];
  const search = async (q: string) => {
    calls++;
    queries.push(q);
    const n = /Hit (\d+)/.exec(q)?.[1];
    return n ? [{ url: `https://www.youtube.com/watch?v=vid${n.padStart(8, "0")}`, title: `Hit ${n} official` }] : [];
  };
  const songs = Array.from({ length: 15 }, (_, i) => ({ title: `Hit ${i}`, artist: "A" }));
  const first = await resolvePlayAll(songs, { search });
  assert.equal(first.ids.length, MAX_TRACKS);
  assert.equal(calls, MAX_TRACKS);
  assert.match(queries[0], /site:youtube\.com$/);
  assert.ok(first.playAll?.startsWith("https://www.youtube.com/watch_videos?video_ids="));
  await resolvePlayAll(songs, { search });
  assert.equal(calls, MAX_TRACKS, "second time is all cache");
  const none = await resolvePlayAll([{ title: "Nope 1", artist: "A" }, { title: "Nope 2", artist: "A" }, { title: "Nope 3", artist: "A" }], { search });
  assert.equal(none.playAll, null);
  assert.equal(await lookupYoutubeId({ title: "Err", artist: "A" }, { search: async () => Promise.reject(new Error("x")) }), null);
});
