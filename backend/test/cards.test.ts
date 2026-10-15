import { test } from "node:test";
import assert from "node:assert/strict";
import {
  alarmIntent,
  amazonSearchUrl,
  directionsIntent,
  eventIntent,
  findVpas,
  flightsUrl,
  isLocalDateTime,
  isValidVpa,
  myntraSearchUrl,
  normalizeAmount,
  normalizePhone,
  safeHttps,
  sanitizeIntent,
  timerIntent,
  uberUrl,
  upiUri,
  whatsappUrl,
  type CardIntent,
} from "../src/context/cardLinks.js";
import { lookupPlace, mapNominatim, MIN_GAP_MS, paced, resetGeocode, searchUrl, userAgent } from "../src/context/geocode.js";
import { buildCard, cardsNote, detectCardTypes, fallbackUpiCard, finalizeCards, placeMatches, type Card } from "../src/context/cards.js";
import { buildSystemPrompt } from "../src/prompts/system.js";

const block = (o: unknown) => "```sparky-card\n" + JSON.stringify(o) + "\n```";
const cardsIn = (text: string): Card[] => [...text.matchAll(/```sparky-card\n([\s\S]*?)\n```/g)].map((m) => JSON.parse(m[1]));
const action = (c: Card, id: string) => c.actions.find((a) => a.id === id)!;

// ---- detection ---------------------------------------------------------------

test("detects the card type per request", () => {
  const cases: Array<[string, string]> = [
    ["directions to Blue Tokai Koramangala", "place"],
    ["what are the opening hours of AIIMS", "place"],
    ["add dentist appointment Friday 4pm to my calendar", "event"],
    ["wake me at 6:30", "clock"],
    ["set a timer for 10 minutes", "clock"],
    ["give me a pasta recipe", "clock"],
    ["whatsapp 98765 43210 that I am late", "contact"],
    ["save this number +44 20 7946 0000", "contact"],
    ["where can I buy a Sony WH-1000XM5", "product"],
    ["book a cab to the airport", "ride"],
    ["order biryani on swiggy", "food"],
    ["cheapest flights from Delhi to Goa", "travel"],
    ["pay rahul@okaxis 500", "upi"],
  ];
  for (const [text, type] of cases) assert.ok(detectCardTypes(text).includes(type as never), `${text} -> ${type}`);
});

test("no card for plain questions", () => {
  for (const t of ["explain how DNS works", "write a python function to sort a list", "hi", "", "my email is a@gmail.com, pay attention"]) {
    assert.deepEqual(detectCardTypes(t), [], t);
  }
});

test("UPI needs a payee id in the text and a payment word; an email is not one", () => {
  assert.ok(detectCardTypes("send 200 to meera@ybl").includes("upi"));
  assert.ok(!detectCardTypes("pay 200 to my landlord").includes("upi"));
  assert.ok(!detectCardTypes("send the report to meera@gmail.com").includes("upi"));
});

test("the prompt rule is only added for the detected types", () => {
  assert.equal(cardsNote([]), null);
  const note = cardsNote(["place"])!;
  assert.match(note, /"type":"place"/);
  assert.doesNotMatch(note, /"type":"upi"|"type":"ride"/);
  // The base prompt carries no card rule at all.
  assert.doesNotMatch(buildSystemPrompt("default", undefined), /sparky-card/);
});

// ---- builders: exact URLs and extras -----------------------------------------

test("directions intent: coordinates or text, with the web fallback", () => {
  assert.deepEqual(directionsIntent("Blue Tokai, Koramangala"), {
    action: "view",
    uri: "google.navigation:q=Blue%20Tokai%2C%20Koramangala",
    package: "com.google.android.apps.maps",
    fallback: "https://www.google.com/maps/dir/?api=1&destination=Blue%20Tokai%2C%20Koramangala",
  });
  assert.equal(directionsIntent("x", { lat: 12.93, lon: 77.62 }).uri, "google.navigation:q=12.93%2C77.62");
});

test("WhatsApp link prefills only the message and keeps digits", () => {
  assert.equal(whatsappUrl("+919876543210", "Running late & sorry"), "https://wa.me/919876543210?text=Running%20late%20%26%20sorry");
  assert.equal(whatsappUrl("+919876543210"), "https://wa.me/919876543210");
});

