// Rule- and gazetteer-based entity extraction. Pure, local and fast (a few
// regex passes plus one token scan). Entities feed exact-match boosting in RAG
// keyword search, quoted names in web query planning, GitHub repo lookup and
// memory extraction hints.

export type EntityType =
  | "repo"
  | "url"
  | "email"
  | "phone"
  | "date"
  | "version"
  | "path"
  | "identifier"
  | "money"
  | "tech"
  | "person"
  | "org"
  | "name";

export type Entity = {
  type: EntityType;
  /** As written in the text. */
  text: string;
  /** Normalised form: ISO date, canonical tech name, "owner/repo", number+currency... */
  value: string;
  index: number;
};

const MAX_CHARS = 4000;

/** Truncates any unbroken run of non-space characters, which bounds regex backtracking on junk input. */
export function capTokens(s: string, max = 100): string {
  return s.replace(new RegExp(`\\S{${max + 1},}`, "g"), (m) => m.slice(0, max));
}

// ---- gazetteers -------------------------------------------------------------------

/** Case-insensitive tech terms (canonical spelling is the value). */
const TECH = [
  "JavaScript", "TypeScript", "Python", "Java", "Kotlin", "Dart", "Flutter", "React", "React Native", "Next.js", "Vue", "Vue.js", "Angular", "Svelte",
  "Node.js", "Deno", "Bun", "Express", "NestJS", "Django", "Flask", "FastAPI", "Spring Boot", "Laravel", "Rails", "Ruby on Rails", "Golang", "Rust",
  "C++", "C#", ".NET", "PHP", "Ruby", "Scala", "Elixir", "Haskell", "Swift", "SwiftUI", "Jetpack Compose", "Android", "iOS", "Linux", "Ubuntu", "Debian",
  "macOS", "Windows", "Docker", "Kubernetes", "Terraform", "Ansible", "Nginx", "Apache", "Redis", "PostgreSQL", "Postgres", "MySQL", "MariaDB", "SQLite",
  "MongoDB", "Cassandra", "Elasticsearch", "Kafka", "RabbitMQ", "GraphQL", "gRPC", "REST", "WebSocket", "OAuth", "JWT", "Prisma", "Drizzle", "pgvector",
  "Supabase", "Firebase", "Vercel", "Netlify", "Cloudflare", "AWS", "Azure", "GCP", "Google Cloud", "DigitalOcean", "Heroku", "Coolify", "GitHub", "GitLab",
  "Bitbucket", "Git", "npm", "pnpm", "Yarn", "Webpack", "Vite", "Babel", "ESLint", "Prettier", "Jest", "Vitest", "Playwright", "Cypress", "Tailwind",
  "Tailwind CSS", "Bootstrap", "Sass", "CSS", "HTML", "SQL", "NoSQL", "Bash", "PowerShell", "Vim", "Neovim", "VS Code", "Visual Studio Code", "IntelliJ",
  "Android Studio", "Xcode", "Figma", "Postman", "Jira", "Notion", "Slack", "Discord", "Telegram", "WhatsApp", "TensorFlow", "PyTorch", "Keras", "NumPy",
  "Pandas", "scikit-learn", "Jupyter", "LangChain", "LlamaIndex", "Hugging Face", "Ollama", "OpenAI", "ChatGPT", "GPT-4", "GPT-5", "Claude", "Claude Code",
  "Anthropic", "Gemini", "Llama", "Mistral", "Groq", "Nvidia", "CUDA", "RAG", "LLM", "Raspberry Pi", "Arduino", "ESP32", "Wi-Fi", "Bluetooth", "Kubernetes",
  "Helm", "Grafana", "Prometheus", "Sentry", "Stripe", "Razorpay", "UPI", "Paytm", "PhonePe", "Aadhaar", "GST", "Excel", "Google Sheets", "PowerPoint",
  "Photoshop", "Blender", "Unity", "Unreal Engine", "Godot", "Zustand", "Redux", "Riverpod", "Bloc", "Dio", "Hive", "Pub", "Gradle", "Maven", "Cargo",
  "Homebrew", "Nix", "WebAssembly", "WASM", "Electron", "Tauri", "Deno Deploy", "Hono", "Fastify", "Remix", "Astro", "Nuxt", "SvelteKit", "Zod", "tRPC",
  "Axios", "Socket.IO", "Mermaid", "Markdown", "JSON", "YAML", "TOML", "Protobuf", "MCP", "iPhone", "iPad", "MacBook", "Pixel", "Galaxy", "Chrome", "Firefox",
  "Safari", "Edge",
];

