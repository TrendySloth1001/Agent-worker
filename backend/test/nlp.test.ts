import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyIntent, INTENTS, webVerdict, shapeHint, type IntentLabel } from "../src/nlp/intent.js";
import { detectLanguage, languageInstruction, languageClause } from "../src/nlp/language.js";
import { extractEntities, quoteNames, exactTerms, knownRepoGuesses, memoryHints, type Entity } from "../src/nlp/entities.js";
import { analyze } from "../src/nlp/index.js";

type Case = { text: string; intent: IntentLabel; lang: string };

// Realistic messages: English plus Hindi (Devanagari), Hinglish, Spanish and German.
const SET: Case[] = [
  // chitchat
  { text: "hey", intent: "chitchat", lang: "en" },
  { text: "hello there, how are you?", intent: "chitchat", lang: "en" },
  { text: "thanks, that was really helpful!", intent: "chitchat", lang: "en" },
  { text: "good morning!", intent: "chitchat", lang: "en" },
  { text: "bhai kaise ho, kya chal raha hai", intent: "chitchat", lang: "hi-Latn" },
  { text: "नमस्ते, आप कैसे हैं?", intent: "chitchat", lang: "hi" },
  { text: "hola, ¿cómo estás hoy?", intent: "chitchat", lang: "es" },
  { text: "Hallo, wie geht es dir?", intent: "chitchat", lang: "de" },
  { text: "tell me a joke", intent: "chitchat", lang: "en" },
  // explain
  { text: "What is the difference engine in computing history?", intent: "explain", lang: "en" },
  { text: "Why is the sky blue?", intent: "explain", lang: "en" },
  { text: "explain how garbage collection works in simple terms", intent: "explain", lang: "en" },
  { text: "Who was Ada Lovelace?", intent: "explain", lang: "en" },
  { text: "blockchain kya hota hai, thoda samjhao", intent: "explain", lang: "hi-Latn" },
  { text: "photosynthesis क्या है और यह कैसे होता है?", intent: "explain", lang: "hi" },
  { text: "¿Qué es la inflación y por qué sube?", intent: "explain", lang: "es" },
  { text: "Warum ist der Himmel blau? Erkläre es mir bitte.", intent: "explain", lang: "de" },
  // howto
  { text: "How do I set up a Python virtual environment on Windows?", intent: "howto", lang: "en" },
  { text: "how to get a passport in India step by step", intent: "howto", lang: "en" },
  { text: "What's the best way to learn to cook rice properly?", intent: "howto", lang: "en" },
  { text: "pan card ke liye apply kaise karu", intent: "howto", lang: "hi-Latn" },
  { text: "मैं घर पर पनीर कैसे बनाऊं?", intent: "howto", lang: "hi" },
  { text: "¿Cómo puedo renovar mi pasaporte paso a paso?", intent: "howto", lang: "es" },
  { text: "Wie kann ich mein Fahrrad selbst reparieren?", intent: "howto", lang: "de" },
  // code
  { text: "I get TypeError: Cannot read properties of undefined (reading 'map') in my React component", intent: "code", lang: "en" },
  { text: "```python\ndef add(a, b):\n    return a - b\n```\nwhy does this return the wrong value?", intent: "code", lang: "en" },
  { text: "write a python function that merges two sorted lists", intent: "code", lang: "en" },
  { text: "my flutter app crashes with null check operator used on a null value, here is the stack trace", intent: "code", lang: "en" },
  { text: "optimize this SQL query, it takes 12 seconds: SELECT * FROM orders o JOIN users u ON u.id = o.user_id", intent: "code", lang: "en" },
  { text: "yaar ye error aa raha hai code mein, npm install fail ho gaya", intent: "code", lang: "hi-Latn" },
  { text: "मेरे कोड में एरर आ रहा है, अनडिफाइंड वेरिएबल", intent: "code", lang: "hi" },
  { text: "Tengo un error en mi función de JavaScript, no funciona el bucle", intent: "code", lang: "es" },
  { text: "Mein Python-Skript wirft einen Fehler: ModuleNotFoundError", intent: "code", lang: "de" },
  // compare
  { text: "React vs Vue for a small team project?", intent: "compare", lang: "en" },
  { text: "Should I buy an iPhone or a Pixel this year?", intent: "compare", lang: "en" },
  { text: "compare PostgreSQL and MongoDB for an analytics workload", intent: "compare", lang: "en" },
  { text: "what's the difference between a loan and a mortgage and which is better for me", intent: "compare", lang: "en" },
  { text: "Honda City ya Hyundai Verna, kaun sa better rahega", intent: "compare", lang: "hi-Latn" },
  { text: "¿Cuál es mejor para empezar, Python o Java?", intent: "compare", lang: "es" },
  { text: "Was ist besser für Anfänger: Linux oder Windows? Vor- und Nachteile bitte.", intent: "compare", lang: "de" },
  // write
  { text: "Write a polite email to my landlord asking to fix the leaking tap", intent: "write", lang: "en" },
  { text: "draft a short LinkedIn bio for a product designer with 5 years of experience", intent: "write", lang: "en" },
  { text: "rewrite this message so it sounds more professional: hey can u send the report asap", intent: "write", lang: "en" },
  { text: "boss ko leave ke liye email likh do, kal fever hai", intent: "write", lang: "hi-Latn" },
  { text: "मुझे अपने दोस्त को जन्मदिन की बधाई का संदेश लिखो", intent: "write", lang: "hi" },
  { text: "Escribe un correo formal para solicitar una reunión con el director", intent: "write", lang: "es" },
  { text: "Schreibe mir eine Nachricht an meinen Vermieter wegen der Heizung", intent: "write", lang: "de" },
  // math
  { text: "what is 15% of 2400?", intent: "math", lang: "en" },
  { text: "solve 3x^2 - 12x + 9 = 0", intent: "math", lang: "en" },
  { text: "calculate the EMI for a 20 lakh loan at 8.5% for 15 years", intent: "math", lang: "en" },
  { text: "234 * 56 + 78", intent: "math", lang: "en" },
  { text: "450 aur 275 jodo, phir 18 percent GST kitna hoga", intent: "math", lang: "hi-Latn" },
  { text: "२५ गुणा १२ कितना होगा, हिसाब लगाओ", intent: "math", lang: "hi" },
  { text: "Calcula la raíz cuadrada de 144 más el 20 por ciento de 500", intent: "math", lang: "es" },
  { text: "Berechne den Mittelwert von 12, 15 und 21", intent: "math", lang: "de" },
  // news
  { text: "latest news on the Mars mission", intent: "news", lang: "en" },
  { text: "who won the cricket match yesterday?", intent: "news", lang: "en" },
  { text: "what's the current price of Bitcoin", intent: "news", lang: "en" },
  { text: "weather in Mumbai today", intent: "news", lang: "en" },
  { text: "aaj ki taaza khabar kya hai", intent: "news", lang: "hi-Latn" },
  { text: "आज का मौसम कैसा रहेगा दिल्ली में", intent: "news", lang: "hi" },
  { text: "Últimas noticias sobre las elecciones de hoy", intent: "news", lang: "es" },
  { text: "Aktuelle Nachrichten zur Bundestagswahl heute", intent: "news", lang: "de" },
  // github
  { text: "show me the recent commits in facebook/react", intent: "github", lang: "en" },
  { text: "list the open issues of my GitHub repo keepit", intent: "github", lang: "en" },
  { text: "summarize this PR https://github.com/vercel/next.js/pull/1234", intent: "github", lang: "en" },
  { text: "find a good open source library for PDF parsing on GitHub", intent: "github", lang: "en" },
  { text: "mere github repos dikhao jo private hain", intent: "github", lang: "hi-Latn" },
  { text: "Muéstrame los contribuidores del repositorio flutter/flutter en GitHub", intent: "github", lang: "es" },
  { text: "Zeig mir die letzten Commits im GitHub Repository torvalds/linux", intent: "github", lang: "de" },
  // ui
  { text: "build me a landing page for a coffee shop in HTML", intent: "ui", lang: "en" },
  { text: "create a responsive dashboard with sales charts", intent: "ui", lang: "en" },
  { text: "make a simple to-do app with add and delete buttons", intent: "ui", lang: "en" },
  { text: "ek calculator app banao html mein", intent: "ui", lang: "hi-Latn" },
  { text: "Crea una página web para mi portafolio de fotografía", intent: "ui", lang: "es" },
  { text: "Erstelle mir eine Webseite für meinen Friseursalon", intent: "ui", lang: "de" },
  // longdoc
  { text: "Write a detailed report on the future of renewable energy in India, with sections and an executive summary", intent: "longdoc", lang: "en" },
  { text: "summarize this document and list the key takeaways", intent: "longdoc", lang: "en" },
  { text: "Draft a comprehensive whitepaper about zero-trust security for banks", intent: "longdoc", lang: "en" },
  { text: "is document ka summary bana do, main points batao", intent: "longdoc", lang: "hi-Latn" },
  { text: "Resume este documento y dame los puntos principales", intent: "longdoc", lang: "es" },
  { text: "Fasse diesen Bericht bitte zusammen und nenne die wichtigsten Punkte", intent: "longdoc", lang: "de" },
  // quiz
  { text: "quiz me on world capitals", intent: "quiz", lang: "en" },
  { text: "make me flashcards for organic chemistry reactions", intent: "quiz", lang: "en" },
  { text: "teach me linear algebra from scratch, I'm a beginner", intent: "quiz", lang: "en" },
  { text: "give me 10 MCQs on the Indian constitution to practice", intent: "quiz", lang: "en" },
  { text: "mera quiz lo history ka, mujhe exam ki taiyari karni hai", intent: "quiz", lang: "hi-Latn" },
  { text: "Hazme un quiz de historia de España", intent: "quiz", lang: "es" },
  { text: "Teste mich bitte in englischen Vokabeln", intent: "quiz", lang: "de" },
  // memory
  { text: "remember that I'm vegetarian and allergic to peanuts", intent: "memory", lang: "en" },
  { text: "my name is Priya and I live in Pune", intent: "memory", lang: "en" },
  { text: "from now on always reply in short bullet points", intent: "memory", lang: "en" },
  { text: "yaad rakhna ki mera birthday 14 March ko hai", intent: "memory", lang: "hi-Latn" },
  { text: "याद रखना कि मैं शाकाहारी हूं", intent: "memory", lang: "hi" },
  { text: "Recuerda que me llamo Carlos y trabajo en Madrid", intent: "memory", lang: "es" },
  { text: "Merk dir bitte, dass ich Linkshänder bin", intent: "memory", lang: "de" },
  // image
  { text: "generate an image of a cat astronaut floating in space", intent: "image", lang: "en" },
  { text: "what does a Bengal tiger look like?", intent: "image", lang: "en" },
  { text: "draw a minimalist logo for my bakery", intent: "image", lang: "en" },
  { text: "taj mahal ki tasveer dikhao", intent: "image", lang: "hi-Latn" },
  { text: "Muéstrame una imagen de la Sagrada Familia", intent: "image", lang: "es" },
  { text: "Zeig mir ein Bild vom Schwarzwald im Herbst", intent: "image", lang: "de" },
];

