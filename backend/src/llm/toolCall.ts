/**
 * Some models (vision/omni ones especially) were trained with tools and, when
 * asked to "search the web", answer with a tool call instead of prose:
 *   {"type": "websearch", "query": "..."}
 *   {"name": "search", "arguments": {"query": "..."}}
 *   <tool_call>{"name": "web_search", ...}</tool_call>
 *   search("...")
 * The chat has no tool calling, so such output must never reach the user.
 * [ToolCallGuard] holds the start of a reply until it is clearly prose; a
 * leading tool call is swallowed and reported so the route can run the search
 * it asked for and ask again.
 */

export type ToolCall = { name: string; query: string | null; raw: string };

/** How much of a reply may be held back while deciding whether it is a tool call. */
const MAX_HOLD = 1_500;

const TOOL_NAME_RE = /^(web[_ ]?search|websearch|search(_web|_engine|_query)?|google(_search)?|bing(_search)?|browse(r)?|browser\.search|lookup|look_up|find|fetch|open_url|retrieve|tool|function)$/i;
const CALL_RE = /^\s*(?:functions\.)?(web[_ ]?search|websearch|search(?:_web|_query)?|google(?:_search)?|bing(?:_search)?|browse|browser\.search|lookup|retrieve)\s*\(\s*(?:(?:query|q)\s*=\s*)?(["'`])([\s\S]*?)\2\s*\)\s*;?\s*$/i;

function queryFrom(v: unknown): string | null {
  if (typeof v === "string") {
    const s = v.trim();
    if (!s) return null;
    // "arguments" is often a JSON string.
    if (s.startsWith("{")) {
      try {
        return queryFrom(JSON.parse(s));
      } catch {
        return null;
      }
    }
    return s.slice(0, 200);
  }
  if (Array.isArray(v)) return v.map(queryFrom).find((q) => q) ?? null;
  if (v && typeof v === "object") {
    const o = v as Record<string, unknown>;
    for (const k of ["query", "q", "search_query", "searchQuery", "queries", "keywords", "search", "text", "input", "url"]) {
      const q = queryFrom(o[k]);
      if (q) return q;
    }
    for (const k of ["arguments", "args", "parameters", "params", "input", "function", "tool_input"]) {
      if (o[k] && typeof o[k] === "object") {
        const q = queryFrom(o[k]);
        if (q) return q;
      } else if (k === "arguments" && typeof o[k] === "string") {
        const q = queryFrom(o[k]);
        if (q) return q;
      }
    }
  }
  return null;
}

/** The tool call an object describes, or null when it is ordinary data. */
function fromObject(o: unknown, raw: string): ToolCall | null {
  if (Array.isArray(o)) return o.length ? fromObject(o[0], raw) : null;
  if (!o || typeof o !== "object") return null;
  const r = o as Record<string, unknown>;
  const fn = r.function && typeof r.function === "object" ? (r.function as Record<string, unknown>) : null;
  const name = [r.type, r.tool, r.name, r.tool_name, r.action, r.recipient_name, fn?.name].find((v): v is string => typeof v === "string" && TOOL_NAME_RE.test(v.replace(/^functions\./, "")));
  const callShape = "arguments" in r || "parameters" in r || "tool_input" in r || (r.type === "function" && !!fn) || "tool_calls" in r;
  if (Array.isArray(r.tool_calls)) return fromObject(r.tool_calls[0], raw);
  if (!name && !callShape) return null;
  // `{"type": "bar", "x": [...]}` (a chart) has neither a tool name nor a call shape, so it never gets here.
  return { name: (name ?? (typeof r.name === "string" ? r.name : "tool")).replace(/^functions\./, ""), query: queryFrom(fn?.arguments ?? r.arguments ?? r.parameters ?? r.args ?? r.tool_input ?? r) ?? null, raw };
}

function parseJsonLoose(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    // Single quotes or trailing commas from sloppy models.
    try {
      return JSON.parse(s.replace(/,\s*([}\]])/g, "$1").replace(/'/g, '"'));
    } catch {
      return undefined;
    }
  }
}

/**
 * Whether [text] (a whole reply, or its start) is a tool call. Recognises a bare
 * JSON object, a ```json / ```tool_call fence around one, <tool_call>/<function_call>
 * tags and `search("...")`-style calls.
 */
export function detectToolCall(text: string): ToolCall | null {
  const t = text.trim();
  if (!t) return null;
  const raw = t;
  // <tool_call>...</tool_call>, <function_call>...</function_call>, <|tool_call|>...
  const tag = t.match(/^<\|?(tool_call|tool_code|function_call|functioncall|tool_use|function=[\w.]+)\|?>([\s\S]*?)(<\/?\|?(tool_call|tool_code|function_call|functioncall|tool_use|function)\|?>|$)/i);
  if (tag) {
    const inner = tag[2].trim();
    const fnName = tag[1].toLowerCase().startsWith("function=") ? tag[1].slice("function=".length) : null;
    const obj = parseJsonLoose(inner);
    const fromObj = obj !== undefined ? fromObject(obj, raw) : null;
    if (fromObj) return fromObj;
    const call = inner.match(CALL_RE);
    if (call) return { name: call[1], query: call[3].trim().slice(0, 200) || null, raw };
    return { name: fnName ?? "tool", query: obj !== undefined ? queryFrom(obj) : inner.replace(/<[^>]+>/g, "").trim().slice(0, 200) || null, raw };
  }
  // ```json {...} ```, ```tool_call ...```, ```python search("...")```
  const fence = t.match(/^```([\w-]*)[^\n]*\n([\s\S]*?)(\n```|$)/);
  if (fence) {
    const lang = fence[1].toLowerCase();
    if (lang && !/^(json|json5|tool_call|tool_code|tool|function_call|python|py|js|javascript|text|plaintext)$/.test(lang)) return null;
    const inner = fence[2].trim();
    if (!inner) return null;
    const viaTag = inner.startsWith("<") ? detectToolCall(inner) : null;
    if (viaTag) return { ...viaTag, raw };
    const call = inner.match(CALL_RE);
    if (call) return { name: call[1], query: call[3].trim().slice(0, 200) || null, raw };
    const obj = parseJsonLoose(inner);
    return obj !== undefined ? fromObject(obj, raw) : null;
  }
  if (t.startsWith("{") || t.startsWith("[")) {
    const end = jsonEnd(t);
    const obj = parseJsonLoose(end > 0 ? t.slice(0, end) : t);
    return obj !== undefined ? fromObject(obj, raw) : null;
  }
  const call = t.split("\n")[0].match(CALL_RE);
  if (call) return { name: call[1], query: call[3].trim().slice(0, 200) || null, raw };
  return null;
}

/** Index just past the first balanced JSON value at the start of [s], or -1 while it is still open. */
export function jsonEnd(s: string): number {
  let depth = 0;
  let inStr: string | null = null;
  let esc = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (esc) esc = false;
      else if (c === "\\") esc = true;
      else if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"') inStr = c;
    else if (c === "{" || c === "[") depth++;
    else if (c === "}" || c === "]") {
      depth--;
      if (depth === 0) return i + 1;
    }
  }
  return -1;
}

