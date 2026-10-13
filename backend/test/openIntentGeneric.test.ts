import { test } from "node:test";
import assert from "node:assert/strict";
import {
  actionBlock,
  openReply,
  parseOpenIntent,
  pickGenericApp,
  resolveOpenAction,
  type MetaFn,
  type OpenAction,
  type SiteSearchFn,
} from "../src/context/openIntent.js";
import { linkMeta, parseOgMeta, youtubeId, type MetaFetch } from "../src/context/linkMeta.js";
import { deviceActionsSchema } from "../src/context/deviceActions.js";
import { needsGithub, promptNeeds } from "../src/prompts/system.js";
import { githubIntent } from "../src/github/grounding.js";
import { TagStream } from "../src/web/tagStream.js";

// The real-phone conversation: Circle to Search identified the song.
const LAST_ANSWER = 'This is **Rab Diyan Rab Jaane** by **Gurnam Bhullar**, a Punjabi song. You can listen on Spotify [W1] and YouTube [W3].';
const SOURCES = [
  { url: "https://open.spotify.com/track/4abcDEF123", title: "Rab Diyan Rab Jaane - song and lyrics by Gurnam Bhullar | Spotify" },
  { url: "https://open.spotify.com/track/4abcDEF123?si=x", title: "Rab Diyan Rab Jaane | Spotify" },
  { url: "https://chartex.com/song/rab-diyan", title: "Rab Diyan Rab Jaane - Chartex" },
  { url: "https://www.youtube.com/watch?v=Zx9Yv8W7u6T", title: "Rab Diyan Rab Jaane (Official Video) - YouTube" },
];
const noMeta: MetaFn = async () => ({});
const neverSearch: SiteSearchFn = async () => {
  throw new Error("search must not run");
};

// ---- intent table -----------------------------------------------------------

/** [phrase, app key | category | null]: "app:spotify", "cat:music", "ctx" (generic, from the conversation) or null (not an action). */
const TABLE: Array<[string, string | null]> = [
  // The exact phrases of the bug reports.
  ["Open on youtube music", "app:youtube_music"],
  ["open in music app", "cat:music"],
  ["open it in my music app", "cat:music"],
  ["open in the app", "ctx"],
  ["play it", "cat:music"],
  ["play this song", "cat:music"],
  ["open it", "ctx"],
  ["listen to it", "cat:music"],
  ["watch it", "cat:video"],
  ["open it in a video app", "cat:video"],
  ["show it in maps", "app:maps"],
  ["buy it on a shopping app", "cat:shopping"],
  ["gaana chalao", "cat:music"],
  ["isko chalao", "cat:music"],
  ["music app mein kholo", "cat:music"],
  ["youtube pe chalao", "app:youtube"],
  ["Kesariya spotify pe bajao", "app:spotify"],
  ["ye gaana bajao", "cat:music"],
  ["isko spotify pe bajao", "app:spotify"],
  // Typos.
  ["play it on youtub music", "app:youtube_music"],
  ["open in spotfy", "app:spotify"],
  ["paly it on spotify", "app:spotify"],
  ["opne it on yt music", "app:youtube_music"],
  // More phrasings.
  ["play Rab Diyan Rab Jaane on Spotify", "app:spotify"],
  ["open youtube music", "app:youtube_music"],
  ["please play it again", "cat:music"],
  ["can you play this song on jiosaavn please", "app:jiosaavn"],
  ["spotify chalao", "app:spotify"],
  ["open the song in music app", "cat:music"],
  // Questions and other sentences: answered, never acted on.
  ["what app is this", null],
  ["is it on spotify?", null],
  ["which app plays this?", null],
  ["how do I open it on spotify", null],
  ["what's the best song to play on spotify?", null],
  ["open the pod bay doors", null],
  ["play chess with me", null],
  ["watch out for the rain", null],
  ["tell me about this song", null],
  ["who sang it", null],
  ["start a timer for 5 minutes", null],
  ["open a new chat", null],
  ["show me the lyrics", null],
  ["kya ye spotify pe hai", null],
];