test("phone normalisation", () => {
  assert.equal(normalizePhone("098765 43210"), "+919876543210");
  assert.equal(normalizePhone("+44 20 7946 0000"), "+442079460000");
  assert.equal(normalizePhone("0044 20 7946 0000"), "+442079460000");
  assert.equal(normalizePhone("12345"), null);
  assert.equal(normalizePhone("+1234567890123456"), null);
});

test("UPI uri: exact format, encoded params, INR", () => {
  assert.equal(
    upiUri({ vpa: "rahul.k@okaxis", name: "Rahul Kumar", amount: "500", note: "Dinner & drinks" }),
    "upi://pay?pa=rahul.k%40okaxis&pn=Rahul%20Kumar&am=500&tn=Dinner%20%26%20drinks&cu=INR",
  );
  assert.equal(upiUri({ vpa: "a@b" }), null);
  assert.equal(upiUri({ vpa: "rahul@okaxis" }), "upi://pay?pa=rahul%40okaxis&cu=INR");
});

test("VPA validation", () => {
  for (const v of ["rahul@okaxis", "9876543210@ybl", "a.b-c_d@paytm"]) assert.ok(isValidVpa(v), v);
  for (const v of ["rahul", "rahul@gmail.com", "@ybl", "a@b", "ra hul@ybl", "rahul@ybl&am=1", "x@ybl?pa=evil@ybl"]) assert.ok(!isValidVpa(v), v);
  assert.deepEqual(findVpas("pay rahul@okaxis or mail me@gmail.com"), ["rahul@okaxis"]);
});

test("amounts", () => {
  assert.equal(normalizeAmount("₹1,250.5"), "1250.5");
  assert.equal(normalizeAmount(500), "500");
  for (const v of [0, -5, "abc", 100_001, null]) assert.equal(normalizeAmount(v), null);
});

test("shopping, ride and travel links", () => {
  assert.equal(amazonSearchUrl("usb c cable"), "https://www.amazon.in/s?k=usb%20c%20cable");
  assert.equal(myntraSearchUrl("Black Shirt"), "https://www.myntra.com/black-shirt?rawQuery=Black%20Shirt");
  assert.equal(
    uberUrl("Airport T2"),
    "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff%5Bnickname%5D=Airport%20T2&dropoff%5Bformatted_address%5D=Airport%20T2",
  );
  assert.equal(flightsUrl({ from: "Delhi", to: "Goa", date: "2026-11-02" }), "https://www.google.com/travel/flights?q=Flights%20from%20Delhi%20to%20Goa%20on%202026-11-02");
});

test("alarm, timer and event intents carry the right extras", () => {
  assert.deepEqual(alarmIntent(6, 30, "Gym"), { action: "set_alarm", extras: { hour: 6, minutes: 30, message: "Gym" } });
  assert.deepEqual(timerIntent(600, "Pasta"), { action: "set_timer", extras: { length: 600, message: "Pasta" } });
  assert.deepEqual(eventIntent({ title: "Dentist", start: "2026-10-16T16:00", location: "Clinic" }).extras, { title: "Dentist", begin: "2026-10-16T16:00", location: "Clinic" });
  assert.ok(isLocalDateTime("2026-02-28T10:00"));
  assert.ok(!isLocalDateTime("2026-02-30T10:00"));
  assert.ok(!isLocalDateTime("tomorrow"));
});

// ---- sanitisation ------------------------------------------------------------

test("scheme and host allow-list", () => {
  assert.equal(safeHttps("https://www.amazon.in/s?k=x"), "https://www.amazon.in/s?k=x");
  assert.equal(safeHttps("http://www.amazon.in/s?k=x"), null);
  assert.equal(safeHttps("https://evil.example/phish"), null);
  assert.equal(safeHttps("https://user:pw@www.amazon.in/"), null);
  for (const bad of ["javascript:alert(1)", "intent://x#Intent;end", "file:///etc/passwd", "content://contacts/people", "sms:123", "data:text/html,hi"]) {
    assert.equal(sanitizeIntent({ action: "view", uri: bad }), null, bad);
  }
  assert.equal(sanitizeIntent({ action: "dial", uri: "https://www.amazon.in/" }), null); // wrong scheme for the action
  assert.equal(sanitizeIntent({ action: "view" }), null); // view needs a uri
  assert.equal(sanitizeIntent({ action: "teleport" as never }), null);
});

