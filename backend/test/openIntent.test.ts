import { test } from "node:test";
import assert from "node:assert/strict";
import { ACTION_FENCE, deviceActionsSchema, tailNotes } from "../src/context/deviceActions.js";
import { identificationMessage } from "../src/context/imageWeb.js";
import {
  actionBlock,
  conversationLinks,
  hasActionBlock,
  MEDIA_APPS,
  openSubject,
  parseOpenIntent,
  pickAppLink,
  resolveOpenAction,
  siteQueries,
  type SiteSearchFn,
  type MetaFn,
} from "../src/context/openIntent.js";
import { NO_TOOLS_NOTE } from "../src/prompts/system.js";
import { tidyCitations, TagStream } from "../src/web/tagStream.js";

const app = (key: string) => MEDIA_APPS.find((a) => a.key === key)!;

// The answer from the real-phone bug: the circled album art was identified.
const LAST_ANSWER =
  "This is the cover of **I Met Her Again** by **Maan Panu**, a Punjabi song released in India [W1]. You can stream it on YouTube and JioSaavn [W2].";
const SOURCES = [
  { url: "https://www.youtube.com/watch?v=abcDEF12345", title: "I Met Her Again - Maan Panu - YouTube" },
  { url: "https://music.apple.com/in/album/i-met-her-again/1234567", title: "I Met Her Again - Apple Music" },
  { url: "https://www.jiosaavn.com/song/i-met-her-again/ABC", title: "I Met Her Again | JioSaavn" },
  { url: "https://gaana.com/song/i-met-her-again", title: "I Met Her Again - Gaana" },
];

// ---- intent -----------------------------------------------------------------

test("open/play/listen/watch ... on <app> is an open request", () => {
  const i = parseOpenIntent("Open on youtube music")!;
  assert.equal(i.app?.key, "youtube_music");
  assert.equal(i.query, "");
  assert.equal(parseOpenIntent("open it on YouTube Music.")!.app?.key, "youtube_music");
  assert.equal(parseOpenIntent("play this song on spotify please")!.app?.key, "spotify");
  assert.equal(parseOpenIntent("play this song on spotify please")!.query, "");
  assert.equal(parseOpenIntent("Can you play I Met Her Again on JioSaavn")!.query, "I Met Her Again");
  assert.equal(parseOpenIntent("watch it on youtube")!.app?.key, "youtube");
  assert.equal(parseOpenIntent("listen to it on gaana")!.app?.key, "gaana");
  assert.equal(parseOpenIntent("show it in google maps")!.app?.key, "maps");
  assert.equal(parseOpenIntent("buy it on flipkart")!.app?.key, "flipkart");
  assert.equal(parseOpenIntent("open youtube music")!.explicit, false);
});

test("questions and other sentences are not open requests", () => {
  assert.equal(parseOpenIntent("what's the best song to play on spotify?"), null);
  assert.equal(parseOpenIntent("Is it on YouTube Music?"), null);
  assert.equal(parseOpenIntent("open the pod bay doors"), null);
  assert.equal(parseOpenIntent(""), null);
});

// ---- links ------------------------------------------------------------------

test("YouTube Music prefers music.youtube.com, else the YouTube video's id on music.youtube.com", () => {
  assert.equal(pickAppLink(app("youtube_music"), SOURCES), "https://music.youtube.com/watch?v=abcDEF12345");
  assert.equal(
    pickAppLink(app("youtube_music"), [...SOURCES, { url: "https://music.youtube.com/watch?v=zzzzzz111" }]),
    "https://music.youtube.com/watch?v=zzzzzz111",
  );
  assert.equal(pickAppLink(app("youtube"), SOURCES), "https://www.youtube.com/watch?v=abcDEF12345");
  assert.equal(pickAppLink(app("jiosaavn"), SOURCES), "https://www.jiosaavn.com/song/i-met-her-again/ABC");
  assert.equal(pickAppLink(app("apple_music"), SOURCES), "https://music.apple.com/in/album/i-met-her-again/1234567");
});