test("open/play intent table (English, Hinglish, typos, negatives)", () => {
  for (const [phrase, want] of TABLE) {
    const i = parseOpenIntent(phrase);
    const got = !i ? null : i.app ? `app:${i.app.key}` : i.category ? `cat:${i.category}` : "ctx";
    assert.equal(got, want, phrase);
  }
  assert.equal(parseOpenIntent("Kesariya spotify pe bajao")!.query, "Kesariya");
  assert.equal(parseOpenIntent("play Rab Diyan Rab Jaane on Spotify")!.query, "Rab Diyan Rab Jaane");
  assert.equal(parseOpenIntent("open in music app")!.query, "");
});

// ---- generic targets: the installed app of the kind ---------------------------

test("'open in music app' opens an installed music app: the cited one, else YouTube Music", async () => {
  const intent = parseOpenIntent("open in music app")!;
  const a = await resolveOpenAction({ intent, sources: SOURCES, lastAnswer: LAST_ANSWER, installed: ["youtube_music", "youtube", "spotify"], search: neverSearch, meta: noMeta });
  assert.equal(a?.type, "url");
  assert.equal(a?.type === "url" && a.app, "Spotify");
  // Spotify is cited by the answer and installed: the cited one wins over the default order.
  const b = await resolveOpenAction({ intent, sources: SOURCES.slice(3), lastAnswer: LAST_ANSWER, installed: ["youtube_music", "youtube", "spotify"], search: neverSearch, meta: noMeta });
  assert.equal(b?.type === "url" && b.url, "https://music.youtube.com/watch?v=Zx9Yv8W7u6T");
  // Spotify not installed: never picked even though it is cited.
  const c = await resolveOpenAction({ intent, sources: SOURCES, lastAnswer: LAST_ANSWER, installed: ["youtube_music", "youtube"], search: neverSearch, meta: noMeta });
  assert.equal(c?.type === "url" && c.app, "YouTube Music");
});

test("the app the user named earlier in the conversation is preferred when installed", () => {
  const app = pickGenericApp({ category: "music", installed: ["youtube_music", "jiosaavn"], sources: [], history: ["who sings this?", "play it on jiosaavn"] });
  assert.equal(app?.key, "jiosaavn");
  const order = pickGenericApp({ category: "music", installed: ["gaana", "jiosaavn"], sources: [], history: [] });
  assert.equal(order?.key, "jiosaavn");
});

test("no music app installed: the reply asks which app, with chips", async () => {
  const a = await resolveOpenAction({ intent: parseOpenIntent("open in music app")!, sources: SOURCES, lastAnswer: LAST_ANSWER, installed: [], search: neverSearch, meta: noMeta });
  assert.equal(a?.type, "choice");
  const r = openReply(a!);
  assert.match(r.text, /Which app should I play "Rab Diyan Rab Jaane" in\?/);
  assert.deepEqual(r.suggestions, ["Play it on YouTube Music", "Play it on Spotify", "Play it on JioSaavn"]);
  assert.ok(!r.text.includes("```"));
});

test("'play it' with nothing to play in the conversation is left to the model", async () => {
  const a = await resolveOpenAction({ intent: parseOpenIntent("play it")!, sources: [], lastAnswer: "Python decorators wrap a function.", installed: ["youtube_music"], search: neverSearch, meta: noMeta });
  assert.equal(a, null);
  assert.equal(await resolveOpenAction({ intent: parseOpenIntent("open it")!, sources: [], lastAnswer: "Here is the **PDF** summary.", search: neverSearch, meta: noMeta }), null);
});

test("Hinglish 'isko chalao' resolves to the subject in the installed app", async () => {
  const a = await resolveOpenAction({ intent: parseOpenIntent("isko chalao")!, sources: SOURCES, lastAnswer: LAST_ANSWER, installed: ["youtube"], search: neverSearch, meta: noMeta });
  assert.equal(a?.type === "url" && a.app, "YouTube");
  assert.equal(a?.type === "url" && a.url, "https://www.youtube.com/watch?v=Zx9Yv8W7u6T");
});

test("the phone's installed apps travel in deviceActions (bad values are dropped, not a 400)", () => {
  assert.deepEqual(deviceActionsSchema.parse({ installedApps: ["spotify"] }).installedApps, ["spotify"]);
  assert.equal(deviceActionsSchema.parse({ installedApps: "spotify" }).installedApps, undefined);
});

// ---- the reply: one sentence and the card, nothing else -----------------------