test("sanitising drops unknown extras, packages and fallbacks", () => {
  const i = sanitizeIntent({
    action: "set_timer",
    package: "not a package!",
    fallback: "https://evil.example/",
    extras: { length: 60, message: "x", secret: "y", skipUi: true } as never,
  } as CardIntent)!;
  assert.deepEqual(i, { action: "set_timer", extras: { length: 60, message: "x" } });
  assert.equal(sanitizeIntent({ action: "launch" }), null);
  assert.deepEqual(sanitizeIntent({ action: "launch", package: "com.olacabs.customer", fallback: "https://www.olacabs.com/" }), { action: "launch", package: "com.olacabs.customer", fallback: "https://www.olacabs.com/" });
});

// ---- cards -------------------------------------------------------------------

test("the model cannot smuggle its own buttons or links into a card", async () => {
  const text = block({ type: "product", name: "Phone", actions: [{ id: "x", label: "Click", intent: { action: "view", uri: "https://evil.example" } }], url: "https://evil.example" });
  const [c] = cardsIn(await finalizeCards(text, { userTexts: ["buy a phone"] }));
  assert.deepEqual(c.actions.map((a) => a.id), ["amazon", "flipkart"]);
  assert.ok(!JSON.stringify(c).includes("evil.example"));
});

test("event card", async () => {
  const text = "Added.\n" + block({ type: "event", title: "Dentist", start: "2026-10-16T16:00", end: "2026-10-16T17:00", place: "Smile Clinic", notes: "Bring X-rays" });
  const out = await finalizeCards(text, { userTexts: ["dentist friday 4pm"] });
  const [c] = cardsIn(out);
  assert.equal(c.title, "Dentist");
  assert.deepEqual(c.rows, [
    { k: "When", v: "Fri 16 Oct 2026, 16:00 to 17:00" },
    { k: "Where", v: "Smile Clinic" },
    { k: "Notes", v: "Bring X-rays" },
  ]);
  assert.equal(action(c, "calendar").primary, true);
  assert.deepEqual(action(c, "calendar").intent.extras, { title: "Dentist", begin: "2026-10-16T16:00", end: "2026-10-16T17:00", location: "Smile Clinic", description: "Bring X-rays" });
  assert.equal(action(c, "share").intent.action, "send");
  assert.equal(buildCard({ type: "event", title: "x", start: "soon" }, { userTexts: [] }), null);
});

test("clock card: alarm, timers as chips, limits", async () => {
  const c = buildCard({ type: "clock", title: "Pasta", alarms: [{ time: "18:05", label: "Dinner" }], timers: [{ seconds: 600, label: "Boil" }, { seconds: 90 }, { seconds: 0 }, { seconds: 999999 }] }, { userTexts: [] })!;
  assert.deepEqual(c.actions.map((a) => a.label), ["Set alarm 18:05", "Boil · 10 min", "Start timer 1 min 30 s"]);
  assert.deepEqual(c.actions[0].intent, { action: "set_alarm", extras: { hour: 18, minutes: 5, message: "Dinner" } });
  assert.equal(c.actions[0].primary, true);
  assert.equal(c.actions[1].chip, true);
  const t = buildCard({ type: "timer", seconds: 300 }, { userTexts: [] })!;
  assert.equal(t.actions[0].label, "Start timer 5 min");
  assert.equal(t.actions[0].chip, false);
  assert.equal(buildCard({ type: "clock", alarms: [{ time: "25:00" }] }, { userTexts: [] }), null);
  const many = buildCard({ type: "clock", timers: Array.from({ length: 9 }, (_, i) => ({ seconds: 60 * (i + 1) })) }, { userTexts: [] })!;
  assert.equal(many.actions.length, 6);
});