// Written after the rules were tuned and never used to tune them: a check against overfitting the set above.
const HELD_OUT: Case[] = [
  { text: "sup, long time no see", intent: "chitchat", lang: "en" },
  { text: "can you tell me how photosynthesis works?", intent: "explain", lang: "en" },
  { text: "what are microservices and why do companies use them", intent: "explain", lang: "en" },
  { text: "how can I convert a PDF to Word for free", intent: "howto", lang: "en" },
  { text: "getting 'Cannot find module express' when I run node server.js", intent: "code", lang: "en" },
  { text: "git rebase gave me a merge conflict in package.json, what now", intent: "code", lang: "en" },
  { text: "Notion or Obsidian for taking notes, which one should I pick", intent: "compare", lang: "en" },
  { text: "write a thank you note to my teacher for the farewell gift", intent: "write", lang: "en" },
  { text: "if I invest 5000 a month at 12% for 10 years how much will I have", intent: "math", lang: "en" },
  { text: "Did the RBI change the repo rate this week?", intent: "news", lang: "en" },
  { text: "who is the maintainer of the kubernetes/kubernetes repository", intent: "github", lang: "en" },
  { text: "design a login screen with email and password fields", intent: "ui", lang: "en" },
  { text: "give me a 5 page study guide summarizing the French Revolution", intent: "longdoc", lang: "en" },
  { text: "test my knowledge of Python decorators", intent: "quiz", lang: "en" },
  { text: "please note that I prefer metric units", intent: "memory", lang: "en" },
  { text: "show me a picture of the northern lights", intent: "image", lang: "en" },
  { text: "bhai ek zabardast caption likh do mere trip photo ke liye", intent: "write", lang: "hi-Latn" },
  { text: "yaar python mein list reverse kaise karte hain", intent: "howto", lang: "hi-Latn" },
  { text: "आज की ताज़ा खबर क्या है", intent: "news", lang: "hi" },
  { text: "¿Puedes escribirme un poema sobre el mar?", intent: "write", lang: "es" },
  { text: "¿Cuánto es el 25% de 840?", intent: "math", lang: "es" },
  { text: "Wie installiere ich Docker auf Ubuntu?", intent: "howto", lang: "de" },
  { text: "Was ist der Unterschied zwischen TCP und UDP?", intent: "compare", lang: "de" },
  { text: "thanks a lot, you're the best", intent: "chitchat", lang: "en" },
];

