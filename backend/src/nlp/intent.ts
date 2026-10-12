// Fast local intent classifier for chat messages. A weighted feature model:
// regex features (English, Hindi, Hinglish, Spanish, German) and a small
// token lexicon add evidence per label; structural cues (code fences, length,
// attachments) add more. Multi-label with scores, no network, no LLM.
//
// Embedding nearest-centroid fallback: not added. The embedding client in
// ../embeddings is a remote API call (50-500 ms), which breaks the hot-path
// budget, so uncertain messages fall through to the existing LLM deciders.

import { needsFreshFacts } from "../web/freshness.js";
import { capTokens } from "./entities.js";

export const INTENTS = [
  "chitchat",
  "explain",
  "howto",
  "code",
  "compare",
  "write",
  "math",
  "news",
  "github",
  "ui",
  "longdoc",
  "quiz",
  "memory",
  "image",
] as const;
export type IntentLabel = (typeof INTENTS)[number];

export type IntentResult = {
  top: IntentLabel;
  /** 0..1 confidence in [top]: strong evidence and a clear margin over the runner-up. */
  confidence: number;
  /** Every label with real evidence, best first. */
  labels: { label: IntentLabel; score: number }[];
  /** True when the evidence is thin or two labels are close: callers may ask a model. */
  uncertain: boolean;
};

export type IntentOpts = { hasImages?: boolean; hasAttachments?: boolean };

/** Whole-word match that also works for Devanagari and accented letters. */
const W = (src: string) => new RegExp(`(?<![\\p{L}\\p{N}_])(?:${src})(?![\\p{L}\\p{N}_])`, "iu");
type Feat = [RegExp, number];