/** Words that are only a tech name when written exactly like this (they are common words otherwise). */
const TECH_CASED = new Set(["Go", "Rust", "Swift", "Express", "Spring", "Rails", "Ruby", "Dart", "Bun", "Edge", "Pixel", "Galaxy", "Helm", "Nix", "Pub", "Hive", "Bloc", "Claude", "Gemini", "Llama", "Safari", "Chrome", "Android", "Git", "Cargo", "Windows", "Unity", "Notion", "Slack", "Discord", "Mistral", "Remix", "Astro", "Hono", "Zod", "Dio", "REST", "RAG"]);

const TECH_MAP = new Map<string, string>();
for (const t of TECH) TECH_MAP.set(t.toLowerCase(), t);
for (const [k, v] of Object.entries({ js: "JavaScript", ts: "TypeScript", node: "Node.js", nodejs: "Node.js", reactjs: "React", nextjs: "Next.js", vuejs: "Vue.js", expressjs: "Express", golang: "Golang", k8s: "Kubernetes", postgresql: "PostgreSQL", pg: "PostgreSQL", gh: "GitHub", vscode: "VS Code", "c-sharp": "C#", tailwindcss: "Tailwind CSS", sklearn: "scikit-learn", huggingface: "Hugging Face" })) {
  TECH_MAP.set(k, v);
}
// "go" alone is a verb: only "Golang" counts, and "Go" exactly (handled via TECH_CASED + the capitalised check).
TECH_MAP.set("go", "Go");

const ORGS = [
  "Google", "Microsoft", "Apple", "Amazon", "Meta", "Facebook", "Netflix", "Tesla", "SpaceX", "NASA", "ISRO", "DRDO", "IBM", "Intel", "AMD", "Samsung",
  "Infosys", "TCS", "Wipro", "HCL", "Reliance", "Tata", "Flipkart", "Zomato", "Swiggy", "Ola", "Paytm", "Zerodha", "Mozilla", "Oracle", "Adobe", "Uber",
  "Twitter", "LinkedIn", "YouTube", "Instagram", "Reddit", "Wikipedia", "RBI", "SEBI", "UNESCO", "WHO", "UN", "IIT", "IIM", "NIT", "BCCI", "FIFA", "OpenAI", "Anthropic",
];
const ORG_MAP = new Map(ORGS.map((o) => [o.toLowerCase(), o]));
const ORG_SUFFIX = /^(Inc|Ltd|Limited|Corp|Corporation|LLC|LLP|Pvt|Technologies|Technology|Labs|Systems|Solutions|University|Institute|College|Bank|Foundation|Association|Group|Company|Co|Studios|Ventures|Industries|Airlines|Hospital|School)\.?$/;
const TITLES = /^(Mr|Mrs|Ms|Miss|Dr|Prof|Sir|Shri|Smt|Sri|Mx)\.?$/;

/** Capitalised words that are not names (sentence starters, days, months, pronouns). */
const NOT_NAME = new Set(
  (
    "i i'm i've i'll i'd the a an this that these those it its is are was were be been am do does did how what why when where which who whom whose can could would should will shall may might must " +
    "please hi hello hey hola hallo thanks thank ok okay yes no not and or but so if then also just now here there let lets let's tell show give make write explain help find get need want " +
    "my our your his her their me us you we they he she monday tuesday wednesday thursday friday saturday sunday january february march april may june july august september october november december " +
    "today tomorrow yesterday tonight good best new old first next last some any all every each more most very much many few one two three about after before because with without for from into over under " +
    "dear regards best sincerely subject note remember suppose imagine consider assume create build fix debug add remove delete update upgrade install run use using try check compare list summarize translate " +
    "mujhe mera meri mere kya kaise kyun kyu kab kahan kaun aap tum main hum bhai yaar bro ek aur hai hain nahi haan por para como que cuando donde quien ich wie was warum wann wo wer und oder mit bitte danke"
  ).split(" "),
);

const MONTHS = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?";
const MONTH_IDX = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

const FILE_EXT = "ts|tsx|jsx|mjs|cjs|py|md|json|ya?ml|toml|txt|css|scss|html|sh|rs|go|java|kt|dart|c|cc|cpp|h|hpp|rb|php|swift|sql|lock|env|xml|gradle|csv|log|conf|ini|pdf|docx?|xlsx?|png|jpe?g|svg|ipynb|js";

// ---- helpers ----------------------------------------------------------------------

