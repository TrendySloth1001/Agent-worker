import { test } from "node:test";
import assert from "node:assert/strict";
import { mapsDirUrl, navigateIntent, sanitizeIntent } from "../src/context/cardLinks.js";
import { formatDistance, formatDuration, mapOsrm, osrmUrl, drivingRoute, resetRoute, ROUTE_GAP_MS, routeKey } from "../src/context/route.js";
import { buildDirections, cleanDestination, directionsBlock, parseDirections, placesQuery, placesSearchCard, routeNote } from "../src/context/directions.js";
import { findPhones, NOTE_ADDRESS, NOTE_EMAIL, NOTE_PHONE, NOTE_URL, phoneDigits, scrubUnverified } from "../src/context/verify.js";
import { guardAsk, stripDecorativeEmoji, TYPE_IT_REPLY } from "../src/context/replyStyle.js";
import type { PlaceInfo } from "../src/context/geocode.js";

// ---- URL builders (exact) ----------------------------------------------------

test("maps URLs are exact", () => {
  assert.equal(mapsDirUrl({ destination: "Lonavala" }), "https://www.google.com/maps/dir/?api=1&destination=Lonavala&travelmode=driving");
  assert.equal(
    mapsDirUrl({ destination: "Lonavala, Maharashtra", origin: "Nalasopara", mode: "transit" }),
    "https://www.google.com/maps/dir/?api=1&destination=Lonavala%2C%20Maharashtra&origin=Nalasopara&travelmode=transit",
  );
  assert.deepEqual(navigateIntent("Lonavala"), {
    action: "view",
    uri: "google.navigation:q=Lonavala",
    package: "com.google.android.apps.maps",
    fallback: "https://www.google.com/maps/dir/?api=1&destination=Lonavala&travelmode=driving",
  });
  assert.ok(sanitizeIntent(navigateIntent("18.75,73.4")));
  assert.ok(sanitizeIntent({ action: "view", uri: mapsDirUrl({ destination: "x", origin: "y", mode: "transit" }) }));
});

// ---- OSRM --------------------------------------------------------------------

test("OSRM url, mapping and formats", () => {
  assert.equal(osrmUrl({ lat: 19.42, lon: 72.82 }, { lat: 18.75, lon: 73.41 }), "https://router.project-osrm.org/route/v1/driving/72.82,19.42;73.41,18.75?overview=false");
  assert.deepEqual(mapOsrm({ code: "Ok", routes: [{ distance: 104_600.4, duration: 9_000.2 }] }), { meters: 104_600, seconds: 9_000 });
  assert.equal(mapOsrm({ code: "NoRoute", routes: [] }), null);
  assert.equal(mapOsrm({ code: "Ok", routes: [] }), null);
  assert.equal(mapOsrm({ code: "Ok", routes: [{ distance: "x", duration: 1 }] }), null);
  assert.equal(mapOsrm(null), null);
  assert.equal(formatDistance(104_600), "105 km");
  assert.equal(formatDistance(12_340), "12.3 km");
  assert.equal(formatDistance(850), "850 m");
  assert.equal(formatDuration(9_000), "2.5 h");
  assert.equal(formatDuration(4_800), "1 h 20 min");
  assert.equal(formatDuration(1_500), "25 min");
});

test("drivingRoute caches, paces and never throws", async () => {
  resetRoute();
  const a = { lat: 19.42, lon: 72.82 };
  const b = { lat: 18.75, lon: 73.41 };
  let calls = 0;
  const sleeps: number[] = [];
  let t = 1_000_000;
  const ok = async () => {
    calls++;
    return { code: "Ok", routes: [{ distance: 105_000, duration: 9_000 }] };
  };
  const o = { fetch: ok, now: () => t, sleep: async (ms: number) => void sleeps.push(ms) };
  assert.deepEqual(await drivingRoute(a, b, o), { meters: 105_000, seconds: 9_000 });
  await drivingRoute(b, a, o);
  assert.equal(calls, 2);
  assert.ok(sleeps.length >= 1 && sleeps[0] <= ROUTE_GAP_MS && sleeps[0] > 0);
  assert.equal(await drivingRoute(a, b, { ...o, fetch: async () => { throw new Error("down"); } }), null);
  assert.equal(routeKey(a, b), "19.42,72.82>18.75,73.41");
});

// ---- parsing -----------------------------------------------------------------