test("contact card: call, WhatsApp prefilled, SMS, save; nothing is sent", () => {
  const c = buildCard({ type: "contact", name: "Rahul", number: "98765 43210", message: "Running late" }, { userTexts: [] })!;
  assert.deepEqual(c.actions.map((a) => a.id), ["call", "whatsapp", "sms", "save"]);
  assert.deepEqual(action(c, "call").intent, { action: "dial", uri: "tel:+919876543210" });
  assert.deepEqual(action(c, "whatsapp").intent, { action: "view", uri: "https://wa.me/919876543210?text=Running%20late", package: "com.whatsapp" });
  assert.deepEqual(action(c, "sms").intent, { action: "sendto", uri: "smsto:+919876543210", extras: { body: "Running late" } });
  assert.deepEqual(action(c, "save").intent, { action: "insert_contact", extras: { name: "Rahul", phone: "+919876543210" } });
  assert.equal(buildCard({ type: "contact", name: "x", number: "123" }, { userTexts: [] }), null);
});

test("product, ride, food and travel cards", () => {
  const ctx = { userTexts: [] };
  const p = buildCard({ type: "product", name: "Nike running shoes", price: "about Rs 4,000" }, ctx)!;
  assert.deepEqual(p.actions.map((a) => a.id), ["amazon", "flipkart", "myntra"]);
  assert.equal(p.rows?.[0].v, "about Rs 4,000");
  assert.deepEqual(buildCard({ type: "product", name: "USB cable" }, ctx)!.actions.map((a) => a.id), ["amazon", "flipkart"]);

  const r = buildCard({ type: "ride", destination: "Indiranagar Metro" }, ctx)!;
  assert.deepEqual(r.actions.map((a) => a.id), ["uber", "ola", "rapido", "directions"]);
  assert.equal(action(r, "uber").intent.package, "com.ubercab");
  assert.deepEqual(action(r, "ola").intent, { action: "launch", package: "com.olacabs.customer", fallback: "https://www.olacabs.com/" });

  const f = buildCard({ type: "food", query: "chicken biryani", place: "HSR Layout" }, ctx)!;
  assert.equal(action(f, "swiggy").intent.uri, "https://www.swiggy.com/search?query=chicken%20biryani%20HSR%20Layout");
  assert.equal(action(f, "zomato").intent.uri, "https://www.zomato.com/search?q=chicken%20biryani%20HSR%20Layout");

  const fl = buildCard({ type: "travel", mode: "flight", from: "Delhi", to: "Goa", date: "2026-11-02" }, ctx)!;
  assert.equal(action(fl, "flights").intent.uri, "https://www.google.com/travel/flights?q=Flights%20from%20Delhi%20to%20Goa%20on%202026-11-02");
  assert.equal(fl.title, "Delhi to Goa");
  const tr = buildCard({ type: "travel", mode: "train", from: "Pune", to: "Mumbai", date: "next friday" }, ctx)!;
  assert.deepEqual(tr.actions.map((a) => a.id), ["irctc", "ixigo", "mmt", "search"]);
  assert.equal(tr.rows?.length ?? 0, 0); // an unparseable date is dropped
  const bus = buildCard({ type: "travel", mode: "bus", from: "A", to: "B" }, ctx)!;
  assert.deepEqual(bus.actions.map((a) => a.id), ["ixigo", "mmt", "search"]);
});

// ---- UPI ---------------------------------------------------------------------

test("UPI card from the user's own message", async () => {
  const user = "pay rahul@okaxis 500 for dinner";
  const [c] = cardsIn(await finalizeCards(block({ type: "upi", vpa: "rahul@okaxis", name: "Rahul", amount: 500, note: "dinner" }), { userTexts: [user] }));
  assert.equal(c.title, "Pay Rahul");
  assert.match(c.notice!, /confirm and pay in your UPI app/);
  assert.match(c.notice!, /never pays/);
  const a = action(c, "pay");
  assert.equal(a.intent.uri, "upi://pay?pa=rahul%40okaxis&pn=Rahul&am=500&tn=dinner&cu=INR");
  assert.equal(a.intent.chooser, true);
});

