/**
 * Action cards: "directions to Blue Tokai", "add the dentist on Friday 4pm to
 * my calendar", "set a timer for the pasta", "WhatsApp Rahul", "pay
 * rahul@okaxis 500", "cab to the airport". The model writes a small
 * ```sparky-card JSON block holding only meaning (a name, a time, a number);
 * this module turns it into the card the app shows, with the buttons and their
 * intents built from cardLinks.ts. Nothing runs without a tap.
 *
 *   detectCardTypes  local rules: which card types this turn may need (gates the prompt rule)
 *   cardsNote        the system note for those types only
 *   finalizeCards    replaces each block of the reply with the safe, built card
 *                    (places looked up on OpenStreetMap; no key, no model call)
 *
 * UPI cards come only from the user's own message: the payee must be written
 * in what the user typed, never taken from web pages or the model's memory.
 */
import { lookupPlace, type PlaceInfo } from "./geocode.js";
import {
  alarmIntent,
  amazonSearchUrl,
  clip,
  directionsIntent,
  eventIntent,
  findVpas,
  flightsUrl,
  flipkartSearchUrl,
  isLocalDateTime,
  isValidVpa,
  mapsSearchUrl,
  myntraSearchUrl,
  normalizeAmount,
  normalizePhone,
  PKG,
  sanitizeIntent,
  saveContactIntent,
  shareIntent,
  SITE,
  smsUri,
  swiggySearchUrl,
  telUri,
  timerIntent,
  travelSearchUrl,
  uberUrl,
  upiUri,
  whatsappUrl,
  zomatoSearchUrl,
  type CardIntent,
  type TravelMode,
} from "./cardLinks.js";

export const CARD_FENCE = "sparky-card";
export const CARD_TYPES = ["place", "event", "clock", "contact", "product", "ride", "food", "travel", "upi"] as const;
export type CardType = (typeof CARD_TYPES)[number];

/** One button. `app` names its logo in the app; `group: "apps"` buttons are alternatives (installed first). */
export type CardAction = { id: string; label: string; app: string; primary?: boolean; chip?: boolean; group?: "apps"; intent: CardIntent };
export type CardRow = { k: string; v: string };
export type Card = { v: 1; type: CardType; title: string; subtitle?: string; rows?: CardRow[]; notice?: string; actions: CardAction[] };

export const MAX_CARDS = 2;

// ---- detection ---------------------------------------------------------------