test("held-out messages (not used for tuning)", () => {
  const wrong: string[] = [];
  let lang = 0;
  for (const c of HELD_OUT) {
    const r = classifyIntent(c.text);
    if (r.top !== c.intent) wrong.push(`  [${c.intent} -> ${r.top} ${r.confidence}] ${c.text}`);
    if (detectLanguage(c.text).code === c.lang) lang++;
  }
  const acc = 1 - wrong.length / HELD_OUT.length;
  console.log(`held-out top-1: ${HELD_OUT.length - wrong.length}/${HELD_OUT.length} = ${(acc * 100).toFixed(1)}%, language ${lang}/${HELD_OUT.length}${wrong.length ? "\n" + wrong.join("\n") : ""}`);
  assert.ok(acc >= 0.75, wrong.join("\n"));
});

function evaluate() {
  const results = SET.map((c) => ({ c, r: classifyIntent(c.text) }));
  const stats = new Map<IntentLabel, { tp: number; fp: number; fn: number }>();
  for (const l of INTENTS) stats.set(l, { tp: 0, fp: 0, fn: 0 });
  let correct = 0;
  const misses: string[] = [];
  for (const { c, r } of results) {
    if (r.top === c.intent) {
      correct++;
      stats.get(c.intent)!.tp++;
    } else {
      stats.get(c.intent)!.fn++;
      stats.get(r.top)!.fp++;
      misses.push(`  [${c.intent} -> ${r.top} ${r.confidence}] ${c.text.slice(0, 70)}`);
    }
  }
  return { correct, total: SET.length, stats, misses };
}