test("parses route requests", () => {
  const cases: Array<[string, string, string | undefined]> = [
    ["Directions to Lonavala", "Lonavala", undefined],
    ["directions to Lonavala from Nalasopara", "Lonavala", "Nalasopara"],
    ["how to reach Lonavala", "Lonavala", undefined],
    ["How do I get to Blue Tokai Koramangala?", "Blue Tokai Koramangala", undefined],
    ["route to Pune airport from Thane", "Pune airport", "Thane"],
    ["navigate to Lonavala", "Lonavala", undefined],
    ["Lonavala directions", "Lonavala", undefined],
    ["Lonavala ka rasta", "Lonavala", undefined],
    ["Mumbai se Lonavala ka rasta", "Lonavala", "Mumbai"],
    ["Lonavala kaise jaye", "Lonavala", undefined],
    ["Nalasopara se Lonavala kaise jaye", "Lonavala", "Nalasopara"],
    ["directions from Nalasopara to Lonavala", "Lonavala", "Nalasopara"],
  ];
  for (const [text, dest, origin] of cases) {
    const r = parseDirections(text, []);
    assert.ok(r, text);
    assert.equal(r.destination, dest, text);
    assert.equal(r.origin, origin, text);
  }
  for (const text of ["what is the capital of France", "directions for use of this medicine are unclear to me", "tell me a joke", "I want to learn how to reach goals"]) {
    assert.equal(parseDirections(text, [])?.pure ?? null, null, text);
  }
  assert.equal(cleanDestination("there"), null);
});

test("hotel + directions is not a pure route request", () => {
  const r = parseDirections("Could you find hotels and direction to Lonavala. With hotel contact", []);
  assert.ok(r);
  assert.equal(r.destination, "Lonavala");
  assert.equal(r.pure, false);
  assert.equal(placesQuery("Could you find hotels and direction to Lonavala. With hotel contact", r.destination), "hotels in Lonavala");
  assert.equal(placesQuery("best cafes in Indiranagar", undefined), "cafes in Indiranagar");
  assert.equal(placesQuery("what is a hotel", undefined), null);
});

// ---- the real conversation ---------------------------------------------------

const place = (name: string, lat: number, lon: number, extra: Partial<PlaceInfo> = {}): PlaceInfo => ({ name, address: `${name}, Maharashtra`, lat, lon, ...extra });
const lookup = async (q: string) => {
  const s = q.toLowerCase();
  if (s.includes("lonavala")) return place("Lonavala", 18.7546, 73.4062);
  if (s.includes("nalasopara")) return place("Nalasopara", 19.4167, 72.8167);
  if (s.includes("mumbai")) return place("Mumbai", 19.076, 72.8777);
  return null;
};
let routeCalls: string[] = [];
const route = async (a: { lat: number; lon: number }, b: { lat: number; lon: number }) => {
  routeCalls.push(`${a.lat},${a.lon}>${b.lat},${b.lon}`);
  return { meters: 104_600, seconds: 9_000 };
};
const cards = (text: string) => [...text.matchAll(/```sparky-card\n([\s\S]*?)\n```/g)].map((m) => JSON.parse(m[1]));

const conversation = {
  t1: "I am planning to go to lonavala any idea where it is",
  t2: "Could you find hotels and direction to Lonavala. With hotel contact",
  t3: "Directions",
  t4: "Somewhere else (I'll type it)",
  t5: "Lonavala directions",
  t6: "Nalasopara",
};
const hist = (...u: string[]) => u.reverse();

test("every Directions turn of the real chat yields a card with no questions", async () => {
  routeCalls = [];
  // Turn 3: a bare "Directions" takes the place from the earlier messages.
  const t3 = parseDirections(conversation.t3, hist(conversation.t1, conversation.t2));
  assert.ok(t3?.pure);
  assert.equal(t3.destination, "Lonavala");
  const r3 = await buildDirections(t3, { lookup, route });
  assert.ok(r3);
  const c3 = cards(directionsBlock(r3))[0];
  assert.deepEqual(c3.actions.map((a: { label: string }) => a.label), ["Navigate", "Route in Maps", "Transit", "Share"]);
  assert.equal(c3.actions[0].intent.uri, "google.navigation:q=18.7546%2C73.4062");
  assert.ok(!/starting|where are you/i.test(r3.text));
  assert.ok(!c3.actions[1].intent.uri.includes("origin="));
  assert.equal(routeCalls.length, 0, "no origin known: no OSRM call, no invented numbers");
  assert.match(r3.text, /Tap Navigate/);

  // Turn 5: "Lonavala directions".
  const t5 = parseDirections(conversation.t5, hist(conversation.t1, conversation.t2, conversation.t3, conversation.t4));
  assert.equal(t5?.destination, "Lonavala");
  assert.ok(await buildDirections(t5!, { lookup, route }));

  // Turn 4 (the option text) after our own card: not a route, nothing asked.
  assert.equal(parseDirections(conversation.t4, hist(conversation.t1, conversation.t2, conversation.t3), "Tap Navigate for live directions"), null);

  // Without an approximate city and without a user origin, still a card (and still no OSRM).
  const t2 = parseDirections(conversation.t2, [conversation.t1]);
  assert.ok(t2 && !t2.pure);
});