test("UPI card is refused for a payee that is not in the user's message", async () => {
  // e.g. an id the model read on a web page or invented.
  const text = "Here you go.\n" + block({ type: "upi", vpa: "scammer@okaxis", amount: 500 });
  const out = await finalizeCards(text, { userTexts: ["pay my plumber 500", "his number is 9876543210"] });
  assert.equal(cardsIn(out).length, 0);
  assert.equal(out, "Here you go.");
  assert.equal(buildCard({ type: "upi", vpa: "rahul@okaxis" }, { userTexts: ["RAHUL@OKAXIS"] }) !== null, true); // case-insensitive
  assert.equal(buildCard({ type: "upi", vpa: "rahul@okaxis" }, { userTexts: ["see https://x.example/pay?pa=rahul@okaxis"] }) !== null, true); // the user pasted it themselves
  assert.equal(buildCard({ type: "upi", vpa: "rahul@gmail.com" }, { userTexts: ["rahul@gmail.com"] }), null);
});

test("UPI amount the user never wrote is dropped (they type it in their UPI app)", async () => {
  const c = buildCard({ type: "upi", vpa: "rahul@okaxis", amount: 5000 }, { userTexts: ["pay rahul@okaxis 500"] })!;
  assert.ok(!c.actions[0].intent.uri!.includes("am="));
  const d = buildCard({ type: "upi", vpa: "rahul@okaxis", amount: 500 }, { userTexts: ["pay rahul@okaxis 5,500"] })!;
  assert.ok(!d.actions[0].intent.uri!.includes("am="));
});

test("UPI fallback card when the model wrote none", () => {
  const c = fallbackUpiCard("send Rs 1,250.50 to meera@ybl")!;
  assert.equal(c.actions[0].intent.uri, "upi://pay?pa=meera%40ybl&am=1250.5&cu=INR");
  assert.equal(fallbackUpiCard("send money to a@ybl and b@paytm"), null);
  assert.equal(fallbackUpiCard("send the file to me@gmail.com"), null);
});

// ---- the reply ---------------------------------------------------------------

test("finalize: invalid blocks removed, at most two cards, prose kept", async () => {
  const text = ["Sure.", block({ type: "ride", destination: "A" }), block({ type: "nonsense" }), block({ type: "food", query: "pizza" }), block({ type: "product", name: "x" })].join("\n\n");
  const out = await finalizeCards(text, { userTexts: [] });
  assert.deepEqual(cardsIn(out).map((c) => c.type), ["ride", "food"]);
  assert.ok(out.startsWith("Sure."));
  assert.equal(await finalizeCards("no blocks", { userTexts: [] }), "no blocks");
  assert.doesNotMatch(await finalizeCards("```sparky-card\nnot json\n```", { userTexts: [] }), /sparky-card/);
});

// ---- Nominatim (fixtures, no network) ----------------------------------------

const NOMINATIM = [
  {
    lat: "12.9352",
    lon: "77.6245",
    name: "Blue Tokai Coffee Roasters",
    display_name: "Blue Tokai Coffee Roasters, 80 Feet Road, Koramangala, Bengaluru, Karnataka, 560034, India",
    address: { road: "80 Feet Road", suburb: "Koramangala", city: "Bengaluru", state: "Karnataka", postcode: "560034" },
    extratags: { opening_hours: "Mo-Su 08:00-23:00; PH off", phone: "080 4123 4567" },
  },
];

test("maps a Nominatim result: name, address, hours, phone", () => {
  assert.deepEqual(mapNominatim(NOMINATIM), {
    name: "Blue Tokai Coffee Roasters",
    address: "80 Feet Road, Koramangala, Bengaluru, Karnataka, 560034",
    lat: 12.9352,
    lon: 77.6245,
    hours: "Mo-Su 08:00-23:00 · PH off",
    phone: "+918041234567",
  });
  assert.equal(mapNominatim([]), null);
  assert.equal(mapNominatim({}), null);
  assert.equal(mapNominatim([{ lat: "abc", lon: "1", name: "x" }]), null);
  assert.equal(mapNominatim([{ lat: "95", lon: "1", name: "x" }]), null);
});

test("the request: encoded query, descriptive User-Agent with a contact", () => {
  assert.equal(searchUrl("Blue Tokai & Co"), "https://nominatim.openstreetmap.org/search?q=Blue%20Tokai%20%26%20Co&format=jsonv2&limit=1&addressdetails=1&extratags=1&accept-language=en");
  assert.match(userAgent(), /^sparky-chat\/\d+\.\d+ \(https?:\/\/\S+|\S+@\S+\)$/);
});