const RULES: Array<[CardType, RegExp]> = [
  ["place", /\b(where(?:'s| is)|directions?|how (?:do i|to|can i) get to|navigate|route to|near(?:by| me)|nearest|address of|location of|opening (?:hours|time)s?|timings?|open now|phone number of)\b/i],
  ["event", /\b(calendar|schedule (?:a |an |the )?(?:meeting|event|call|appointment|interview)|appointment|add .{1,40} (?:to|on) my (?:calendar|schedule)|invite|set up a meeting|book .{1,30} (?:slot|meeting))\b/i],
  ["clock", /\b(alarm|wake me|timer|countdown|remind me|reminder|stopwatch|recipe|how (?:long|to) (?:to )?(?:cook|bake|boil|fry|roast|steep)|bake for|simmer|boil for)\b/i],
  ["contact", /(?:\+?\d[\d\s().-]{7,}\d).{0,60}\b(?:call|whatsapp|text|sms|save|contact)\b|\b(?:call|whatsapp|text|sms|save|contact|message)\b.{0,60}(?:\+?\d[\d\s().-]{7,}\d)|\b(?:save|add) (?:this |the )?(?:contact|number)\b/i],
  ["product", /\b(buy|purchase|price of|how much (?:is|does|are)|cheapest|best .{1,40} (?:under|below)|where (?:can i|to) (?:buy|get|order)|add to cart|amazon|flipkart|myntra|deal on|discount on|worth buying)\b/i],
  ["ride", /\b(uber|ola|rapido|cab|taxi|auto ?rickshaw|(?:book|get|need|call|hail) (?:me )?(?:a |an )?(?:ride|auto|cab|taxi|bike))\b/i],
  ["food", /\b(zomato|swiggy|food delivery|order (?:some |a |an )?(?:food|dinner|lunch|breakfast|biryani|pizza|burger)|i(?:'m| am) hungry|craving|where (?:can|should) i eat|deliver(?:y)? (?:me )?(?:a |some )?(?:food|biryani|pizza))\b/i],
  ["travel", /\b(flights?|train tickets?|trains? (?:from|to)|bus (?:tickets?|from|to)|irctc|ixigo|makemytrip|fly (?:from|to)|tickets? (?:from|to)|book (?:a )?(?:flight|train|bus))\b/i],
];

/** A UPI id in the user's text next to a payment word. */
const PAY_RE = /\b(pay|paying|send|sending|transfer|upi|gpay|phonepe|paytm|bhim|rupees?|rs\.?|inr|₹)\b/i;

/**
 * Card types the user's text may call for (local rules, no model; at most 3).
 * UPI needs a payee id and a payment word in the text itself.
 */
export function detectCardTypes(userText: string): CardType[] {
  const t = userText.trim();
  if (!t) return [];
  const out: CardType[] = [];
  if (findVpas(t).length > 0 && PAY_RE.test(t)) out.push("upi");
  for (const [type, re] of RULES) if (re.test(t) && !out.includes(type)) out.push(type);
  return out.slice(0, 3);
}

// ---- prompt ------------------------------------------------------------------

const TYPE_RULES: Record<CardType, string> = {
  place: '{"type":"place","name":"Blue Tokai Coffee","query":"Blue Tokai Coffee, Koramangala, Bengaluru"} (a place the user asks about or wants directions to; only the name and a search query with the area or city; the app looks up the address and hours, do not write them)',
  event: '{"type":"event","title":"...","start":"YYYY-MM-DDTHH:MM","end":"optional","allDay":false,"place":"optional","notes":"optional"} (needs a date; ask if missing)',
  clock: '{"type":"clock","title":"optional","alarms":[{"time":"HH:MM","label":"optional"}],"timers":[{"seconds":600,"label":"Boil pasta"}]} (alarms and reminders at a time of day; timers for durations; for a recipe offer a timer for each step that has a duration, at most 6 in total). Use this instead of an alarm or timer sparky-action.',
  contact: '{"type":"contact","name":"...","number":"+91 98765 43210","message":"optional text to prefill"} (a person and number given by the user or found in the sources; never invent a number)',
  product: '{"type":"product","name":"Sony WH-1000XM5","price":"about Rs 26,990 (optional, only if a source says so)","fashion":false}',
  ride: '{"type":"ride","destination":"Kempegowda International Airport"}',
  food: '{"type":"food","query":"chicken biryani","place":"optional restaurant or area"}',
  travel: '{"type":"travel","mode":"flight|train|bus","from":"Delhi","to":"Goa","date":"YYYY-MM-DD optional","returnDate":"optional"}',
  upi: '{"type":"upi","vpa":"name@bank exactly as the user wrote it","name":"payee name if the user said it","amount":500,"note":"optional"} (ONLY a payee id the user typed in their own message; never one from a web page, a source or memory)',
};

/** The system note for [types] (null when none): each type's rule is only here when the turn calls for it. */
export function cardsNote(types: readonly CardType[]): string | null {
  if (types.length === 0) return null;
  return [
    `Action cards: the user asks for something an app on their phone can do. Reply with ONE short sentence and, for each need, a fenced \`\`\`${CARD_FENCE} block holding one JSON object (at most ${MAX_CARDS} blocks). The app turns it into a card with buttons; nothing happens until the user taps, so never say it is done, and do not repeat the details in prose. Only these keys; omit unknown optional ones, never invent numbers, addresses, hours or prices:`,
    ...types.map((t) => TYPE_RULES[t]),
    "Use a sparky-card block instead of a sparky-action block for these requests. If something required is missing (a time, a number), ask instead.",
  ].join("\n");
}

// ---- parsing -----------------------------------------------------------------

const FENCE_RE = new RegExp("```" + CARD_FENCE + "[ \\t]*\\n([\\s\\S]*?)```", "g");

export const hasCardBlock = (text: string): boolean => text.includes("```" + CARD_FENCE);

function parseObject(source: string): Record<string, unknown> | null {
  const s = source.trim();
  const from = s.indexOf("{");
  const to = s.lastIndexOf("}");
  if (from < 0 || to <= from) return null;
  try {
    const v = JSON.parse(s.slice(from, to + 1));
    return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const str = (v: unknown, n: number): string => clip(v, n);
const WORD = /[\p{L}\p{N}]+/gu;
const words = (s: string): Set<string> => new Set((s.toLowerCase().match(WORD) ?? []).filter((w) => w.length > 1));

/** Whether the lookup result is the place the model named (shares at least half of the name's words). */
export function placeMatches(name: string, info: PlaceInfo): boolean {
  const want = words(name);
  if (want.size === 0) return false;
  const have = words(`${info.name} ${info.address}`);
  let n = 0;
  for (const w of want) if (have.has(w)) n++;
  return n / want.size >= 0.5;
}

// ---- building ----------------------------------------------------------------

export type BuildContext = {
  /** The user's own recent messages (UPI payees must be written in them). */
  userTexts: string[];
  /** The looked-up place, for place cards. */
  place?: PlaceInfo | null;
};

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** "2026-10-16T16:00" as "Fri 16 Oct 2026, 16:00" (the date alone when there is no time). */
export function whenText(s: string, withTime = true): string {
  const [date, time] = s.split("T");
  const [y, m, d] = date.split("-").map(Number);
  const day = DAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  return `${day} ${d} ${MONTHS[m - 1]} ${y}${withTime && time ? `, ${time}` : ""}`;
}

const rows = (...r: Array<[string, string | undefined]>): CardRow[] => r.filter((x): x is [string, string] => !!x[1]).map(([k, v]) => ({ k, v }));

const finish = (c: Card): Card | null => {
  const actions = c.actions.flatMap((a) => {
    const intent = sanitizeIntent(a.intent);
    return intent ? [{ ...a, intent }] : [];
  });
  return actions.length ? { ...c, actions } : null;
};

function buildPlace(o: Record<string, unknown>, ctx: BuildContext): Card | null {
  const name = str(o.name, 120);
  if (!name) return null;
  const query = str(o.query, 200) || name;
  const info = ctx.place && placeMatches(name, ctx.place) ? ctx.place : null;
  const destination = info ? `${name}, ${info.address}`.replace(/, $/, "") : query;
  const share = [name, info?.address, mapsSearchUrl(info ? `${info.lat},${info.lon}` : query)].filter(Boolean).join("\n");
  const actions: CardAction[] = [{ id: "directions", label: "Directions", app: "maps", primary: true, intent: directionsIntent(destination, info ? { lat: info.lat, lon: info.lon } : undefined) }];
  if (info?.phone) actions.push({ id: "call", label: "Call", app: "call", intent: { action: "dial", uri: telUri(info.phone) } });
  actions.push({ id: "share", label: "Share", app: "share", intent: shareIntent(share) });
  return finish({ v: 1, type: "place", title: name, ...(info?.address ? { subtitle: info.address } : { subtitle: query !== name ? query : undefined }), rows: rows(["Hours", info?.hours], ["Phone", info?.phone]), actions });
}

function buildEvent(o: Record<string, unknown>): Card | null {
  const title = str(o.title, 120);
  const start = str(o.start, 16);
  if (!title || !isLocalDateTime(start)) return null;
  const allDay = o.allDay === true;
  const endRaw = str(o.end, 16);
  const end = isLocalDateTime(endRaw) && endRaw > start ? endRaw : undefined;
  const place = str(o.place ?? o.location, 160);
  const notes = str(o.notes, 400);
  const when = allDay ? whenText(start, false) : `${whenText(start)}${end ? ` to ${end.startsWith(start.slice(0, 10)) ? end.slice(11) : whenText(end)}` : ""}`;
  const share = [title, when, place, notes].filter(Boolean).join("\n");
  return finish({
    v: 1,
    type: "event",
    title,
    rows: rows(["When", when], ["Where", place], ["Notes", notes]),
    actions: [
      { id: "calendar", label: "Add to calendar", app: "calendar", primary: true, intent: eventIntent({ title, start, end, allDay, location: place || undefined, notes: notes || undefined }) },
      { id: "share", label: "Share", app: "share", intent: shareIntent(share) },
    ],
  });
}

const minutesText = (s: number) => (s % 3600 === 0 ? `${s / 3600} h` : s >= 3600 ? `${Math.floor(s / 3600)} h ${Math.round((s % 3600) / 60)} min` : s % 60 === 0 ? `${s / 60} min` : s > 60 ? `${Math.floor(s / 60)} min ${s % 60} s` : `${s} s`);

function buildClock(o: Record<string, unknown>): Card | null {
  const actions: CardAction[] = [];
  const alarms = Array.isArray(o.alarms) ? o.alarms : o.time ? [{ time: o.time, label: o.label }] : [];
  for (const a of alarms.slice(0, 3)) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(str((a as Record<string, unknown>)?.time, 5));
    if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) continue;
    const label = str((a as Record<string, unknown>).label, 60);
    const hh = m[1].padStart(2, "0");
    actions.push({ id: `alarm${actions.length}`, label: `Set alarm ${hh}:${m[2]}`, app: "alarm", intent: alarmIntent(Number(m[1]), Number(m[2]), label || undefined) });
  }
  const timers = Array.isArray(o.timers) ? o.timers : o.seconds ? [{ seconds: o.seconds, label: o.label }] : [];
  for (const t of timers.slice(0, 6)) {
    const seconds = Math.round(Number((t as Record<string, unknown>)?.seconds));
    if (!Number.isFinite(seconds) || seconds < 1 || seconds > 86_400) continue;
    const label = str((t as Record<string, unknown>).label, 60);
    actions.push({ id: `timer${actions.length}`, label: label ? `${label} · ${minutesText(seconds)}` : `Start timer ${minutesText(seconds)}`, app: "timer", chip: actions.length > 0 || timers.length > 1, intent: timerIntent(seconds, label || undefined) });
  }
  if (actions.length === 0) return null;
  actions[0].primary = true;
  actions[0].chip = false;
  const title = str(o.title, 80) || (actions.every((a) => a.app === "alarm") ? "Alarm" : actions.every((a) => a.app === "timer") ? "Timer" : "Alarms and timers");
  return finish({ v: 1, type: "clock", title, actions });
}

function buildContact(o: Record<string, unknown>): Card | null {
  const name = str(o.name, 80);
  const number = normalizePhone(str(o.number, 30));
  if (!number) return null;
  const message = str(o.message, 500);
  const email = /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(str(o.email, 100)) ? str(o.email, 100) : undefined;
  const actions: CardAction[] = [
    { id: "call", label: "Call", app: "call", primary: true, intent: { action: "dial", uri: telUri(number) } },
    { id: "whatsapp", label: "WhatsApp", app: "whatsapp", intent: { action: "view", uri: whatsappUrl(number, message || undefined), package: PKG.whatsapp } },
    { id: "sms", label: "SMS", app: "sms", intent: { action: "sendto", uri: smsUri(number), ...(message ? { extras: { body: message } } : {}) } },
    { id: "save", label: "Save contact", app: "contact", intent: saveContactIntent({ name: name || number, phone: number, email }) },
  ];
  return finish({ v: 1, type: "contact", title: name || number, subtitle: name ? number : undefined, rows: rows(["Message", message], ["Email", email]), actions });
}

const FASHION_RE = /\b(shirt|t-?shirt|jeans|kurta?|saree|dress|shoes?|sneakers?|jacket|hoodie|trousers?|top|skirt|heels|sandals|watch(?:es)?|handbag|backpack|sunglasses|ethnic|lehenga|innerwear)\b/i;

function buildProduct(o: Record<string, unknown>): Card | null {
  const name = str(o.name, 120);
  if (!name) return null;
  const q = str(o.query, 120) || name;
  const price = str(o.price, 60);
  const actions: CardAction[] = [
    { id: "amazon", label: "Amazon", app: "amazon", group: "apps", primary: true, intent: { action: "view", uri: amazonSearchUrl(q), package: PKG.amazon } },
    { id: "flipkart", label: "Flipkart", app: "flipkart", group: "apps", intent: { action: "view", uri: flipkartSearchUrl(q), package: PKG.flipkart } },
  ];
  if (o.fashion === true || FASHION_RE.test(q)) actions.push({ id: "myntra", label: "Myntra", app: "myntra", group: "apps", intent: { action: "view", uri: myntraSearchUrl(q), package: PKG.myntra } });
  return finish({ v: 1, type: "product", title: name, rows: rows(["Price", price]), notice: price ? "Prices change; check the app." : undefined, actions });
}

function buildRide(o: Record<string, unknown>): Card | null {
  const destination = str(o.destination ?? o.to, 160);
  if (!destination) return null;
  return finish({
    v: 1,
    type: "ride",
    title: destination,
    rows: rows(["Drop", destination]),
    notice: "Uber opens with the drop filled in. Ola and Rapido open the app; enter the drop there.",
    actions: [
      { id: "uber", label: "Uber", app: "uber", group: "apps", primary: true, intent: { action: "view", uri: uberUrl(destination), package: PKG.uber } },
      { id: "ola", label: "Ola", app: "ola", group: "apps", intent: { action: "launch", package: PKG.ola, fallback: SITE.ola } },
      { id: "rapido", label: "Rapido", app: "rapido", group: "apps", intent: { action: "launch", package: PKG.rapido, fallback: SITE.rapido } },
      { id: "directions", label: "Directions", app: "maps", intent: directionsIntent(destination) },
    ],
  });
}

function buildFood(o: Record<string, unknown>): Card | null {
  const q = str(o.query ?? o.dish ?? o.name, 100);
  if (!q) return null;
  const place = str(o.place, 100);
  const search = place ? `${q} ${place}` : q;
  return finish({
    v: 1,
    type: "food",
    title: q,
    subtitle: place || undefined,
    actions: [
      { id: "swiggy", label: "Swiggy", app: "swiggy", group: "apps", primary: true, intent: { action: "view", uri: swiggySearchUrl(search), package: PKG.swiggy } },
      { id: "zomato", label: "Zomato", app: "zomato", group: "apps", intent: { action: "view", uri: zomatoSearchUrl(search), package: PKG.zomato } },
    ],
  });
}

const ymd = (v: unknown): string | undefined => {
  const s = str(v, 10);
  return isLocalDateTime(s) && s.length === 10 ? s : undefined;
};

function buildTravel(o: Record<string, unknown>): Card | null {
  const from = str(o.from, 80);
  const to = str(o.to, 80);
  const mode = ["flight", "train", "bus"].includes(str(o.mode, 8).toLowerCase()) ? (str(o.mode, 8).toLowerCase() as TravelMode) : "flight";
  if (!from || !to) return null;
  const date = ymd(o.date);
  const returnDate = mode === "flight" ? ymd(o.returnDate) : undefined;
  const search: CardAction = { id: "search", label: "Search the web", app: "google", intent: { action: "view", uri: travelSearchUrl(mode, { from, to, date }) } };
  const actions: CardAction[] =
    mode === "flight"
      ? [
          { id: "flights", label: "Google Flights", app: "google", group: "apps", primary: true, intent: { action: "view", uri: flightsUrl({ from, to, date, returnDate }) } },
          { id: "mmt", label: "MakeMyTrip", app: "makemytrip", group: "apps", intent: { action: "view", uri: SITE.mmtFlights, package: PKG.makemytrip } },
        ]
      : mode === "train"
        ? [
            { id: "irctc", label: "IRCTC", app: "irctc", group: "apps", primary: true, intent: { action: "launch", package: PKG.irctc, fallback: SITE.irctc } },
            { id: "ixigo", label: "ixigo", app: "ixigo", group: "apps", intent: { action: "view", uri: SITE.ixigoTrains, package: PKG.ixigo } },
            { id: "mmt", label: "MakeMyTrip", app: "makemytrip", group: "apps", intent: { action: "view", uri: SITE.mmtTrains, package: PKG.makemytrip } },
            search,
          ]
        : [
            { id: "ixigo", label: "ixigo", app: "ixigo", group: "apps", primary: true, intent: { action: "view", uri: SITE.ixigoBus, package: PKG.ixigo } },
            { id: "mmt", label: "MakeMyTrip", app: "makemytrip", group: "apps", intent: { action: "view", uri: SITE.mmtBus, package: PKG.makemytrip } },
            search,
          ];
  return finish({
    v: 1,
    type: "travel",
    title: `${from} to ${to}`,
    subtitle: mode[0].toUpperCase() + mode.slice(1),
    rows: rows(["Date", date ? whenText(date, false) : undefined], ["Return", returnDate ? whenText(returnDate, false) : undefined]),
    notice: mode === "flight" ? undefined : "These open the search page; enter the trip there.",
    actions,
  });
}

export const UPI_NOTICE = "You'll confirm and pay in your UPI app. sparky never pays.";

function buildUpi(o: Record<string, unknown>, ctx: BuildContext): Card | null {
  const vpa = str(o.vpa, 100);
  if (!isValidVpa(vpa)) return null;
  // Only a payee the user typed themselves; never one from a web page, a source or the model's memory.
  const mine = new Set(ctx.userTexts.flatMap((t) => findVpas(t)).map((v) => v.toLowerCase()));
  if (!mine.has(vpa.toLowerCase())) return null;
  const typed = ctx.userTexts.join(" ").replace(/,/g, "");
  const amount = normalizeAmount(o.amount);
  const written = (typed.match(/\d+(?:\.\d+)?/g) ?? []).map(Number);
  const amountOk = amount && written.includes(Number(amount)) ? amount : undefined;
  const name = str(o.name, 60).replace(/[^\p{L}\p{N} .'-]/gu, "").trim();
  const note = str(o.note, 50).replace(/[^\p{L}\p{N} .,'-]/gu, "").trim();
  const uri = upiUri({ vpa, name: name || undefined, amount: amountOk, note: note || undefined });
  if (!uri) return null;
  return finish({
    v: 1,
    type: "upi",
    title: name ? `Pay ${name}` : `Pay ${vpa}`,
    subtitle: name ? vpa : undefined,
    rows: rows(["Amount", amountOk ? `₹${amountOk}` : undefined], ["Note", note]),
    notice: UPI_NOTICE,
    actions: [{ id: "pay", label: "Open UPI app", app: "upi", primary: true, intent: { action: "view", uri, chooser: true } }],
  });
}

/** The card for one model object, or null when it is invalid (or breaks a rule such as the UPI one). */
export function buildCard(o: Record<string, unknown>, ctx: BuildContext): Card | null {
  switch (str(o.type, 12).toLowerCase()) {
    case "place": return buildPlace(o, ctx);
    case "event": return buildEvent(o);
    case "clock":
    case "alarm":
    case "timer":
    case "reminder": return buildClock(o);
    case "contact": return buildContact(o);
    case "product": return buildProduct(o);
    case "ride": return buildRide(o);
    case "food": return buildFood(o);
    case "travel": return buildTravel(o);
    case "upi": return buildUpi(o, ctx);
    default: return null;
  }
}

/** The fenced block the app shows. */
export const cardBlock = (c: Card): string => "```" + CARD_FENCE + "\n" + JSON.stringify(c) + "\n```";

// ---- the reply ---------------------------------------------------------------

/** The cards of a payment message the model did not write (UPI is deterministic: the payee is in the user's text). */
export function fallbackUpiCard(userText: string): Card | null {
  const vpas = findVpas(userText);
  if (vpas.length !== 1 || !PAY_RE.test(userText)) return null;
  const amt = /(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)|\b([\d,]+(?:\.\d{1,2})?)\s*(?:rupees|rs\b|inr)/i.exec(userText);
  return buildUpi({ type: "upi", vpa: vpas[0], amount: amt ? (amt[1] ?? amt[2]) : undefined }, { userTexts: [userText] });
}

/**
 * [text] with every ```sparky-card block rebuilt from its meaning (the model's
 * own buttons and links are never kept), invalid blocks removed, at most
 * [MAX_CARDS] kept. Places are looked up first (OpenStreetMap, cached, paced).
 */
export async function finalizeCards(text: string, o: { userTexts: string[]; lookup?: typeof lookupPlace; signal?: AbortSignal }): Promise<string> {
  if (!hasCardBlock(text)) return text;
  const lookup = o.lookup ?? lookupPlace;
  const found = [...text.matchAll(FENCE_RE)];
  const built = new Map<string, string>();
  let kept = 0;
  for (const m of found) {
    const obj = parseObject(m[1]);
    let place: PlaceInfo | null = null;
    if (obj && str(obj.type, 12).toLowerCase() === "place" && kept < MAX_CARDS) {
      const q = str(obj.query, 200) || str(obj.name, 120);
      if (q) {
        const stop = AbortSignal.timeout(6_000);
        place = await lookup(q, { signal: o.signal ? AbortSignal.any([o.signal, stop]) : stop }).catch(() => null);
      }
    }
    const card = obj && kept < MAX_CARDS ? buildCard(obj, { userTexts: o.userTexts, place }) : null;
    if (card) kept++;
    built.set(m[0] + "#" + m.index, card ? cardBlock(card) : "");
  }
  let out = text.replace(FENCE_RE, (whole, _b, offset: number) => built.get(whole + "#" + offset) ?? "");
  out = out.replace(/\n{3,}/g, "\n\n").trim();
  return out;
}