test("Nalasopara after 'where are you starting from?' gives origin + destination + OSRM numbers", async () => {
  routeCalls = [];
  const ask = parseDirections(conversation.t6, hist(conversation.t1, conversation.t2, conversation.t3, conversation.t4, conversation.t5), "```ask\nquestion: Where are you starting from?\n- Mumbai\n- Pune\n```");
  assert.ok(ask?.pure);
  assert.equal(ask.origin, "Nalasopara");
  assert.equal(ask.destination, "Lonavala");
  const r = await buildDirections(ask, { lookup, route });
  assert.ok(r);
  assert.equal(r.text, "Lonavala is about 105 km from Nalasopara, roughly 2.5 h by road without traffic. Tap Navigate for live traffic and directions.");
  assert.deepEqual(routeCalls, ["19.4167,72.8167>18.7546,73.4062"]);
  const c = r.card;
  assert.deepEqual(c.rows, [{ k: "From", v: "Nalasopara" }, { k: "Distance", v: "105 km" }, { k: "Drive", v: "2.5 h" }]);
  assert.equal(c.actions[1].intent.uri, "https://www.google.com/maps/dir/?api=1&destination=18.7546%2C73.4062&origin=19.4167%2C72.8167&travelmode=driving");
  assert.equal(c.actions[2].intent.uri, "https://www.google.com/maps/dir/?api=1&destination=18.7546%2C73.4062&origin=19.4167%2C72.8167&travelmode=transit");
  // the answer never carries turn-by-turn or train instructions
  assert.ok(!/Western Express|Kalyan|Dahisar|expressway/i.test(directionsBlock(r)));
});

test("approximate city is labelled and never goes into the Maps origin; OSRM failure omits numbers", async () => {
  routeCalls = [];
  const ask = parseDirections("how to reach Lonavala", [])!;
  const r = await buildDirections(ask, { lookup, route, approx: { city: "Mumbai", region: "Maharashtra" } });
  assert.ok(r);
  assert.match(r.text, /from Mumbai \(approx\.\)/);
  assert.deepEqual(r.card.rows?.[0], { k: "From", v: "Mumbai (approx.)" });
  assert.ok(!(r.card.actions[1].intent.uri ?? "").includes("origin="));
  const down = await buildDirections(ask, { lookup, route: async () => null, approx: { city: "Mumbai" } });
  assert.ok(down);
  assert.ok(!/km/.test(down.text));
  assert.ok(!down.card.rows?.some((x) => x.k === "Distance"));
  // Nominatim unknown: still a card, by name
  const unk = await buildDirections(parseDirections("directions to Zzyzx Falls", [])!, { lookup, route });
  assert.equal(unk?.card.actions[0].intent.uri, "google.navigation:q=Zzyzx%20Falls");
});

test("hotel turn: invented numbers are stripped, numbers in sources are kept", () => {
  const reply = [
    "Here are some places to stay.",
    "",
    "| Hotel | Phone |",
    "| --- | --- |",
    "| Hilton Shillim | +91-2114-666666 |",
    "| Hotel Sahil | +91-2114-272727 |",
    "| Real Resort | +91 98765 43210 |",
    "",
    "Mail info@hotelsahil.example or see https://hotelsahil.example/book. Official: https://real.example/stay and [map](https://maps.example/x).",
    "Hotel Sahil, 12 Mumbai Pune Road, Lonavala.",
  ].join("\n");
  const sources = ["Real Resort, call 098765 43210 or write bookings@real.example", "See https://real.example/stay for rooms", "Which city?"];
  const out = scrubUnverified(reply, sources);
  assert.ok(!out.includes("666666") && !out.includes("272727"));
  assert.ok(out.includes("+91 98765 43210"), "number present in a source (different format) is kept");
  assert.ok(out.includes(NOTE_PHONE));
  assert.ok(!out.includes("info@hotelsahil.example") && out.includes(NOTE_EMAIL));
  assert.ok(!out.includes("hotelsahil.example/book") && out.includes(NOTE_URL));
  assert.ok(out.includes("https://real.example/stay"));
  assert.ok(out.includes("map") && !out.includes("maps.example"), "unverified markdown link keeps its text only");
  assert.ok(out.includes(NOTE_ADDRESS));
});