type Span = [number, number];
class Claims {
  private spans: Span[] = [];
  free(s: number, e: number): boolean {
    return !this.spans.some(([a, b]) => s < b && e > a);
  }
  claim(s: number, e: number): void {
    this.spans.push([s, e]);
  }
}

const pad = (n: number) => String(n).padStart(2, "0");
const iso = (d: Date) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
function addDays(base: Date, n: number): Date {
  const d = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate()));
  d.setUTCDate(d.getUTCDate() + n);
  return d;
}
function monthNo(s: string): number {
  return MONTH_IDX.indexOf(s.slice(0, 3).toLowerCase()) + 1;
}

// ---- patterns ---------------------------------------------------------------------

const URL_RE = /\b(?:https?:\/\/|www\.)[^\s<>"'`)\]]+/gi;
const EMAIL_RE = /[\w.+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+/g;
const GH_URL_RE = /github\.com\/([A-Za-z0-9][\w-]{0,38})\/([\w.-]{1,100})/i;
const GH_RESERVED = new Set(["orgs", "topics", "search", "settings", "features", "marketplace", "sponsors", "collections", "about", "pricing", "login"]);
const GH_CONTEXT = /\b(github|gh|repo|repos|repository|repositories|clone|fork|star|stars|commit|commits|pull request|issue|issues|branch|readme|open[- ]?source)\b/i;
const BARE_REPO_RE = /(?<![\w./@:\\-])([A-Za-z0-9][\w-]{0,38})\/([A-Za-z0-9_.-]{2,100})(?![\w/])/g;
const DIR_FIRST = new Set(["src", "lib", "app", "apps", "test", "tests", "docs", "doc", "backend", "frontend", "node_modules", "dist", "build", "public", "assets", "etc", "usr", "var", "home", "bin", "opt", "tmp", "utils", "components", "pages", "routes", "scripts", "config", "packages", "static", "images", "img", "css", "js", "api", "prisma", "migrations", "controllers", "models", "services", "hooks", "styles", "types", "templates", "views", "cmd", "internal", "pkg", "include", "target", "out"]);
const PATH_FIRST = new Set(["src", "lib", "app", "apps", "test", "tests", "docs", "doc", "backend", "frontend", "node_modules", "dist", "build", "public", "assets", "etc", "usr", "var", "home", "bin", "opt", "tmp", "utils", "components", "pages", "routes", "scripts", "config", "packages", "static", "images", "img", "css", "js", "api", "and", "or", "w", "o", "tcp", "ip", "input", "output", "read", "write", "client", "server", "yes", "no", "true", "false", "his", "her", "he", "she", "km", "kg", "mb", "gb", "min", "sec", "hr"]);
const PATH_RE = new RegExp(
  String.raw`(?<![\w@])(?:(?:~|\.{1,2})?\/)?(?:[\w.@-]+\/)+[\w.@-]*\w(?![\w/])|(?<![\w/@.-])[\w-]+(?:\.[\w-]+)*\.(?:${FILE_EXT})(?![\w/-])|[A-Za-z]:\\(?:[\w .-]+\\)*[\w.-]+`,
  "g",
);
const VERSION_RE = /(?<![\w.])(v\d+(?:\.\d+){0,3}(?:-[\w.]+)?|\d+\.\d+\.\d+(?:\.\d+)?(?:-[\w.]+)?)(?![\w.]*\d)(?![.]\d)/g;
const NAMED_VERSION_RE = /\b(python|node(?:\.?js)?|java|go|golang|rust|ruby|php|react|vue|angular|flutter|dart|django|rails|ubuntu|android|ios|macos|windows|postgres(?:ql)?|mysql|docker|kubernetes|typescript|swift|kotlin|next(?:\.js)?|version|ver|release|v)\s+(\d+(?:\.\d+){1,3})(?![\w.]*\d)/gi;
const MONEY_RE = new RegExp(
  String.raw`(?:(?:₹|\$|€|£|Rs\.?|INR|USD|EUR|GBP)\s?\d[\d,]*(?:\.\d+)?(?:\s?(?:k|m|bn|b|lakhs?|crores?|cr|million|billion|thousand)\b)?)|(?:\b\d[\d,]*(?:\.\d+)?\s?(?:rupees|rs|dollars|euros|usd|inr|eur|bucks|lakhs?|crores?)\b)`,
  "gi",
);
const PHONE_RE = /(?<![\w.])(?:\+\d{1,3}[\s-]?)?(?:\(\d{2,5}\)[\s-]?)?\d[\d\s-]{7,14}\d(?!\w)(?!\.\d)/g;
const ISO_DATE_RE = /\b(\d{4})-(\d{2})-(\d{2})\b/g;
const NUM_DATE_RE = /\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})\b/g;
const DMY_RE = new RegExp(String.raw`\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(${MONTHS})\.?(?:,?\s+(\d{4}))?\b`, "gi");
const MDY_RE = new RegExp(String.raw`\b(${MONTHS})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b`, "gi");
const MY_RE = new RegExp(String.raw`\b(${MONTHS})\.?\s+(\d{4})\b`, "gi");
const REL_RE = new RegExp(
  String.raw`\b(?:day after tomorrow|day before yesterday|tomorrow|yesterday|today|tonight|(?:next|last|this|coming)\s+(?:week|month|year|weekend|${WEEKDAYS.join("|")})|(?:on\s+)?(?:${WEEKDAYS.join("|")})|in\s+\d+\s+(?:days?|weeks?|months?|years?|hours?)|\d+\s+(?:days?|weeks?|months?|years?)\s+ago|end of (?:the )?(?:month|year|week)|aaj|parso|kal)\b`,
  "gi",
);
const YEAR_RE = /\b(?:19|20)\d{2}\b/g;
const CAMEL_RE = /\b[a-z]+(?:[A-Z][a-z0-9]+)+\b|\b[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\b/g;
const SNAKE_RE = /\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b/g;
const CONST_RE = /\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b/g;
const CALL_RE = /\b[A-Za-z_][\w.]*\(\)/g;
const BACKTICK_RE = /`([^`\n]{2,60})`/g;

function resolveRelative(phrase: string, now: Date): string {
  const p = phrase.toLowerCase().replace(/^on\s+/, "");
  const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  if (p === "today" || p === "tonight" || p === "aaj") return iso(today);
  if (p === "tomorrow") return iso(addDays(today, 1));
  if (p === "yesterday") return iso(addDays(today, -1));
  if (p === "day after tomorrow" || p === "parso") return iso(addDays(today, 2));
  if (p === "day before yesterday") return iso(addDays(today, -2));
  let m = p.match(/^in (\d+) (day|week|month|year|hour)s?$/);
  if (m) {
    const n = Number(m[1]);
    return iso(unitShift(today, m[2]!, n));
  }
  m = p.match(/^(\d+) (day|week|month|year)s? ago$/);
  if (m) return iso(unitShift(today, m[1] ? m[2]! : "day", -Number(m[1])));
  m = p.match(/^(next|last|this|coming) (week|month|year|weekend)$/);
  if (m) {
    const dir = m[1] === "last" ? -1 : m[1] === "this" ? 0 : 1;
    if (m[2] === "weekend") return iso(addDays(today, ((6 - today.getUTCDay() + 7) % 7) + (dir === 1 ? 7 : 0)));
    return iso(unitShift(today, m[2]!, dir));
  }
  m = p.match(/^(?:(next|last|this|coming)\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)$/);
  if (m) {
    const target = WEEKDAYS.indexOf(m[2]!);
    const cur = today.getUTCDay();
    if (m[1] === "last") return iso(addDays(today, -(((cur - target + 6) % 7) + 1)));
    let diff = (target - cur + 7) % 7;
    if (m[1] === "next" && diff === 0) diff = 7;
    return iso(addDays(today, diff));
  }
  m = p.match(/^end of (?:the )?(month|year|week)$/);
  if (m) {
    if (m[1] === "month") return iso(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 0)));
    if (m[1] === "year") return `${today.getUTCFullYear()}-12-31`;
    return iso(addDays(today, (7 - today.getUTCDay()) % 7));
  }
  return "";
}
function unitShift(d: Date, unit: string, n: number): Date {
  if (unit === "hour") return d;
  if (unit === "day") return addDays(d, n);
  if (unit === "week") return addDays(d, n * 7);
  const out = new Date(d);
  if (unit === "month") out.setUTCMonth(out.getUTCMonth() + n);
  else out.setUTCFullYear(out.getUTCFullYear() + n);
  return out;
}

const year4 = (y: string | undefined, now: Date) => (y ? (y.length === 2 ? `20${y}` : y) : String(now.getUTCFullYear()));

// ---- extraction -------------------------------------------------------------------

export function extractEntities(input: string, now = new Date()): Entity[] {
  const text = capTokens((input ?? "").slice(0, MAX_CHARS));
  if (!text.trim()) return [];
  const out: Entity[] = [];
  const claims = new Claims();
  const push = (type: EntityType, s: number, e: number, value?: string, claim = true): void => {
    if (!claims.free(s, e)) return;
    if (claim) claims.claim(s, e);
    const raw = text.slice(s, e);
    out.push({ type, text: raw, value: value ?? raw, index: s });
  };
  const scan = (re: RegExp, fn: (m: RegExpMatchArray, s: number, e: number) => void) => {
    re.lastIndex = 0;
    for (const m of text.matchAll(re)) fn(m, m.index!, m.index! + m[0].length);
  };

  // 1. urls and emails (also yield repos)
  scan(URL_RE, (m, s) => {
    const url = m[0].replace(/[.,;:!?]+$/, "");
    const e = s + url.length;
    const gh = url.match(GH_URL_RE);
    if (gh && !GH_RESERVED.has(gh[1]!.toLowerCase())) {
      const repo = gh[2]!.replace(/\.git$/, "").replace(/[.,;:]+$/, "");
      out.push({ type: "repo", text: `${gh[1]}/${repo}`, value: `${gh[1]}/${repo}`, index: s });
    }
    push("url", s, e, url);
  });
  scan(EMAIL_RE, (m, s, e) => push("email", s, e, m[0].toLowerCase()));

  // 2. money before phone/version so "$1,200.50" is not a number run
  scan(MONEY_RE, (m, s, e) => push("money", s, e, normaliseMoney(m[0])));

  // 3. dates (absolute first, then relative)
  scan(ISO_DATE_RE, (m, s, e) => push("date", s, e, m[0]));
  scan(NUM_DATE_RE, (m, s, e) => {
    const [a, b] = [Number(m[1]), Number(m[2])];
    // dd/mm/yyyy (India, Europe); fall back to mm/dd when the first part cannot be a day-of-month > 12 rule.
    const [d, mo] = b > 12 ? [b, a] : [a, b];
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return;
    push("date", s, e, `${year4(m[3], now)}-${pad(mo)}-${pad(d)}`);
  });
  scan(DMY_RE, (m, s, e) => push("date", s, e, `${year4(m[3], now)}-${pad(monthNo(m[2]!))}-${pad(Number(m[1]))}`));
  scan(MDY_RE, (m, s, e) => push("date", s, e, `${year4(m[3], now)}-${pad(monthNo(m[1]!))}-${pad(Number(m[2]))}`));
  scan(MY_RE, (m, s, e) => push("date", s, e, `${m[2]}-${pad(monthNo(m[1]!))}`));
  scan(REL_RE, (m, s, e) => {
    const v = resolveRelative(m[0], now);
    // "kal" is yesterday or tomorrow; "may" style ambiguities are filtered by the regexes above.
    if (v) push("date", s, e, v);
    else if (/^kal$/i.test(m[0])) push("date", s, e, "");
  });

  // 4. versions
  scan(NAMED_VERSION_RE, (m, s, e) => {
    const vs = e - m[2]!.length;
    push("version", vs, e, m[2]);
  });
  scan(VERSION_RE, (m, s, e) => {
    const v = m[1]!;
    if (!v.startsWith("v")) {
      const parts = v.split(".");
      // IPs (four small numeric parts) and dd.mm.yyyy dates are not versions.
      if (parts.length === 4 && parts.every((p) => /^\d{1,3}$/.test(p) && Number(p) <= 255)) return;
      if (parts.length === 3 && /^\d{4}$/.test(parts[2]!)) return;
    }
    push("version", s, e, v.replace(/^v/, ""));
  });

  // 5. repos (before paths: "vercel/next.js")
  const ghContext = GH_CONTEXT.test(text);
  scan(BARE_REPO_RE, (m, s, e) => {
    const [owner, repoRaw] = [m[1]!, m[2]!];
    const repo = repoRaw.replace(/\.git$/, "").replace(/[.,;:]+$/, "");
    if (!claims.free(s, e)) return;
    if (/^\d+$/.test(owner) || /^\d+$/.test(repo) || owner.length < 2) return;
    if (PATH_FIRST.has(owner.toLowerCase()) || PATH_FIRST.has(repo.toLowerCase())) return;
    if (new RegExp(`\\.(?:${FILE_EXT.replace("|js", "")})$`, "i").test(repo)) return;
    if (!ghContext && !/^[a-z0-9][\w-]*$/i.test(owner)) return;
    // Without GitHub wording, "a/b" is far more often a slash phrase than a repo.
    if (!ghContext && (owner.length < 3 || !/[a-z]/.test(owner) || /^[A-Z]+$/.test(owner))) return;
    push("repo", s, s + owner.length + 1 + repo.length, `${owner}/${repo}`);
  });

  // 6. phones: 10-15 digits in total, not already a date/version/money
  scan(PHONE_RE, (m, s, e) => {
    const digits = m[0].replace(/\D/g, "");
    if (digits.length < 10 || digits.length > 15) return;
    if (!claims.free(s, e)) return;
    push("phone", s, e, (m[0].trim().startsWith("+") ? "+" : "") + digits);
  });

  // 7. paths
  scan(PATH_RE, (m, s, e) => {
    const p = m[0];
    // a bare "a.b" word is only a path when it ends in a known file extension (guaranteed by the regex branch)
    if (/^https?:/i.test(p) || /^\d+(\.\d+)+$/.test(p) || TECH_MAP.has(p.toLowerCase())) return;
    // "a/b" without an extension or leading ./ is a slash phrase or an owner/repo (handled above) unless it starts with a real directory.
    if (/^[\w-]+\/[\w-]+$/.test(p) && !DIR_FIRST.has(p.split("/")[0]!.toLowerCase())) return;
    push("path", s, e, p);
  });

  // 8. bare years (after everything numeric)
  scan(YEAR_RE, (m, s, e) => push("date", s, e, m[0]));

  // 9. code identifiers
  scan(BACKTICK_RE, (m, s, e) => push("identifier", s, e, m[1]!.trim()));
  scan(CALL_RE, (m, s, e) => push("identifier", s, e, m[0]));
  scan(CONST_RE, (m, s, e) => push("identifier", s, e, m[0]));
  scan(SNAKE_RE, (m, s, e) => push("identifier", s, e, m[0]));
  scan(CAMEL_RE, (m, s, e) => {
    // Brand-style PascalCase words that the gazetteer knows are tech, not identifiers.
    if (TECH_MAP.has(m[0].toLowerCase())) return;
    push("identifier", s, e, m[0]);
  });

  // 10. tech terms, orgs and names via a token scan
  extractNamed(text, claims, push);

  out.sort((a, b) => a.index - b.index || a.type.localeCompare(b.type));
  return out;
}

function normaliseMoney(raw: string): string {
  const cur = /₹|rs\.?|inr|rupees|lakh|crore|\bcr\b/i.test(raw) ? "INR" : /€|eur|euros/i.test(raw) ? "EUR" : /£|gbp/i.test(raw) ? "GBP" : "USD";
  let n = Number((raw.match(/\d[\d,]*(?:\.\d+)?/)?.[0] ?? "0").replace(/,/g, ""));
  const unit = raw.toLowerCase();
  if (/lakhs?/.test(unit)) n *= 100_000;
  else if (/crores?|\bcr\b/.test(unit)) n *= 10_000_000;
  else if (/billion|\bbn\b|\d\s?b\b/.test(unit)) n *= 1e9;
  else if (/million|\d\s?m\b/.test(unit)) n *= 1e6;
  else if (/thousand|\d\s?k\b/.test(unit)) n *= 1e3;
  return `${cur} ${n}`;
}

const TOKEN_RE = /[\p{L}\p{N}][\p{L}\p{N}.+#_'-]*/gu;

function extractNamed(text: string, claims: Claims, push: (type: EntityType, s: number, e: number, value?: string, claim?: boolean) => void): void {
  type Tok = { w: string; s: number; e: number };
  const toks: Tok[] = [];
  for (const m of text.matchAll(TOKEN_RE)) {
    let w = m[0].replace(/[.'-]+$/, "");
    // keep "Node.js", "C++", "C#", ".NET"; strip a trailing sentence dot
    if (!w) continue;
    toks.push({ w, s: m.index!, e: m.index! + w.length });
  }
  // ".NET" starts with a dot, which the token regex skips.
  for (const m of text.matchAll(/(?<![\w])\.NET\b/g)) push("tech", m.index!, m.index! + 4, ".NET");

  const atSentenceStart = (i: number): boolean => {
    if (i === 0) return true;
    const gap = text.slice(toks[i - 1]!.e, toks[i]!.s);
    return /[.!?\n:]\s*$/.test(gap) || /^\s*["'(]?$/.test(gap) && /[.!?]$/.test(text.slice(0, toks[i]!.s).trimEnd());
  };

  const used = new Set<number>();
  for (let i = 0; i < toks.length; i++) {
    if (used.has(i)) continue;
    const t = toks[i]!;
    // bigram tech/org ("Spring Boot", "Google Cloud", "VS Code")
    const next = toks[i + 1];
    if (next && /^\s{1,2}$/.test(text.slice(t.e, next.s))) {
      const bi = `${t.w} ${next.w}`.toLowerCase();
      const tech = TECH_MAP.get(bi);
      if (tech && claims.free(t.s, next.e)) {
        push("tech", t.s, next.e, tech);
        used.add(i).add(i + 1);
        continue;
      }
    }
    const lower = t.w.toLowerCase();
    const tech = TECH_MAP.get(lower);
    if (tech) {
      // Ambiguous words need the canonical capitalisation and must not just be a sentence opener.
      const ambiguous = TECH_CASED.has(tech);
      const ok = !ambiguous || (t.w === tech && !(atSentenceStart(i) && !isTechContext(text)));
      if (ok && claims.free(t.s, t.e)) {
        push("tech", t.s, t.e, tech);
        used.add(i);
        continue;
      }
    }
    const org = ORG_MAP.get(lower);
    const nextCap = next && /^\s{1,2}$/.test(text.slice(t.e, next.s)) && (ORG_SUFFIX.test(next.w) || /^\p{Lu}/u.test(next.w) && !NOT_NAME.has(next.w.toLowerCase()));
    if (org && !nextCap && (t.w === org || /^[A-Z]+$/.test(t.w))) {
      if (claims.free(t.s, t.e)) push("org", t.s, t.e, org);
      used.add(i);
      continue;
    }
  }

  // capitalised phrases: runs of Capitalised words (people / orgs)
  const cap = (w: string) => /^\p{Lu}[\p{Ll}'’-]+$/u.test(w) || /^\p{Lu}\.$/u.test(w);
  for (let i = 0; i < toks.length; i++) {
    if (used.has(i)) continue;
    const t = toks[i]!;
    if (!cap(t.w) && !/^[A-Z]{2,6}$/.test(t.w)) continue;
    let j = i;
    while (j + 1 < toks.length && !used.has(j + 1) && cap(toks[j + 1]!.w) && /^[ \t]{1,2}$/.test(text.slice(toks[j]!.e, toks[j + 1]!.s))) j++;
    const words = toks.slice(i, j + 1).map((x) => x.w);
    // drop leading sentence starters / stop words from the run
    let from = 0;
    while (from < words.length && NOT_NAME.has(words[from]!.toLowerCase())) from++;
    const run = words.slice(from);
    const first = i + from;
    if (run.length === 0) {
      i = j;
      continue;
    }
    const s = toks[first]!.s;
    const e = toks[j]!.e;
    if (!claims.free(s, e)) {
      i = j;
      continue;
    }
    const phrase = text.slice(s, e);
    if (run.length === 1) {
      const w = run[0]!;
      const start = atSentenceStart(first);
      if (start || w.length < 3 || NOT_NAME.has(w.toLowerCase()) || MONTH_IDX.includes(w.slice(0, 3).toLowerCase()) && /^(January|February|March|April|May|June|July|August|September|October|November|December)$/.test(w)) {
        i = j;
        continue;
      }
      if (/^[A-Z]{2,6}$/.test(w)) {
        push("org", s, e, w);
      } else if (!WEEKDAYS.includes(w.toLowerCase())) {
        push("name", s, e, w);
      }
    } else {
      const last = run[run.length - 1]!;
      const hasTitle = TITLES.test(run[0]!);
      const orgish = ORG_SUFFIX.test(last) || run.some((x) => ORG_MAP.has(x.toLowerCase()));
      if (orgish) push("org", s, e, phrase);
      else if (hasTitle || run.length <= 3) push("person", s, e, phrase.replace(/^(?:Mr|Mrs|Ms|Miss|Dr|Prof|Sir|Shri|Smt|Sri|Mx)\.?\s+/, ""));
      else push("org", s, e, phrase);
    }
    i = j;
  }
}

function isTechContext(text: string): boolean {
  return /\b(code|coding|programming|framework|library|language|install|npm|server|backend|api|compile|build|app)\b/i.test(text);
}

// ---- consumers --------------------------------------------------------------------

/** Entities worth matching exactly in a keyword search or quoting in a web query. */
export function exactTerms(entities: Entity[], opts: { max?: number } = {}): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const e of entities) {
    if (e.type === "date" || e.type === "money" || e.type === "phone" || e.type === "url" || e.type === "name") continue;
    const term = e.type === "tech" || e.type === "person" || e.type === "org" ? e.value : e.type === "version" ? e.value : e.value;
    const key = term.toLowerCase();
    if (!term || seen.has(key)) continue;
    seen.add(key);
    out.push(term);
    if (out.length >= (opts.max ?? 6)) break;
  }
  return out;
}

/** Multi-word names and owner/repo pairs: what a search engine should treat as one unit. */
export function quotableNames(entities: Entity[]): string[] {
  const out: string[] = [];
  for (const e of entities) {
    if ((e.type === "person" || e.type === "org" || e.type === "tech") && /\s/.test(e.value)) out.push(e.value);
    else if (e.type === "repo") out.push(e.value);
  }
  return [...new Set(out)];
}

/** Wraps known multi-word names in quotes inside a search query (once, case-insensitively). */
export function quoteNames(query: string, entities: Entity[]): string {
  let q = query;
  for (const name of quotableNames(entities)) {
    const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`(?<!["\\w])${esc}(?!["\\w])`, "i");
    if (re.test(q)) q = q.replace(re, (m) => `"${m}"`);
  }
  return q;
}

export function repoEntities(entities: Entity[]): { owner: string; repo: string }[] {
  return entities
    .filter((e) => e.type === "repo")
    .map((e) => {
      const [owner, repo] = e.value.split("/");
      return { owner: owner!, repo: repo! };
    });
}

/** A few well-known projects, so "the React repo" can be resolved to facebook/react. */
export const KNOWN_REPOS: Record<string, string> = {
  react: "facebook/react",
  vue: "vuejs/core",
  angular: "angular/angular",
  svelte: "sveltejs/svelte",
  "next.js": "vercel/next.js",
  flutter: "flutter/flutter",
  dart: "dart-lang/sdk",
  "node.js": "nodejs/node",
  deno: "denoland/deno",
  bun: "oven-sh/bun",
  typescript: "microsoft/TypeScript",
  "vs code": "microsoft/vscode",
  rust: "rust-lang/rust",
  go: "golang/go",
  kubernetes: "kubernetes/kubernetes",
  docker: "moby/moby",
  tensorflow: "tensorflow/tensorflow",
  pytorch: "pytorch/pytorch",
  django: "django/django",
  flask: "pallets/flask",
  fastapi: "fastapi/fastapi",
  prisma: "prisma/prisma",
  tailwind: "tailwindlabs/tailwindcss",
  "tailwind css": "tailwindlabs/tailwindcss",
  vite: "vitejs/vite",
  express: "expressjs/express",
  langchain: "langchain-ai/langchain",
  ollama: "ollama/ollama",
  redis: "redis/redis",
  postgres: "postgres/postgres",
  linux: "torvalds/linux",
  git: "git/git",
  swift: "swiftlang/swift",
  kotlin: "JetBrains/kotlin",
};

/** Repo guesses for well-known projects named in the text (e.g. "the Flutter repo"). */
export function knownRepoGuesses(entities: Entity[]): { owner: string; repo: string }[] {
  const out: { owner: string; repo: string }[] = [];
  for (const e of entities) {
    if (e.type !== "tech") continue;
    const full = KNOWN_REPOS[e.value.toLowerCase()];
    if (!full) continue;
    const [owner, repo] = full.split("/");
    if (!out.some((r) => r.owner === owner && r.repo === repo)) out.push({ owner: owner!, repo: repo! });
  }
  return out;
}

/** Short factual lines for the memory extractor (not instructions). */
export function memoryHints(entities: Entity[]): string[] {
  const lines: string[] = [];
  const by = (t: EntityType) => [...new Set(entities.filter((e) => e.type === t).map((e) => e.value))];
  const people = by("person");
  const orgs = by("org");
  const tech = by("tech");
  const dates = entities.filter((e) => e.type === "date" && e.value).map((e) => (e.value === e.text ? e.text : `${e.text} = ${e.value}`));
  if (people.length) lines.push(`people: ${people.slice(0, 5).join(", ")}`);
  if (orgs.length) lines.push(`organisations: ${orgs.slice(0, 5).join(", ")}`);
  if (tech.length) lines.push(`technologies: ${tech.slice(0, 8).join(", ")}`);
  if (dates.length) lines.push(`dates: ${[...new Set(dates)].slice(0, 4).join("; ")}`);
  const money = by("money");
  if (money.length) lines.push(`amounts: ${money.slice(0, 3).join(", ")}`);
  const emails = by("email");
  if (emails.length) lines.push(`emails: ${emails.slice(0, 2).join(", ")}`);
  const phones = by("phone");
  if (phones.length) lines.push(`phones: ${phones.slice(0, 2).join(", ")}`);
  const repos = by("repo");
  if (repos.length) lines.push(`repositories: ${repos.slice(0, 3).join(", ")}`);
  return lines;
}