test("intent classifier: top-1 accuracy >= 85% with per-label precision/recall", () => {
  const { correct, total, stats, misses } = evaluate();
  const lines = [`top-1: ${correct}/${total} = ${((100 * correct) / total).toFixed(1)}%`];
  for (const l of INTENTS) {
    const { tp, fp, fn } = stats.get(l)!;
    const p = tp + fp ? tp / (tp + fp) : 1;
    const r = tp + fn ? tp / (tp + fn) : 1;
    lines.push(`  ${l.padEnd(9)} precision ${p.toFixed(2)}  recall ${r.toFixed(2)}  (n=${tp + fn})`);
  }
  if (misses.length) lines.push("misses:", ...misses);
  console.log(lines.join("\n"));
  assert.ok(total >= 60);
  assert.ok(correct / total >= 0.85, `top-1 ${correct}/${total}\n${misses.join("\n")}`);
});

test("language detection on the labelled set", () => {
  const wrong: string[] = [];
  for (const c of SET) {
    const r = detectLanguage(c.text);
    if (r.code !== c.lang) wrong.push(`  [${c.lang} -> ${r.code} ${r.confidence}] ${c.text.slice(0, 70)}`);
  }
  const acc = 1 - wrong.length / SET.length;
  console.log(`language accuracy: ${(acc * 100).toFixed(1)}%${wrong.length ? "\n" + wrong.join("\n") : ""}`);
  assert.ok(acc >= 0.9, wrong.join("\n"));
});

test("language: short and code-heavy text falls back to history", () => {
  const de = "Wie kann ich eine Datei in Python lesen und dann zeilenweise verarbeiten?";
  assert.equal(detectLanguage("ok", [de]).code, "de");
  assert.equal(detectLanguage("ok", [de]).source, "history");
  assert.equal(detectLanguage("```js\nconst x = foo(bar);\nconsole.log(x)\n```", [de]).code, "de");
  assert.equal(detectLanguage("ok").code, "en");
  assert.equal(detectLanguage("").code, "en");
});

test("language: Hinglish is not misdetected and low-confidence Latin is English", () => {
  assert.equal(detectLanguage("mujhe ek email likhna hai boss ko").code, "hi-Latn");
  assert.equal(detectLanguage("kal milte hain bhai, aaj kaam bahut hai").code, "hi-Latn");
  assert.equal(detectLanguage("Docker run flags").code, "en");
  assert.equal(detectLanguage("npm ERR! code ELIFECYCLE").code, "en");
  assert.equal(detectLanguage("lol ok").code, "en");
});