test("open reply: one short sentence, never the request echoed, and only the card", async () => {
  const a = await resolveOpenAction({
    intent: parseOpenIntent("Open on youtube music")!,
    sources: SOURCES,
    lastAnswer: LAST_ANSWER,
    search: neverSearch,
    meta: async (url) => ({ image: `https://i.ytimg.com/vi/${youtubeId(url)}/hqdefault.jpg`, title: "Rab Diyan Rab Jaane (Official Video)" }),
  });
  const { text, suggestions } = openReply(a!);
  const [sentence, ...rest] = text.split("\n\n");
  assert.equal(sentence, 'Ready to play "Rab Diyan Rab Jaane" in YouTube Music.');
  assert.equal(rest.length, 1);
  assert.ok(rest[0].startsWith("```sparky-action"));
  // No images, widgets, citations, GitHub or links in the prose.
  assert.doesNotMatch(text, /\{\{image:|\[W\d|\[G\d|github|https?:\/\/(?!music\.youtube|i\.ytimg)/i);
  assert.doesNotMatch(sentence, /open on youtube music/i);
  assert.deepEqual(suggestions, []);
  const json = JSON.parse(rest[0].split("\n")[1]);
  assert.deepEqual(json, {
    type: "url",
    url: "https://music.youtube.com/watch?v=Zx9Yv8W7u6T",
    app: "YouTube Music",
    package: "com.google.android.apps.youtube.music",
    title: "Rab Diyan Rab Jaane",
    subtitle: "Gurnam Bhullar",
    image: "https://i.ytimg.com/vi/Zx9Yv8W7u6T/hqdefault.jpg",
  });
});

test("app and search-page replies", () => {
  const app: OpenAction = { type: "app", name: "Spotify", package: "com.spotify.music" };
  assert.match(openReply(app).text, /^Ready to open Spotify\.\n\n```sparky-action/);
  const search: OpenAction = { type: "url", url: "https://open.spotify.com/search/x", app: "Spotify", package: "com.spotify.music", via: "app_search", title: "X" };
  assert.match(openReply(search).text, /^Ready to search for "X" in Spotify\./);
  assert.equal(actionBlock({ type: "choice", category: "music", apps: [], subject: "" }), "");
});

// ---- link metadata ----------------------------------------------------------

test("og metadata: title, absolute https image and site name", () => {
  const html = `<html><head><title>Fallback</title>
    <meta property="og:title" content="Rab Diyan Rab Jaane &amp; more">
    <meta property="og:image" content="/img/cover.jpg">
    <meta property="og:site_name" content="Spotify"></head></html>`;
  assert.deepEqual(parseOgMeta(html, "https://open.spotify.com/track/1"), {
    title: "Rab Diyan Rab Jaane & more",
    image: "https://open.spotify.com/img/cover.jpg",
    site: "Spotify",
  });
  assert.deepEqual(parseOgMeta("<title>Only</title>", "https://x.example/"), { title: "Only" });
});

test("YouTube links: thumbnail from the id, title and channel from oEmbed", async () => {
  let asked = "";
  const fetch: MetaFetch = async (url) => {
    asked = url;
    return { url, body: JSON.stringify({ title: "Rab Diyan Rab Jaane", author_name: "Gurnam Bhullar - Topic" }) };
  };
  const m = await linkMeta("https://music.youtube.com/watch?v=Zx9Yv8W7u6T", { fetch });
  assert.ok(asked.startsWith("https://www.youtube.com/oembed?"));
  assert.deepEqual(m, { image: "https://i.ytimg.com/vi/Zx9Yv8W7u6T/hqdefault.jpg", title: "Rab Diyan Rab Jaane", subtitle: "Gurnam Bhullar" });
  // A failing or slow fetch never breaks the card.
  const slow: MetaFetch = () => new Promise(() => {});
  assert.deepEqual(await linkMeta("https://open.spotify.com/track/9", { fetch: slow, timeoutMs: 20 }), {});
});

test("YouTube live streams and playlists still get a thumbnail", async () => {
  // A live stream link with its video id (watch?v= or /live/<id>): the id gives the thumbnail.
  const oembed: MetaFetch = async (url) => ({ url, body: JSON.stringify({ title: "lofi hip hop radio 📚 beats to relax/study to", author_name: "Lofi Girl" }) });
  assert.equal(youtubeId("https://www.youtube.com/live/jfKfPfyJRdk?si=abc"), "jfKfPfyJRdk");
  assert.equal(youtubeId("https://www.youtube.com/watch?v=jfKfPfyJRdk&list=PL123&index=2"), "jfKfPfyJRdk");
  assert.equal((await linkMeta("https://www.youtube.com/live/jfKfPfyJRdk", { fetch: oembed })).image, "https://i.ytimg.com/vi/jfKfPfyJRdk/hqdefault.jpg");

  // A playlist (no video id): oEmbed's thumbnail is the first video's, normalized to hqdefault.
  let asked = "";
  const playlist: MetaFetch = async (url) => {
    asked = url;
    return {
      url,
      body: JSON.stringify({ title: "Chillhop Essentials", author_name: "Chillhop Music", thumbnail_url: "https://i.ytimg.com/vi/5yx6BWlEVcY/hqdefault.jpg?sqp=x" }),
    };
  };
  const m = await linkMeta("https://music.youtube.com/playlist?list=PLOzDu-MXXLliO9fBNZOQTBDddoA3FzZUo", { fetch: playlist });
  assert.ok(decodeURIComponent(asked).includes("https://www.youtube.com/playlist?list=PLOzDu-MXXLliO9fBNZOQTBDddoA3FzZUo"), "music host asked as www");
  assert.deepEqual(m, { title: "Chillhop Essentials", subtitle: "Chillhop Music", image: "https://i.ytimg.com/vi/5yx6BWlEVcY/hqdefault.jpg" });

  // A channel's live page with no oEmbed: the page's og:image.
  const page: MetaFetch = async (url) => {
    if (url.includes("/oembed")) throw new Error("404");
    return { url, body: `<meta property="og:image" content="https://i.ytimg.com/vi/jfKfPfyJRdk/maxresdefault_live.jpg"><meta property="og:title" content="Lofi Girl - live">` };
  };
  assert.equal((await linkMeta("https://www.youtube.com/@LofiGirl/live", { fetch: page })).image, "https://i.ytimg.com/vi/jfKfPfyJRdk/maxresdefault_live.jpg");

  // A slow oEmbed never loses a thumbnail the id already gives.
  const slow: MetaFetch = () => new Promise(() => {});
  assert.deepEqual(await linkMeta("https://www.youtube.com/watch?v=jfKfPfyJRdk", { fetch: slow, timeoutMs: 20 }), { image: "https://i.ytimg.com/vi/jfKfPfyJRdk/hqdefault.jpg" });
});

// ---- GitHub only when the message is about GitHub ------------------------------

test("GitHub rules and grounding stay off for media links and open requests", () => {
  assert.equal(needsGithub("Open on youtube music"), false);
  assert.equal(needsGithub("play https://music.youtube.com/watch?v=abc on my phone"), false);
  assert.equal(needsGithub("open music.youtube.com/watch?v=abc"), false);
  assert.equal(needsGithub("open 24/7 support"), false);
  assert.equal(needsGithub("show me flutter/flutter"), true);
  assert.equal(needsGithub("what's new in https://github.com/flutter/flutter"), true);
  assert.equal(promptNeeds("Open on youtube music").github, false);
  for (const p of ["Open on youtube music", "open in music app", "gaana chalao", "play it on spotify"]) assert.equal(githubIntent(p), null, p);
});

// ---- citation chip spacing --------------------------------------------------

test("a kept tag and the punctuation after it in a later chunk: no space between", () => {
  const run = (chunks: string[]) => {
    const t = new TagStream(new Set(["W1"]));
    return chunks.map((c) => t.push(c)).join("") + t.flush();
  };
  assert.equal(run(["on Spotify [W1]", " ."]), "on Spotify [W1].");
  assert.equal(run(["on Spotify [W1] ", "."]), "on Spotify [W1].");
  assert.equal(run(["on Spotify [W1]", " ", "."]), "on Spotify [W1].");
  assert.equal(run(["on Spotify [W1]", "\u00a0."]), "on Spotify [W1].");
  assert.equal(run(["on Spotify [W1]", " and more."]), "on Spotify [W1] and more.");
});