type Verdict = { kind: "prose" } | { kind: "hold" } | { kind: "call"; end: number };

const OPENERS = ["{", "[", "```", "<tool_call", "<|tool_call", "<tool_code", "<function", "<|function", "<functioncall", "<tool_use"];
const CALL_PREFIX_RE = /^(?:functions\.)?(web[_ ]?search|websearch|search(?:_web|_query)?|google(?:_search)?|bing(?:_search)?|browse|browser\.search|lookup|retrieve)\s*\(/i;
const CALL_WORDS = ["functions.", "web_search", "websearch", "web search", "search", "google", "bing", "browse", "browser.search", "lookup", "retrieve"];

/** Whether [s] is, or may still grow into, a `search("...")`-style call. */
function couldBeCall(s: string): boolean {
  const low = s.toLowerCase();
  return CALL_PREFIX_RE.test(s) || CALL_WORDS.some((w) => w.startsWith(low) || (low.startsWith(w) && /^[\w. ]*$/.test(low) && low.length < w.length + 3));
}

/** Decides, from the start of a reply, whether it is prose, a tool call, or not yet known. */
function classify(head: string): Verdict {
  const t = head.trimStart();
  const lead = head.length - t.length;
  if (!t) return { kind: "hold" };
  const opener = OPENERS.find((o) => t.toLowerCase().startsWith(o) || o.startsWith(t.toLowerCase()));
  if (opener && !t.toLowerCase().startsWith(opener)) return { kind: "hold" };
  if (t.startsWith("{") || t.startsWith("[")) {
    const end = jsonEnd(t);
    if (end < 0) return t.length > MAX_HOLD ? { kind: "prose" } : { kind: "hold" };
    return detectToolCall(t.slice(0, end)) ? { kind: "call", end: lead + end } : { kind: "prose" };
  }
  if (t.startsWith("```")) {
    const nl = t.indexOf("\n");
    if (nl < 0) return t.length > 40 ? { kind: "prose" } : { kind: "hold" };
    const lang = t.slice(3, nl).trim().toLowerCase();
    if (lang && !/^(json|json5|tool_call|tool_code|tool|function_call|python|py|js|javascript|text|plaintext)$/.test(lang)) return { kind: "prose" };
    const close = t.indexOf("\n```", nl);
    if (close < 0) {
      // A fence of real code is long; a tool call is short. Decide early when the body is clearly not a call.
      const body = t.slice(nl + 1).trimStart();
      if (body && !/^[{[<]/.test(body) && !couldBeCall(body)) return { kind: "prose" };
      return t.length > MAX_HOLD ? { kind: "prose" } : { kind: "hold" };
    }
    const end = close + 4;
    return detectToolCall(t.slice(0, end)) ? { kind: "call", end: lead + end } : { kind: "prose" };
  }
  if (t.startsWith("<")) {
    const m = t.match(/<\/\|?(tool_call|tool_code|function_call|functioncall|tool_use|function)\|?>/i);
    if (!m) return t.length > MAX_HOLD ? { kind: "prose" } : { kind: "hold" };
    const end = m.index! + m[0].length;
    return detectToolCall(t.slice(0, end)) ? { kind: "call", end: lead + end } : { kind: "prose" };
  }
  // search("...") style: hold while the start could still be one.
  if (CALL_PREFIX_RE.test(t)) {
    const nl = t.indexOf("\n");
    const line = nl < 0 ? t : t.slice(0, nl);
    if (nl < 0 && !/\)\s*;?\s*$/.test(line)) return t.length > 300 ? { kind: "prose" } : { kind: "hold" };
    return CALL_RE.test(line) ? { kind: "call", end: lead + line.length } : { kind: "prose" };
  }
  return couldBeCall(t) ? { kind: "hold" } : { kind: "prose" };
}

/**
 * Streaming filter: push() returns the text that may be shown now. A leading
 * tool call is swallowed (call() reports it); everything after it streams on.
 */
export class ToolCallGuard {
  private buf = "";
  private decided = false;
  private found: ToolCall | null = null;
  private afterCall = false;

  push(chunk: string): string {
    if (this.decided) return this.afterCall ? this.trimAfterCall(chunk) : chunk;
    this.buf += chunk;
    const v = classify(this.buf);
    if (v.kind === "hold") return "";
    return this.decide(v);
  }

  /** End of the stream: whatever is still held is decided now. */
  flush(): string {
    if (this.decided) return "";
    const call = detectToolCall(this.buf);
    if (call) {
      this.found = call;
      this.decided = true;
      this.afterCall = true;
      this.buf = "";
      return "";
    }
    this.decided = true;
    const out = this.buf;
    this.buf = "";
    return out;
  }

  /** The tool call the reply started with, if any. */
  call(): ToolCall | null {
    return this.found;
  }

  reset(): void {
    this.buf = "";
    this.decided = false;
    this.found = null;
    this.afterCall = false;
  }

  private decide(v: Verdict): string {
    this.decided = true;
    const all = this.buf;
    this.buf = "";
    if (v.kind === "prose") return all;
    if (v.kind !== "call") return "";
    this.found = detectToolCall(all.slice(0, v.end));
    this.afterCall = true;
    return this.trimAfterCall(all.slice(v.end));
  }

  /** Text after a swallowed call: leading whitespace is dropped so the reply starts cleanly. */
  private trimAfterCall(s: string): string {
    const t = s.replace(/^\s+/, "");
    if (t) this.afterCall = false;
    return t;
  }
}