test("lookups are cached and never repeat a live request", async () => {
  resetGeocode();
  let calls = 0;
  let ua = "";
  const fetch = async (_u: string, h: Record<string, string>) => {
    calls++;
    ua = h["User-Agent"];
    return NOMINATIM;
  };
  const sleep = async () => {};
  const a = await lookupPlace("Blue Tokai Koramangala", { fetch, sleep, shared: true });
  const b = await lookupPlace("blue tokai  koramangala!", { fetch, sleep, shared: true });
  assert.equal(calls, 1);
  assert.equal(a?.name, "Blue Tokai Coffee Roasters");
  assert.deepEqual(a, b);
  assert.match(ua, /^sparky-chat/);
});

test("a failed lookup is null and is not cached", async () => {
  resetGeocode();
  let calls = 0;
  const fetch = async () => {
    calls++;
    throw new Error("boom");
  };
  assert.equal(await lookupPlace("Nowhere Cafe", { fetch, sleep: async () => {}, shared: true }), null);
  assert.equal(await lookupPlace("Nowhere Cafe", { fetch, sleep: async () => {}, shared: true }), null);
  assert.equal(calls, 2);
});

test("requests are serialised at least 1.1 s apart", async () => {
  resetGeocode();
  let t = 1_000_000;
  const slept: number[] = [];
  const now = () => t;
  const sleep = async (ms: number) => {
    slept.push(ms);
    t += ms;
  };
  const starts: number[] = [];
  await Promise.all([1, 2, 3].map(() => paced(async () => void starts.push(t), { now, sleep })));
  assert.equal(starts.length, 3);
  assert.ok(starts[1] - starts[0] >= MIN_GAP_MS);
  assert.ok(starts[2] - starts[1] >= MIN_GAP_MS);
});

test("place card: found place fills address, hours, phone and uses coordinates", async () => {
  resetGeocode();
  const lookup = async () => mapNominatim(NOMINATIM);
  const out = await finalizeCards("Here.\n" + block({ type: "place", name: "Blue Tokai Coffee", query: "Blue Tokai Koramangala" }), { userTexts: ["directions to blue tokai"], lookup });
  const [c] = cardsIn(out);
  assert.equal(c.subtitle, "80 Feet Road, Koramangala, Bengaluru, Karnataka, 560034");
  assert.deepEqual(c.rows, [
    { k: "Hours", v: "Mo-Su 08:00-23:00 · PH off" },
    { k: "Phone", v: "+918041234567" },
  ]);
  assert.deepEqual(c.actions.map((a) => a.id), ["directions", "call", "share"]);
  assert.equal(action(c, "directions").intent.uri, "google.navigation:q=12.9352%2C77.6245");
  assert.equal(action(c, "call").intent.uri, "tel:+918041234567");
});

test("place card: not found shows the name and a directions search", async () => {
  const lookup = async () => null;
  const [c] = cardsIn(await finalizeCards(block({ type: "place", name: "Raju's Chai Stall", query: "Raju's Chai Stall, Pune" }), { userTexts: [], lookup }));
  assert.deepEqual(c.actions.map((a) => a.id), ["directions", "share"]);
  assert.equal(action(c, "directions").intent.uri, "google.navigation:q=Raju's%20Chai%20Stall%2C%20Pune");
  assert.match(action(c, "directions").intent.fallback!, /^https:\/\/www\.google\.com\/maps\/dir\/\?api=1&destination=/);
  assert.equal(c.rows?.length, 0);
});

test("place card: a lookup that found another place is ignored", async () => {
  assert.equal(placeMatches("Blue Tokai Coffee", mapNominatim(NOMINATIM)!), true);
  assert.equal(placeMatches("Starbucks Reserve", mapNominatim(NOMINATIM)!), false);
  const [c] = cardsIn(await finalizeCards(block({ type: "place", name: "Starbucks Reserve" }), { userTexts: [], lookup: async () => mapNominatim(NOMINATIM) }));
  assert.equal(c.rows?.length, 0);
  assert.equal(c.subtitle, undefined);
});