test("contact verifier: phone formats, emails, URLs", () => {
  const formats = ["+91 98765 43210", "+91-98765-43210", "098765 43210", "9876543210", "(022) 2345 6789", "022-23456789", "+1 (415) 555-2671", "+44 20 7946 0958", "1800 123 4567", "+91-2114-272727", "02114 272727"];
  for (const f of formats) {
    const hits = findPhones(`call ${f} today`);
    assert.equal(hits.length, 1, f);
    assert.ok(scrubUnverified(`call ${f} today`, []).includes(NOTE_PHONE), f);
    assert.equal(scrubUnverified(`call ${f} today`, [`tel ${f}`]), `call ${f} today`, f);
  }
  assert.equal(phoneDigits("+91 98765 43210"), phoneDigits("098765-43210"));
  assert.equal(phoneDigits("+91 98765 43210"), "9876543210");
  // not phones
  const safe = ["On 2026-10-15 it costs Rs 1,00,000 for 12.9716 N, 77.5946 E.", "Built in 1998-2004 with version 1.2.3.4567.", "Paid 8500000 rupees"];
  assert.equal(findPhones(safe[0]).length, 0);
  assert.equal(findPhones(safe[1]).length, 0);
  assert.equal(scrubUnverified("Mail a@b.com now", ["a@b.com"]), "Mail a@b.com now");
  assert.equal(scrubUnverified("Mail A@B.com now", ["a@b.com"]), "Mail A@B.com now");
  assert.equal(scrubUnverified("Mail x@y.org", []), `Mail ${NOTE_EMAIL}`);
  assert.equal(scrubUnverified("see https://a.example/p?x=1.", ["https://www.a.example/p/"]), "see https://a.example/p?x=1.");
  assert.equal(scrubUnverified("see https://b.example/p", ["https://a.example/p"]), `see ${NOTE_URL}`);
  assert.equal(scrubUnverified("[site](https://b.example/p) ok", []), "site ok");
  // the user's own number is known
  assert.equal(scrubUnverified("Calling 98765 43210", ["my number is 9876543210"]), "Calling 98765 43210");
  // code and fences are left alone
  const code = "```js\nconst n = '+91 98765 43210';\n```\nand `+91 98765 43210`";
  assert.equal(scrubUnverified(code, []), code);
  const card = '```sparky-card\n{"title":"x","actions":[{"intent":{"uri":"tel:+919876543210"}}]}\n```';
  assert.equal(scrubUnverified(card, []), card);
});

test("ask widgets: never after 'I'll type it', never the same question twice", () => {
  const ask = (q: string) => "```ask\nquestion: " + q + "\n- Delhi\n- Pune\nother: true\n```";
  const prev = "Where?\n" + ask("Where are you starting from?");
  // turn 4: the user picked the type-it option
  assert.equal(guardAsk(ask("Pick your city"), { userText: "Somewhere else (I'll type it)", prevAssistant: prev }), TYPE_IT_REPLY);
  assert.equal(guardAsk("Sure.\n" + ask("Which city?"), { userText: "Other", prevAssistant: prev }), "Sure.");
  // turn 5: same question again
  assert.equal(guardAsk(ask("Where are you starting from?"), { userText: "Lonavala directions", prevAssistant: prev }), TYPE_IT_REPLY);
  // a different question after a normal answer stays
  const fresh = ask("Which platform?");
  assert.equal(guardAsk(fresh, { userText: "help me deploy", prevAssistant: "Sure thing" }), fresh);
  assert.equal(guardAsk("plain text", { userText: "x", prevAssistant: prev }), "plain text");
});

test("emoji in headings and bullet markers is stripped; the user's own emoji request is honoured", () => {
  const reply = ["## 🚗 By road", "Drive on the highway.", "### 🚆 By train ️", "- ✅ Fast", "- 🛣️ Scenic", "- Plain bullet with a 🙂 inside", "```md", "## 🚗 in code", "```", "# 🚀"].join("\n");
  const out = stripDecorativeEmoji(reply, "directions please");
  assert.equal(out.split("\n").slice(0, 6).join("\n"), ["## By road", "Drive on the highway.", "### By train", "- Fast", "- Scenic", "- Plain bullet with a 🙂 inside"].join("\n"));
  assert.ok(out.includes("## 🚗 in code"));
  assert.ok(!out.includes("# 🚀"));
  assert.equal(stripDecorativeEmoji(reply, "reply with emoji please"), reply);
  assert.equal(stripDecorativeEmoji("## Notes ©", ""), "## Notes ©");
});

test("places search card and prompt rule", () => {
  const c = placesSearchCard("hotels in Lonavala")!;
  assert.equal(c.actions[0].intent.uri, "https://www.google.com/maps/search/?api=1&query=hotels%20in%20Lonavala");
  const note = routeNote({ directions: true, places: "hotels in Lonavala" });
  assert.match(note, /Never ask where the user is starting from/);
  assert.match(note, /Never write phone numbers/);
  assert.match(note, /at most 3/);
  assert.equal(cards(directionsBlock({ text: "x", card: c })).length, 1);
});