const FEATURES: Record<IntentLabel, Feat[]> = {
  chitchat: [
    // Greetings and pleasantries (only count when the message is short, see score()).
    [W("hi+|hello+|hey+|heya|yo+|sup|wass?up|hola|buenas|hallo|moin|servus|namaste|namaskar|pranam|salaam|gm|gn|ty|thx|thanks|thank you|thank u|cheers|bye|goodbye|cya|ok|okay|k|cool|nice|great|awesome|lol|haha+|hmm+|wow|danke|gracias|merci|dhanyavad|shukriya|शुक्रिया|धन्यवाद|नमस्ते|नमस्कार|अलविदा|adios|tschüss|tschuss"), 2.2],
    [W("thanks a lot|thank you so much|thanks so much|many thanks|appreciate it|you'?re (the )?best|you rock|well done|good job|nice work"), 3.5],
    [W("how are you|how r u|how's it going|how is it going|what's up|whats up|how have you been|good (morning|evening|night|afternoon)|see you( later)?|take care|nice to meet you"), 3.5],
    [W("kaise ho|kaisa hai|kaise hain|kya haal|kya chal raha|kya scene|aur bhai|sab theek|kem cho|कैसे हो|क्या हाल|कैसे हैं|आप कैसे हैं"), 3.5],
    [W("c[oó]mo est[aá]s|qu[eé] tal|buenos d[ií]as|buenas (tardes|noches)|wie geht'?s|wie geht es dir|guten (morgen|tag|abend)|gute nacht"), 3.5],
    [W("who are you|what('s| is) your name|are you (a )?(bot|human|real|ai)|tell me a joke|i'?m bored|i love you|you('re| are) (awesome|great|funny|cool|smart)|good bot|are you there|you there"), 3.5],
    [W("tum kaun ho|tumhara naam|aapka naam kya|ek joke|joke suna|bore ho raha|bore ho rha|tu kaun hai|तुम कौन हो|चुटकुला|कोई जोक"), 3.5],
    [W("qui[eé]n eres|c[oó]mo te llamas|cu[eé]ntame un chiste|wer bist du|erz[aä]hl (mir )?einen witz"), 3.5],
  ],
  explain: [
    [/^\s*(what|who|why|whom|whose|which)\b/i, 1.2],
    [W("what (is|are|was|were|does)|what's|who (is|was|are)|why (is|are|do|does|did|can't|cannot)|explain|tell me about|define|meaning of|what does .{1,40} mean|eli5|in simple terms|overview of|intro(duction)? to|how (does|do|did) .{1,60} (work|happen|function)|is it true|history of|tell me more|elaborate"), 2.8],
    [W("kya hai|kya hota hai|kya hote hain|kya matlab|matlab kya|kyu hota|kyun hota|kyu hai|kyun hai|kaise kaam karta|kaise kaam karti|samjhao|samjha do|batao ye kya|explain karo|ke baare mein batao|ke bare me batao"), 3.2],
    [W("क्या है|क्या होता|क्यों|समझाओ|समझाइए|मतलब क्या|के बारे में बताओ|कैसे काम करता"), 3.2],
    [W("qu[eé] es|qu[eé] son|por qu[eé]|expl[ií]came|expl[ií]ca|cu[eé]ntame sobre|qu[eé] significa|c[oó]mo funciona|qui[eé]n fue"), 3.2],
    [W("was ist|was sind|warum|weshalb|erkl[aä]re?|erkl[aä]r mir|was bedeutet|wie funktioniert|wer war|erz[aä]hl mir (etwas )?[uü]ber"), 3.2],
    [/\?\s*$/, 0.5],
  ],
  howto: [
    [W("how (do|can|should|would|could|to|might) (i|you|we|one)?|how to|how can i|how do i|how should i"), 2.4],
    [W("steps? (to|for)|step[- ]by[- ]step|guide (to|for|on)|tutorial|walk me through|instructions? (to|for)|way to|best way to|what('s| is) the (best )?way to|set ?up|getting started|from scratch"), 2.2],
    [W("kaise (karu|karun|kare|karein|karte|banau|banaun|banaye|banayein|karna|banana|kar sakta|kar sakte|install|chalau|chalaun|set)|kaise banate|kaise karte|tarika|तरीका|कैसे (करूं|करें|करते|बनाऊं|बनाएं|बनाते|करना|बनाना)"), 3.4],
    [W("c[oó]mo (puedo|se hace|hago|hacer|se puede|instalo|creo|configuro|logro)|pasos para|gu[ií]a para"), 3.4],
    [W("wie (kann|mache|erstelle|installiere|richte|bekomme|schaffe|geht) (ich|man)|wie geht man|anleitung|schritt f[uü]r schritt|schritte"), 3.4],
    [W("what('s| is) the (best |easiest |fastest |right |proper |correct |quickest |simplest )?way (to|of)|best way to"), 3.4],
    [W("install|configure|setup|deploy|migrate|upgrade|enable|disable|connect"), 0.6],
  ],
  code: [
    [W("error|exception|stack ?trace|traceback|bug|bugs|crash(es|ed|ing)?|segfault|null ?pointer|undefined|nan|not working|doesn'?t work|isn'?t working|fails?|failed|failing|broken|compile|compiler|syntax|lint|refactor|debug|debugging|fix (this|my|the|it)|unit tests?|regex|query|sql|schema|api|endpoint|function|method|class|variable|array|loop|async|await|promise|callback|import|module|package|dependency|dependencies|library|framework|sdk|cli|backend|frontend|database|server|script|code|coding|snippet|algorithm|recursion|pointer|thread|memory leak|race condition"), 1.0],
    [W("javascript|typescript|python|java|kotlin|dart|flutter|react|vue|angular|svelte|node(\\.?js)?|deno|express|django|flask|fastapi|spring|rails|laravel|rust|golang|go lang|swift|php|ruby|c\\+\\+|c#|\\.net|bash|shell|powershell|docker|kubernetes|k8s|nginx|redis|postgres(ql)?|mysql|mongodb|sqlite|prisma|graphql|rest|webpack|vite|npm|pnpm|yarn|pip|cargo|gradle|maven|css|tailwind|jwt|oauth|cors|git rebase|linux|terminal|ssh|json|yaml|xml|html"), 0.9],
    [W("write (me )?(a|an|the|some)? ?(python|js|javascript|typescript|java|c\\+\\+|rust|go|dart|sql|bash|shell|node|react|flutter|kotlin|swift|php|ruby|regex|unit test|test|script|function|class|method|query|program|code|snippet|algorithm|api|endpoint|middleware|hook|component|cron|dockerfile)|implement|code (for|to|that)|give me (the )?code|convert (this )?code|optimi[sz]e (this|my) (code|query|function)|review (this|my) (code|pr|function)|explain (this|the) code|what does this code|time complexity|big o"), 2.6],
    [W("(error|exception|bug|traceback|crash)\\b.{0,30}(in|at|on|while|when)|cannot (read|find|resolve|import)|is not defined|is not a function|command not found|permission denied|segmentation fault|module not found|unexpected token|syntax ?error|type ?error|reference ?error|null ?pointer|nullpointerexception|status 500|404 error|401 unauthorized|build failed|npm err|stack overflow"), 3.2],
    [W("ye error|yeh error|code (mein|me|likh|likho|chal|nahi)|error aa (raha|rha|rahi)|bug fix|code ka|code likh|function likh|chal nahi raha|chal nhi rha|kaam nahi kar raha|kaam nhi kr rha|एरर|कोड|प्रोग्राम"), 3.2],
    [W("tengo un error|me da (un )?error|no funciona|escribe (una )?(funci[oó]n|funcion|consulta|clase|script|c[oó]digo)|c[oó]digo|programa en|arregla (este|mi) (c[oó]digo|error|bug)"), 3.2],
    [W("fehler|funktioniert nicht|schreibe? (mir )?(eine )?(funktion|klasse|skript|abfrage|code|programm)|programmcode|quellcode|wirft (einen )?fehler|abgest[uü]rzt"), 3.2],
    [/```/, 4],
    [/\b(def|function|const|let|var|class|import|from|SELECT|INSERT|UPDATE|CREATE TABLE|public static|#include|fn|func)\s+[\w{(*]/, 1.2],
    [/=>|\(\)\s*[{;]|[\w)\]]\.\w+\(|;\s*$|^\s*(\/\/|#!)|\bnpm (install|run)|\bpip install|\bgit (commit|push|pull|rebase|merge|checkout|stash|clone)\b/m, 1.8],
    [/\b[a-z]+[A-Z][a-z]+\w*\(|\b[a-z]+_[a-z]+\(|\w+\.(ts|tsx|js|jsx|py|dart|java|kt|rs|go|rb|php|cpp|cs|json|yaml|yml|sh)\b/, 1.8],
  ],
  compare: [
    [W("vs\\.?|versus|compare|comparison|comparing|difference(s)? between|differences? of|which (is|one is|one's|should i|do you) (better|best|faster|cheaper|safer)|better than|worse than|pros and cons|pros & cons|trade-?offs?|worth (it|buying)|should i (use|choose|pick|go with|buy|get|learn|switch)|or should i|alternatives? (to|for)|choose between|decide between|which one|which to|compared to|similarities"), 3.0],
    [/\bshould i\b[^?.!]{0,70}\bor\b/i, 2.2],
    [W("(\\w+) ya (\\w+)|kaun sa (better|best|achha|accha|sahi)|konsa (better|best|achha|accha|sahi)|kya better|farak kya|fark kya|antar kya|difference kya|vs kaun|se behtar|se better|कौन सा बेहतर|कौन सा सही|फर्क|अंतर क्या|बेहतर"), 3.2],
    [W("cu[aá]l es mejor|qu[eé] es mejor|diferencia entre|compara|comparar|ventajas y desventajas|mejor que|deber[ií]a (usar|elegir|comprar)"), 3.2],
    [W("unterschied zwischen|was ist besser|besser als|vergleich(e|en)?|vor- und nachteile|soll ich .{1,40} oder|welche[rs]? ist besser|lohnt sich"), 3.2],
  ],
  write: [
    [W("(write|draft|compose|create|prepare|generate|make|give me|need|want) (me |us )?(a |an |the |my |one |some )?(short |brief |polite |formal |professional |friendly |quick |catchy |funny |heartfelt )?(email|e-mail|mail|message|letter|cover letter|resume|cv|bio|biography|about me|post|caption|tweet|linkedin post|speech|toast|apology|resignation|invitation|reply|response|text|whatsapp message|thank[- ]you note|testimonial|review|description|tagline|slogan|poem|story|essay|paragraph|blog post|announcement|reminder|follow[- ]up|complaint|application|recommendation|summary of my)"), 3.6],
    [W("rewrite|rephrase|reword|paraphrase|proofread|polish this|improve (this|my) (text|writing|email|message|paragraph|sentence)|make (this|it) (more )?(professional|formal|polite|concise|shorter|friendly|casual)|fix (the |my )?grammar|translate|reply to (this|his|her|their)|respond to (this|his|her)|how (do|should) i (reply|respond|phrase|word)"), 3.0],
    [W("(email|mail|message|letter|bio|post|caption|msg|sandesh|application|resignation|leave) (likh|likho|likhna|likhna hai|likh do|likh de|likhdo|bana do|banao|draft kar|draft karo|bhejna|ke liye)|likh (do|de|dena|ke do)|ईमेल लिख|मेल लिख|संदेश लिख|पत्र लिख|आवेदन लिख|लिखो|लिख दो"), 3.6],
    [W("escr[ií]b\\w* ?(me |nos )?(un |una |el |mi )?(correo|email|mensaje|carta|biograf[ií]a|bio|discurso|texto|publicaci[oó]n|historia|poema|poes[ií]a|cuento|canci[oó]n)|redacta|redactar|reescribe|corrige (este|mi)|traduce"), 3.6],
    [W("schreibe? (mir |uns )?(eine?n? )?(e-?mail|nachricht|brief|bio|text|rede|geschichte|bewerbung|k[uü]ndigung|entschuldigung|beschreibung)|formuliere|verfasse|dichte|schreibe? (mir )?(ein )?(gedicht|lied)|[uü]berarbeite|korrigiere (diesen|meinen)|[uü]bersetze"), 3.6],
  ],
  math: [
    [/\d+(\.\d+)?\s*[+\-*/^×÷x%]\s*\(?\d+/i, 3.2],
    [W("calculate|calculation|compute|solve|simplify|evaluate|equation|integral|derivative|differentiate|integrate|sqrt|square root|logarithm|log of|factorial|percentage|percent|probability|permutation|combination|mean|median|average of|standard deviation|sum of|product of|prime|gcd|lcm|matrix|determinant|eigenvalue|quadratic|polynomial|trigonometry|sin|cos|tan|pythagoras|area of|volume of|perimeter|simple interest|compound interest|emi|gst|discount|profit|how many .{1,40} (in|are there in)|convert \\d+|\\d+ ?(km|kg|lbs?|miles?|celsius|fahrenheit|usd|inr|eur|cm|inches|feet|liters?|litres?|gb|mb) (to|in|into)"), 2.6],
    [/\bwhat('s| is)\s+\d[\d,.]*\s*(%|percent|of|times|plus|minus|divided|multiplied|x|\*)/i, 3.2],
    [W("invest(ed|ing|ment)?|savings?|how much (will|would|do|can|should) (i|we) (have|need|owe|pay|save|earn|get|make)|interest rate|per (month|year|annum)|growth rate|return on"), 1.8],
    [W("hisab|hisaab|jod(o|na)?|ghata(o|na)?|guna|bhaag|kitna hoga|kitne hote|kitna banega|percent kitna|calculate karo|solve karo|हिसाब|जोड़|घटा|गुणा|भाग|कितना होगा|कितने होंगे|प्रतिशत|हल करो|गणना"), 3.2],
    [W("calcula|calcular|cu[aá]nto es|cu[aá]nto son|resuelve|resolver|ecuaci[oó]n|porcentaje|ra[ií]z cuadrada|promedio|derivada|integral de"), 3.2],
    [W("berechne|berechnen|wie viel ist|wieviel ist|l[oö]se|gleichung|prozent|wurzel|mittelwert|ableitung|rechne"), 3.2],
  ],
  news: [
    [W("news|headlines?|breaking|right now|as of (now|today)|today'?s?|tonight|yesterday|just (released|announced|launched)|trending|live (score|updates?)|score of|who won|who is winning|election|results? (of|for)|stock price|share price|price of|exchange rate|weather|forecast|release date|when (is|does|will) .{1,40} (release|launch|come out|start)|is .{1,40} (out|released|available) yet|202[5-9]"), 2.4],
    [W("latest|newest|recent(ly)?|current(ly)?|this (week|month|year|morning|evening)|last (night|week|month)|upcoming"), 1.6],
    [W("what happened|what's happening|what is happening|any (news|updates?)|update on|status of|announced|launched|released|passed away|died|resigned|arrested|ipo|earnings|market (today|cap)|ceasefire|war in|protest|verdict"), 2.4],
    [W("khabar|khabrein|samachar|taaza|taza|aaj ka|aaj ki|aaj ke|kal ka match|kal ki|abhi (ka|ki|ke)|latest (khabar|news)|kaun jeeta|kaun jita|score kya|rate kya|bhav|मौसम|खबर|ख़बर|समाचार|ताज़ा|ताजा|आज का|आज की|आज के|कौन जीता|स्कोर|भाव"), 3.0],
    [W("noticias|[uú]ltimas noticias|[uú]ltimo|hoy|ayer|esta semana|actualmente|qui[eé]n gan[oó]|resultado del|precio de|el clima|tiempo en"), 3.0],
    [W("nachrichten|neueste[nrs]?|aktuell(e|en|er|es)?|heute|gestern|diese woche|wer hat gewonnen|ergebnis|wetter|kurs von|preis von|wahl"), 3.0],
  ],
  github: [
    [W("github|gh repo|git ?hub"), 3.4],
    [/github\.com\/[\w.-]+\/[\w.-]+/i, 4],
    [W("repo|repos|repository|repositories|pull requests?|prs?|merge request|issues?|commits?|commit history|branch(es)?|forks?|stars?|starred|contributors?|maintainers?|readme|changelog|releases?|open[- ]?source|source code|codebase|git graph"), 1.6],
    [/(?<![\w./@:-])[A-Za-z0-9][\w-]{1,38}\/[A-Za-z][\w.-]{1,60}(?![\w/])/, 1.4],
    [/\b(commits?|issues?|prs?|pull requests?|branch(es)?|releases?|stars?|contributors?|readme|changelog)\b[^.?!\n]{0,40}(?<![\w./@:-])[A-Za-z0-9][\w-]{1,38}\/[A-Za-z][\w.-]{1,60}(?![\w/])/i, 3.2],
    [W("my (repos?|repositories|prs?|pull requests?|issues?|commits?)|mere (repo|repos|repository)"), 2.0],
    [/[\w-]+\/[\w.-]+\b.{0,25}\b(repo|repository|repos)\b|\b(repo|repository|repos)\b.{0,35}(?<![\w./@:-])[\w-]+\/[\w.-]+/i, 3.2],
    [W("find (me )?(a |some )?(good |best |popular )?(librar(y|ies)|packages?|projects?|repos?|tools?) (for|to)|any (good |popular )?(open[- ]?source )?(librar(y|ies)|packages?|repos?) (for|to)|best (open[- ]?source|github) "), 2.4],
  ],
  ui: [
    [W("(build|make|create|generate|design|code|write|develop|need|want|give me)( me)?( a| an| the| some)?( simple| quick| small| responsive| interactive| modern| clean| beautiful| mobile| single[- ]page| full)* ?(html|web ?page|webpage|landing page|website|web app|dashboard|ui|user interface|calculator( app)?|to-?do( app| list)?|todo app|form|login (page|screen|form)|signup (page|form)|game|mock-?up|prototype|interface|component|screen|layout|portfolio|pricing (page|table)|navbar|card|widget|kanban|timer|stopwatch|clock|snake game|quiz app|tic[- ]tac[- ]toe)"), 4.0],
    [W("html (page|file|code|css|template)|single html|in html|as html|html css js|landing page|interactive (demo|page|tool|chart|simulation)|mock ?up|wireframe|ui for|ui design|simulation of|animation of|cheat ?sheet page"), 2.8],
    [W("(html|web ?page|website|landing page|dashboard|app|ui|page) (bana|banao|bana do|banado|banao na|design kar|design karo)|bana do|एचटीएमएल|वेबसाइट बना|पेज बना|डैशबोर्ड बना"), 3.6],
    [W("crea (una )?(p[aá]gina|web|landing|aplicaci[oó]n|interfaz|calculadora)|haz (una )?(p[aá]gina|web|landing|app|calculadora|juego)|dise[nñ]a (una )?(pantalla|interfaz|p[aá]gina)"), 3.8],
    [W("erstelle? (mir )?(eine?n? )?(webseite|website|landingpage|webapp|app|dashboard|rechner|formular|spiel|oberfl[aä]che)|baue? (mir )?(eine?n? )?(webseite|website|app|dashboard|rechner)|gestalte"), 3.8],
  ],
  longdoc: [
    [W("summari[sz](e|es|ing|ed)|summary of|tl;?dr|key (points|takeaways|findings)|main (points|ideas)|abstract|outline (of|for)|review (this|the|my) (document|doc|paper|report|article|contract|pdf|file|essay|proposal|thesis|draft)|analy[sz]e (this|the|my) (document|doc|paper|report|article|contract|pdf|file|text|transcript)|go through (this|the) (document|doc|pdf|file|paper|report)|extract (the )?(key|main|all)|proofread (this|my) (document|doc|essay|paper|report|thesis)"), 2.4],
    [W("(write|draft|create|prepare|generate|produce) (me )?(a |an |the )?(long|detailed|full|comprehensive|complete|in-?depth|thorough|\\d+[- ]?(page|word)) ?(report|document|doc|essay|article|whitepaper|white paper|guide|proposal|thesis|prd|spec(ification)?|plan|manual|handbook|ebook|chapter|blog post|case study|research paper)"), 4.0],
    [W("(write|draft|create|prepare|generate) (me )?(a |an |the )?([a-z-]+ ){0,2}(report|document|whitepaper|white paper|proposal|prd|technical spec|design doc|project plan|business plan|research paper|thesis|case study|handbook|manual|ebook|article|essay) (on|about|for|covering)"), 3.4],
    [W("\\d{3,5} ?(words?|pages?)"), 2.0],
    [W("document (ka|ki|ke) (summary|saar)|iska (summary|saar)|summary (do|de|batao|bana)|saar batao|सारांश|सार बताओ|दस्तावेज़ का"), 3.4],
    [W("resume (este|el) (documento|texto|art[ií]culo|pdf)|resumen de|res[uú]menes?|resumir|analiza (este|el) (documento|informe|contrato)"), 3.4],
    [W("fasse (das|den|diese[ns]?|dieses) .{0,30}zusammen|zusammenfassung|zusammenfassen|fass zusammen|fasse zusammen|analysiere (das|den|diese[ns]?) (dokument|bericht|vertrag|text)|bericht [uü]ber"), 3.4],
  ],
  quiz: [
    [W("quiz( me)?|quizzes|test me|test my (knowledge|skills|understanding)|give me a (quiz|test)|make (me )?a quiz|mcqs?|multiple[- ]choice|flash ?cards?|practice (questions?|problems?|test|exam)|mock (test|exam|interview)|question paper|exam prep|revision (questions?|notes)|drill me|grill me|ask me (some )?questions|check my understanding"), 4.0],
    [W("teach me|help me (learn|study|understand|master|practice|revise|prepare)|i (want|wanna|need) to learn|i'?m learning|learning plan|study plan|roadmap to learn|lesson|curriculum|syllabus|learn (about|how|the basics|from scratch)|how can i (get better|improve|master) at|beginner'?s? (guide|course)|crash course|from zero"), 2.8],
    [W("mera quiz|quiz (lo|karo|do|banao)|mujhe (seekhna|sikhna|padhna|padhai)|sikhao|sikha do|seekhna hai|sikhna hai|padhao|revise karna|test lo|सिखाओ|सीखना|क्विज़|क्विज|पढ़ाओ|परीक्षा"), 3.6],
    [W("hazme (un )?(quiz|examen|test|cuestionario)|ens[eé][nñ]ame|quiero aprender|ay[uú]dame a (aprender|estudiar)|pr[aá]ctica|preg[uú]ntame"), 3.6],
    [W("(teste|testet|pr[uü]fe|quizze|quiz) mich|bring mir .{1,30} bei|ich (m[oö]chte|will|muss) .{0,30}lernen|lernplan|[uü]bungsaufgaben|abfragen|lehre mich|frag mich ab"), 3.6],
  ],
  memory: [
    [W("remember (that|this|me|my|i|to|:)|please remember|don'?t forget (that|to|my|i)|keep in mind|note (that|down)|save (this|that|it) (to|in) memory|make a note|add (this )?to (your |my )?memory|from now on|going forward|always (call|address|reply|respond|use|write)|never (call|use|mention|suggest)|forget (that|about|what i)|what do you (remember|know) about me|do you remember|what did i tell you|update (your )?memory|you should know"), 3.8],
    [W("my name is|call me|i am called|i go by|i live in|i'?m (from|based in|living in|currently in)|i work (at|for|as|in)|i'?m (a|an) (software|senior|junior|student|developer|engineer|designer|doctor|teacher|manager|founder|freelancer|intern)|i study|my (birthday|favou?rite|wife|husband|girlfriend|boyfriend|son|daughter|dog|cat|job|company|manager|team|stack|setup|phone|laptop) (is|are|was)|i (prefer|like|love|hate|dislike|use|don'?t eat|can'?t eat|am allergic|am vegetarian|am vegan)"), 2.6],
    [W("yaad rakh|yaad rakhna|yaad rakho|bhoolna mat|bhulna mat|note kar|save kar|mera naam|mujhe .{1,30} pasand|main .{1,20} (mein|me) rehta|main .{1,20} mein kaam|याद रख|याद रखना|याद रखो|भूलना मत|मेरा नाम|मैं .{1,20} में रहता|मुझे .{1,30} पसंद"), 3.8],
    [W("recuerda (que|esto)|no olvides|mi nombre es|me llamo|vivo en|trabajo en|a partir de ahora|olv[ií]date de"), 3.8],
    [W("merk dir|merke dir|vergiss nicht|denk daran|mein name ist|ich hei[sß]e|ich wohne in|ich arbeite (bei|als)|ab jetzt|vergiss (das|dass)"), 3.8],
  ],
  image: [
    [W("images?|pictures?|photos?|photographs?|pics?|illustrations?|drawings?|sketch(es)?|wallpapers?|logos?|icons?|memes?|screenshots?|infographics?|posters?|banners?|thumbnails?|render(ing)? of|artwork|emoji"), 1.8],
    [W("(draw|generate|create|make|paint|design|show|find|get|send|give)( me)?( an?| the| some)? ?(image|picture|photo|pic|illustration|drawing|sketch|logo|icon|poster|banner|thumbnail|wallpaper|meme|infographic|artwork|diagram|portrait|painting)"), 3.6],
    [W("what does .{1,50} look like|how does .{1,50} look|show me what .{1,50} looks like|what('s| is) in (this|the) (image|picture|photo|screenshot)|describe (this|the) (image|picture|photo|screenshot)|look at (this|the) (image|picture|photo|screenshot)|in this (image|picture|photo|screenshot)|what is this (image|picture|photo)"), 3.6],
    [W("tasveer|tasvir|photo (dikhao|dikha|bhejo|banao)|image (dikhao|banao)|pic (dikhao|bhejo)|dikhta kaisa|kaisa dikhta|तस्वीर|फोटो|चित्र|इमेज|दिखाओ"), 3.4],
    [W("imagen|im[aá]genes|foto|fotos|dibujo|dibuja|ilustraci[oó]n|c[oó]mo se ve|c[oó]mo luce|mu[eé]strame"), 3.2],
    [W("bild|bilder|foto|zeichne|illustration|wie sieht .{1,40} aus|zeig mir"), 3.2],
  ],
};

/** Tiny token lexicon (a hand-set linear model over words): token -> label weights. */
const LEXICON: Record<string, Partial<Record<IntentLabel, number>>> = {
  hi: { chitchat: 0.8 }, hello: { chitchat: 0.8 }, hey: { chitchat: 0.8 }, thanks: { chitchat: 0.8 }, lol: { chitchat: 0.8 }, bro: { chitchat: 0.4 },
  explain: { explain: 0.8 }, meaning: { explain: 0.6 }, concept: { explain: 0.6 }, why: { explain: 0.5 }, difference: { compare: 0.8, explain: 0.3 },
  steps: { howto: 0.6 }, guide: { howto: 0.5 }, tutorial: { howto: 0.6 },
  bug: { code: 0.8 }, error: { code: 0.7 }, code: { code: 0.6 }, function: { code: 0.6 }, compile: { code: 0.8 }, regex: { code: 0.8 }, sql: { code: 0.7 }, refactor: { code: 0.9 },
  versus: { compare: 1.0 }, better: { compare: 0.5 }, best: { compare: 0.3, news: 0.1 }, pros: { compare: 0.4 }, cons: { compare: 0.4 },
  email: { write: 0.8 }, draft: { write: 0.9 }, caption: { write: 0.8 }, bio: { write: 0.8 }, rewrite: { write: 0.8 }, letter: { write: 0.7 }, essay: { write: 0.5, longdoc: 0.3 },
  calculate: { math: 0.9 }, solve: { math: 0.8 }, equation: { math: 0.9 }, percent: { math: 0.8 }, sum: { math: 0.5 },
  news: { news: 1.0 }, latest: { news: 0.9 }, today: { news: 0.5 }, breaking: { news: 1.0 }, score: { news: 0.5 },
  github: { github: 1.0 }, repo: { github: 0.9 }, commit: { github: 0.8 }, pr: { github: 0.7 },
  html: { ui: 0.9 }, webpage: { ui: 1.0 }, dashboard: { ui: 0.8 }, landing: { ui: 0.7 }, mockup: { ui: 0.9 },
  summarize: { longdoc: 1.0 }, summary: { longdoc: 0.7 }, document: { longdoc: 0.6 }, report: { longdoc: 0.5 }, pdf: { longdoc: 0.6 }, article: { longdoc: 0.3 },
  quiz: { quiz: 1.0 }, flashcards: { quiz: 1.0 }, mcq: { quiz: 1.0 }, learn: { quiz: 0.7 }, teach: { quiz: 0.8 }, study: { quiz: 0.7 },
  remember: { memory: 0.8 }, forget: { memory: 0.6 },
  image: { image: 1.0 }, picture: { image: 1.0 }, photo: { image: 0.9 }, draw: { image: 0.9 }, logo: { image: 0.7 },
};

const TOKEN_RE = /[\p{L}\p{N}]+/gu;

const WORD_CAP = 3;

/** Raw evidence per label. */
function score(text: string, opts: IntentOpts): Record<IntentLabel, number> {
  const s = Object.fromEntries(INTENTS.map((l) => [l, 0])) as Record<IntentLabel, number>;
  const words = text.match(TOKEN_RE) ?? [];
  const nWords = words.length;
  const hasFence = /```/.test(text);

  for (const label of INTENTS) {
    // Strongest feature in full, the rest at diminishing weight (many overlapping cues are not many times the evidence).
    const hits: number[] = [];
    for (const [re, w] of FEATURES[label]) {
      if (!re.test(text)) continue;
      // Greeting words only carry weight in short messages; in long ones they are just politeness.
      hits.push(label === "chitchat" && w < 3 ? (nWords <= 6 ? w : nWords <= 12 ? 0.3 : 0) : w);
    }
    hits.sort((a, b) => b - a);
    s[label] += hits.reduce((acc, w, i) => acc + w * (i === 0 ? 1 : i === 1 ? 0.5 : 0.25), 0);
  }

  // Lexicon: each distinct token once; capped so a long text does not drown the rules.
  const seen = new Set<string>();
  const lex = Object.fromEntries(INTENTS.map((l) => [l, 0])) as Record<IntentLabel, number>;
  for (const raw of words) {
    const w = raw.toLowerCase();
    if (seen.has(w)) continue;
    seen.add(w);
    const e = LEXICON[w];
    if (!e) continue;
    for (const [l, v] of Object.entries(e) as [IntentLabel, number][]) lex[l] += v;
  }
  for (const l of INTENTS) s[l] += Math.min(WORD_CAP, lex[l]);

  // Structure.
  if (hasFence) s.code += 1.5;
  if (!hasFence) {
    if (text.length > 6000) s.longdoc += 4;
    else if (text.length > 2500) s.longdoc += 2.5;
    else if (text.length > 1200 && s.longdoc > 0) s.longdoc += 1;
  }
  if (/[\p{L}\p{N}]+\s*\?\s*$/u.test(text) && nWords >= 3) s.explain += 0.3;
  if (opts.hasImages) s.image += 3.5;
  if (opts.hasAttachments && s.longdoc > 0) s.longdoc += 2;
  if (needsFreshFacts(text.slice(0, 400))) s.news += 1.6;
  // "latest"/"today" next to a code term is usually about a version, not news.
  if (s.code >= 3 && s.news < 4) s.news *= 0.6;
  // A GitHub question is more specific than generic code talk.
  if (s.github >= 3.4) s.code *= 0.7;
  // "write ..." that names a document type is writing, not code or UI.
  if (s.write >= 3.6 && !hasFence) s.code *= 0.6;
  // A request to build a page is UI, not generic code.
  if (s.ui >= 3.6 && !hasFence) s.code *= 0.55;
  // Explicit memory statements beat the generic explain/howto cues.
  if (s.memory >= 3.8) {
    s.explain *= 0.5;
    s.howto *= 0.5;
  }
  // How-to questions mentioning a tool are about the task, not about code/debugging.
  if (s.howto >= 2.4 && !hasFence && s.code < 3.2) s.code *= 0.6;
  // Specific asks win over the generic "what/why" explanation cues.
  if (s.compare >= 3) s.explain *= 0.6;
  if (s.math >= 3 || s.image >= 3.4 || s.news >= 3 || s.github >= 3) s.explain *= 0.6;
  // Repo questions say "recent"/"latest" about commits, not about the news.
  if (s.github >= 3 && s.news < 6) s.news *= 0.55;
  // Quiz asks win over "learn" explanations.
  if (s.quiz >= 4) s.explain *= 0.5;
  return s;
}

const squash = (x: number) => 1 - Math.exp(-x / 2.2);
const round = (n: number) => Math.round(n * 1000) / 1000;

export function classifyIntent(input: string, opts: IntentOpts = {}): IntentResult {
  const text = capTokens((input ?? "").slice(0, 8000)).trim();
  if (!text) return { top: opts.hasAttachments ? "longdoc" : "chitchat", confidence: 0.2, labels: [], uncertain: true };
  const raw = score(text, opts);
  const ranked = INTENTS.map((l) => ({ label: l, raw: raw[l] })).sort((a, b) => b.raw - a.raw);
  const best = ranked[0]!;
  const second = ranked[1]!;
  const nWords = (text.match(TOKEN_RE) ?? []).length;

  if (best.raw < 1.2) {
    const top: IntentLabel = /\?\s*$/.test(text) || nWords > 4 ? "explain" : "chitchat";
    return { top, confidence: 0.25, labels: [{ label: top, score: 0.25 }], uncertain: true };
  }
  const margin = best.raw > 0 ? 1 - 0.8 * Math.min(1, second.raw / best.raw) : 0;
  const confidence = round(squash(best.raw) * margin);
  const labels = ranked
    .filter((r) => r.raw >= 1.5 && r.raw >= best.raw * 0.4)
    .map((r) => ({ label: r.label, score: round(squash(r.raw)) }));
  return { top: best.label, confidence, labels, uncertain: confidence < 0.5 };
}

export const hasIntent = (r: IntentResult, label: IntentLabel, min = 0.5): boolean => r.labels.some((l) => l.label === label && l.score >= min);

// ---- consumers ---------------------------------------------------------------------

/** Intents that never need the live web. */
const OFFLINE: IntentLabel[] = ["chitchat", "code", "math", "write", "memory", "ui", "quiz", "longdoc"];

/**
 * Whether the web is needed, when the classifier is sure: "search" for news,
 * "skip" for chit-chat/code/math/writing, "ask" when a model should decide.
 */
export function webVerdict(r: IntentResult): "search" | "skip" | "ask" {
  if (r.uncertain || r.confidence < 0.6) return "ask";
  if (r.top === "news") return "search";
  if (OFFLINE.includes(r.top) && !hasIntent(r, "news", 0.4)) return "skip";
  return "ask";
}

/** A response length/shape hint, or null when the default is right. */
export function shapeHint(r: IntentResult): string | null {
  if (r.uncertain) return null;
  switch (r.top) {
    case "chitchat":
      return "This is small talk: reply in one to three short, natural sentences. No headings, lists or widgets.";
    case "math":
      return "This is a calculation: give the result first, then at most a few short lines of working.";
    case "howto":
      return r.confidence >= 0.6 ? "This is a how-to: give the steps as a short numbered list, one action per step." : null;
    default:
      return null;
  }
}