test("search and home pages are not item links", () => {
  assert.equal(pickAppLink(app("spotify"), [{ url: "https://open.spotify.com/search/i%20met%20her" }]), null);
  assert.equal(pickAppLink(app("youtube"), [{ url: "https://www.youtube.com/results?search_query=x" }]), null);
  assert.equal(pickAppLink(app("spotify"), [{ url: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC" }]), "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC");
});

test("subject: the user's words, else the bold names of the last answer, else a source title", () => {
  assert.equal(openSubject({ query: "Tum Hi Ho", lastAnswer: LAST_ANSWER, sources: SOURCES }), "Tum Hi Ho");
  assert.equal(openSubject({ query: "", lastAnswer: LAST_ANSWER, sources: SOURCES }), "I Met Her Again Maan Panu");
  assert.equal(openSubject({ query: "", lastAnswer: "plain", sources: SOURCES }), "I Met Her Again - Maan Panu");
});

test("conversation links: the sent sources plus links written in the answer", () => {
  const links = conversationLinks([{ url: "https://a.example/x" }], "See [here](https://open.spotify.com/track/abc) and https://gaana.com/song/y.");
  assert.deepEqual(
    links.map((l) => l.url),
    ["https://a.example/x", "https://open.spotify.com/track/abc", "https://gaana.com/song/y."],
  );
});

// ---- resolution -------------------------------------------------------------

const noMeta: MetaFn = async () => ({});
const neverSearch: SiteSearchFn = async () => {
  throw new Error("search must not run");
};

test("a direct link in the sources is used without searching", async () => {
  const a = await resolveOpenAction({ intent: parseOpenIntent("Open on youtube music")!, sources: SOURCES, lastAnswer: LAST_ANSWER, search: neverSearch, meta: noMeta });
  assert.deepEqual(a, {
    type: "url",
    url: "https://music.youtube.com/watch?v=abcDEF12345",
    app: "YouTube Music",
    package: "com.google.android.apps.youtube.music",
    via: "source",
    title: "I Met Her Again",
    subtitle: "Maan Panu",
  });
});

test("no link in the sources: a site-scoped search finds the item page", async () => {
  let asked: string[] = [];
  const search: SiteSearchFn = async (queries) => {
    asked = queries;
    return [
      { title: "Search", url: "https://open.spotify.com/search/i%20met%20her%20again", content: "" },
      { title: "I Met Her Again", url: "https://open.spotify.com/track/7xyz123ABC", content: "" },
    ];
  };
  const a = await resolveOpenAction({ intent: parseOpenIntent("play it on spotify")!, sources: SOURCES, lastAnswer: LAST_ANSWER, search, meta: noMeta });
  assert.deepEqual(asked, siteQueries(app("spotify"), "I Met Her Again Maan Panu"));
  assert.equal(asked[0], '"I Met Her Again Maan Panu" site:open.spotify.com');
  assert.equal(a?.type === "url" && a.url, "https://open.spotify.com/track/7xyz123ABC");
  assert.equal(a?.type === "url" && a.via, "search");
});

test("nothing found (or the search fails): the app's search deep link", async () => {
  for (const search of [async () => [], neverSearch] as SiteSearchFn[]) {
    const a = await resolveOpenAction({ intent: parseOpenIntent("Open on youtube music")!, sources: [], lastAnswer: LAST_ANSWER, search, meta: noMeta });
    assert.equal(a?.type === "url" && a.url, "https://music.youtube.com/search?q=I%20Met%20Her%20Again%20Maan%20Panu");
    assert.equal(a?.type === "url" && a.via, "app_search");
  }
});

test("'open youtube music' with nothing to open is an app action", async () => {
  const a = await resolveOpenAction({ intent: parseOpenIntent("open youtube music")!, sources: [], lastAnswer: "", search: neverSearch, meta: noMeta });
  assert.deepEqual(a, { type: "app", name: "YouTube Music", package: "com.google.android.apps.youtube.music" });
});

test("the action block is fenced JSON the app parses", () => {
  const block = actionBlock({ type: "url", url: "https://music.youtube.com/watch?v=abc", app: "YouTube Music", package: "com.google.android.apps.youtube.music", via: "source" });
  assert.ok(hasActionBlock(block));
  const json = JSON.parse(block.split("\n").slice(3, -1).join("\n"));
  assert.deepEqual(json, { type: "url", url: "https://music.youtube.com/watch?v=abc", app: "YouTube Music", package: "com.google.android.apps.youtube.music" });
  assert.ok(block.includes("```" + ACTION_FENCE));
});

// ---- prompt: actions on every turn type -------------------------------------

test("image + web and vision turns keep the device actions (the no-tools note allows the block)", () => {
  const ident = identificationMessage({ subject: "I Met Her Again", kind: "media", visibleText: "", description: "", queries: ["q"], model: "m", ms: 1 });
  const notes = tailNotes({ identification: ident, vision: true, noTools: NO_TOOLS_NOTE, actions: deviceActionsSchema.parse({}), open: null });
  assert.equal(notes[0], ident);
  assert.equal(notes[1], NO_TOOLS_NOTE);
  assert.match(notes[2], new RegExp("```" + ACTION_FENCE + " block for a phone action is allowed"));
  // The reminder comes after the no-tools note, so it wins.
  assert.ok(notes.indexOf(NO_TOOLS_NOTE) < 2);
});

test("no actions client: no reminder; text turns: no no-tools note", () => {
  assert.deepEqual(tailNotes({ identification: null, vision: true, noTools: NO_TOOLS_NOTE, actions: undefined, open: null }), [NO_TOOLS_NOTE]);
  assert.deepEqual(tailNotes({ identification: null, vision: false, noTools: NO_TOOLS_NOTE, actions: deviceActionsSchema.parse({}), open: "open" }), ["open"]);
});

// ---- citation spacing -------------------------------------------------------

test("dropped citations leave no space before punctuation (the exact phone strings)", () => {
  const none = new Set<string>();
  assert.equal(tidyCitations("released in India [W1]. You can open it on YouTube Music [W3].", none), "released in India. You can open it on YouTube Music.");
  assert.equal(tidyCitations("a [W1], b [W2]; c [W3]: d [W4]! e [W5]? (f [W6])", none), "a, b; c: d! e? (f)");
  assert.equal(tidyCitations("word [W9] more", none), "word more");
  assert.equal(tidyCitations("India [W1] .", new Set(["W1"])), "India [W1].");
  assert.equal(tidyCitations("India [W1].", new Set(["W1"])), "India [W1].");
  assert.equal(tidyCitations("a [link](https://x.y) .", none), "a [link](https://x.y) .");
});

test("TagStream drops unknown tags across chunk boundaries without a stray space", () => {
  const run = (chunks: string[], valid: Set<string>) => {
    const t = new TagStream(valid);
    return chunks.map((c) => t.push(c)).join("") + t.flush();
  };
  assert.equal(run(["released in India ", "[W1]. You can open it on YouTube Music ", "[W3", "]."], new Set()), "released in India. You can open it on YouTube Music.");
  assert.equal(run(["India ", "[W1]."], new Set(["W1"])), "India [W1].");
  assert.equal(run(["Hello ", "world"], new Set()), "Hello world");
});