test("language instruction only for confident non-English without a profile language", () => {
  const de = detectLanguage("Wie funktioniert ein Elektromotor eigentlich genau?");
  assert.match(languageInstruction(de) ?? "", /German/);
  assert.equal(languageInstruction(de, "French"), null);
  assert.equal(languageInstruction(detectLanguage("How does a motor work?")), null);
  assert.match(languageInstruction(detectLanguage("mujhe batao ye kaise kaam karta hai bhai")) ?? "", /Hinglish/);
  assert.equal(languageClause(detectLanguage("hello there")), null);
  assert.match(languageClause(de) ?? "", /German/);
});

test("intent: multi-label scores, uncertainty and consumers", () => {
  const r = classifyIntent("compare React and Vue, then build me a landing page in HTML");
  assert.ok(r.labels.length >= 2);
  assert.ok(r.labels.every((l) => l.score > 0 && l.score <= 1));
  assert.equal(classifyIntent("").uncertain, true);
  assert.equal(webVerdict(classifyIntent("hey, how are you?")), "skip");
  assert.equal(webVerdict(classifyIntent("fix this error: TypeError undefined is not a function in my code")), "skip");
  assert.equal(webVerdict(classifyIntent("latest news on the election results")), "search");
  assert.equal(webVerdict(classifyIntent("tell me about the history of Rome")), "ask");
  assert.match(shapeHint(classifyIntent("thanks, bye!")) ?? "", /small talk/);
  assert.equal(shapeHint(classifyIntent("explain quantum tunnelling in depth")), null);
  assert.equal(classifyIntent("describe this", { hasImages: true }).top, "image");
});

const kinds = (es: Entity[], t: string) => es.filter((e) => e.type === t).map((e) => e.value);
const NOW = new Date(Date.UTC(2026, 9, 12)); // Monday 2026-10-12

test("entities: github repos, urls, emails, phones", () => {
  const e = extractEntities("check facebook/react and https://github.com/vercel/next.js/pull/12, mail me at Priya.S@example.co.in or call +91 98765 43210", NOW);
  assert.deepEqual(kinds(e, "repo").sort(), ["facebook/react", "vercel/next.js"]);
  assert.deepEqual(kinds(e, "email"), ["priya.s@example.co.in"]);
  assert.deepEqual(kinds(e, "phone"), ["+919876543210"]);
  assert.equal(kinds(e, "url").length, 1);
  assert.deepEqual(kinds(extractEntities("my number is 9876543210.", NOW), "phone"), ["9876543210"]);
});

test("entities: paths are not repos, and slash phrases are not repos", () => {
  const e = extractEntities("open src/routes/chat.ts and ./config/app.yaml, TCP/IP and and/or are fine", NOW);
  assert.deepEqual(kinds(e, "repo"), []);
  assert.deepEqual(kinds(e, "path").sort(), ["./config/app.yaml", "src/routes/chat.ts"]);
});

test("entities: dates and relative dates", () => {
  assert.deepEqual(kinds(extractEntities("meet tomorrow", NOW), "date"), ["2026-10-13"]);
  assert.deepEqual(kinds(extractEntities("due next friday", NOW), "date"), ["2026-10-16"]);
  assert.deepEqual(kinds(extractEntities("in 3 days", NOW), "date"), ["2026-10-15"]);
  assert.deepEqual(kinds(extractEntities("2 weeks ago", NOW), "date"), ["2026-09-28"]);
  assert.deepEqual(kinds(extractEntities("on 14 March 2025", NOW), "date"), ["2025-03-14"]);
  assert.deepEqual(kinds(extractEntities("March 3rd, 2024", NOW), "date"), ["2024-03-03"]);
  assert.deepEqual(kinds(extractEntities("born 25/12/1999", NOW), "date"), ["1999-12-25"]);
  assert.deepEqual(kinds(extractEntities("deadline 2026-11-30", NOW), "date"), ["2026-11-30"]);
});

test("entities: versions, money, identifiers", () => {
  assert.deepEqual(kinds(extractEntities("upgrade to v1.2.3 or 2.0.0-beta.1", NOW), "version"), ["1.2.3", "2.0.0-beta.1"]);
  assert.deepEqual(kinds(extractEntities("needs Python 3.12 and node 20.11", NOW), "version"), ["3.12", "20.11"]);
  assert.deepEqual(kinds(extractEntities("server at 192.168.1.10", NOW), "version"), []);
  assert.deepEqual(kinds(extractEntities("it costs $1,200.50 or Rs. 5000 or 3 lakh", NOW), "money"), ["USD 1200.5", "INR 5000", "INR 300000"]);
  assert.deepEqual(kinds(extractEntities("call getUserName() and read user_id from MAX_RETRY_COUNT", NOW), "identifier").sort(), ["MAX_RETRY_COUNT", "getUserName()", "user_id"]);
  assert.deepEqual(kinds(extractEntities("use `useState` hook", NOW), "identifier"), ["useState"]);
});

test("entities: tech gazetteer, people and orgs", () => {
  const e = extractEntities("Should I use Next.js with PostgreSQL and Docker, or Spring Boot on AWS?", NOW);
  assert.deepEqual(kinds(e, "tech"), ["Next.js", "PostgreSQL", "Docker", "Spring Boot", "AWS"]);
  const p = extractEntities("I talked to Sundar Pichai and Dr. Anita Rao about Infosys Technologies", NOW);
  assert.deepEqual(kinds(p, "person"), ["Sundar Pichai", "Anita Rao"]);
  assert.deepEqual(kinds(p, "org"), ["Infosys Technologies"]);
  // common words are not names
  const none = extractEntities("Please go to the store. What is Go good for? I like Rust.", NOW);
  assert.deepEqual(kinds(none, "tech"), ["Go", "Rust"]);
  assert.deepEqual(kinds(none, "person"), []);
  assert.deepEqual(kinds(extractEntities("go to the shop and express yourself", NOW), "tech"), []);
});

test("entity consumers: exact terms, quoted names, repo guesses, memory hints", () => {
  const e = extractEntities("What did Sundar Pichai say about Google Cloud and facebook/react v18.2.0?", NOW);
  const q = quoteNames("Sundar Pichai Google Cloud facebook/react", e);
  assert.equal(q, '"Sundar Pichai" "Google Cloud" "facebook/react"');
  assert.ok(exactTerms(e).includes("facebook/react"));
  assert.deepEqual(knownRepoGuesses(extractEntities("is the Flutter repo active?", NOW)), [{ owner: "flutter", repo: "flutter" }]);
  assert.ok(memoryHints(extractEntities("I work at Infosys and use Flutter", NOW)).some((l) => l.startsWith("organisations: Infosys")));
});

test("latency: full analysis stays under 5 ms per message", () => {
  const long = "Please review my code and explain why this crashes in React with Next.js 14.2.3 on https://github.com/vercel/next.js ".repeat(30);
  const msgs = [...SET.map((c) => c.text), long];
  for (const m of msgs) analyze(m); // warm up
  const times: number[] = [];
  const rounds = 20;
  for (let i = 0; i < rounds; i++) {
    for (const m of msgs) {
      const s = performance.now();
      analyze(m);
      times.push(performance.now() - s);
    }
  }
  times.sort((x, y) => x - y);
  const avg = times.reduce((a, b) => a + b, 0) / times.length;
  const p95 = times[Math.floor(times.length * 0.95)]!;
  console.log(`latency: avg ${avg.toFixed(3)} ms, p95 ${p95.toFixed(3)} ms, max ${times[times.length - 1]!.toFixed(2)} ms over ${times.length} runs`);
  assert.ok(avg < 5, `avg ${avg}`);
  assert.ok(p95 < 5, `p95 ${p95}`);
});

test("wiring: search decision short-circuits, prompt needs and keyword query use NLP", async () => {
  const { decideSearch } = await import("../src/web/searchDecision.js");
  assert.deepEqual(await decideSearch("thanks, that helps!", ""), { search: false, query: "", reason: "intent" });
  assert.equal((await decideSearch("fix this TypeError: undefined is not a function in my code", "")).reason, "intent");
  const news = await decideSearch("breaking news about the election results", "");
  assert.equal(news.search, true);
  const { promptNeeds } = await import("../src/prompts/system.js");
  const ui = classifyIntent("Crea una página web para mi portafolio de fotografía");
  assert.equal(promptNeeds("Crea una página web para mi portafolio", false, ui).html, true);
  assert.equal(promptNeeds("hey", false, classifyIntent("hey")).widgetExamples, false);
  const { intentHint } = await import("../src/prompts/intent.js");
  const de = "Erstelle mir eine Webseite für meinen Friseursalon";
  assert.match(intentHint(de, classifyIntent(de)) ?? "", /HTML page/);
  const { keywordQuery } = await import("../src/retrieval/search.js");
  assert.equal(keywordQuery("What did Sundar Pichai say about Hacker News"), 'what or did or sundar or pichai or say or about or hacker or news or "sundar pichai" or "hacker news"');
});
