/**
 * Normalizes citation tags while the reply streams:
 * - gpt-oss writes 【W1】; the app expects [W1].
 * - Models sometimes combine tags as [K1, W2]; that becomes [K1][W2].
 * An unfinished "[..." at the end of a chunk is held back (briefly) until its
 * "]" arrives, so a tag split across chunks is still rewritten.
 * Reasoning blocks (<think>...</think>, as Qwen/DeepSeek-style models stream
 * them inline) are removed, also when a tag is split across chunks.
 * With [valid] ids, tags that cite nothing of this turn are dropped together
 * with the space before them, so "India [W9]." reads "India." (not "India .").
 * Trailing spaces of a chunk are held until the next one for the same reason.
 */
export class TagStream {
  /** [valid]: the turn's citation ids (may grow while streaming); omitted, every tag is kept. */
  constructor(private readonly valid?: ReadonlySet<string>) {}

  private pending = "";
  private thinkTail = "";
  private inThink = false;
  private emitted = false;
  private afterTag = false;

  push(chunk: string): string {
    const visible = this.stripThink(chunk);
    let s = this.pending + visible.replace(/【/g, "[").replace(/】/g, "]");
    this.pending = "";
    const open = s.lastIndexOf("[");
    if (open >= 0 && s.indexOf("]", open) < 0 && s.length - open <= 24) {
      // The spaces before the open tag go with it (dropped with it if it cites nothing).
      let cut = open;
      while (cut > 0 && (s[cut - 1] === " " || s[cut - 1] === "\t")) cut--;
      this.pending = s.slice(cut);
      s = s.slice(0, cut);
    } else {
      const ws = /[ \t]+$/.exec(s);
      if (ws) {
        this.pending = ws[0];
        s = s.slice(0, ws.index);
      }
    }
    // A kept tag already went out: the space before the punctuation that follows it in a later chunk goes too
    // ("Spotify [W2]" then " ." reads "Spotify [W2].").
    if (this.afterTag) s = s.replace(/^[ \t]+(?=[.,;:!?)])/, "");
    const out = normalize(s, this.valid);
    if (out) this.afterTag = /\[[KWDGC]\d+\]$/.test(out);
    if (out.trim()) this.emitted = true;
    return out;
  }

  /** Whatever is still held back, at the end of the reply. */
  flush(): string {
    // A dangling partial "<thi" that never became a tag is ordinary text; an open <think> is dropped.
    const tail = this.inThink ? "" : this.thinkTail;
    let held = this.pending + tail;
    if (this.afterTag) held = held.replace(/^[ \t]+(?=[.,;:!?)])/, "");
    const rest = normalize(held, this.valid);
    this.pending = "";
    this.thinkTail = "";
    this.inThink = false;
    return rest;
  }

  reset(): void {
    this.pending = "";
    this.thinkTail = "";
    this.inThink = false;
    this.emitted = false;
    this.afterTag = false;
  }

  private stripThink(chunk: string): string {
    let s = this.thinkTail + chunk;
    this.thinkTail = "";
    let out = "";
    for (;;) {
      if (this.inThink) {
        const end = s.search(/<\/think>/i);
        if (end < 0) {
          // Keep a possible partial closing tag for the next chunk.
          this.thinkTail = partialTail(s, "</think>");
          return out;
        }
        s = s.slice(end + "</think>".length).replace(/^\s+/, "");
        this.inThink = false;
        continue;
      }
      const open = s.search(/<think>/i);
      const close = s.search(/<\/think>/i);
      // A lone closing tag before any visible text: the opening tag was in the prompt template.
      if (close >= 0 && (open < 0 || close < open) && !this.emitted && !out.trim()) {
        s = s.slice(close + "</think>".length).replace(/^\s+/, "");
        continue;
      }
      if (open < 0) {
        const keep = partialTail(s, "<think>");
        this.thinkTail = keep;
        return out + s.slice(0, s.length - keep.length);
      }
      out += s.slice(0, open);
      s = s.slice(open + "<think>".length);
      this.inThink = true;
    }
  }
}

/** The longest suffix of [s] that is a proper prefix of [tag] (case-insensitive). */
function partialTail(s: string, tag: string): string {
  const max = Math.min(s.length, tag.length - 1);
  for (let n = max; n > 0; n--) if (tag.startsWith(s.slice(s.length - n).toLowerCase())) return s.slice(s.length - n);
  return "";
}

function normalize(s: string, valid?: ReadonlySet<string>): string {
  const split = s.replace(/\[([KWDGC]\d+(?:\s*[,;]\s*[KWDGC]\d+)+)\]/g, (_m, list: string) =>
    list
      .split(/\s*[,;]\s*/)
      .map((t) => `[${t}]`)
      .join(""),
  );
  return tidyCitations(split, valid);
}

const DROPPED = "\u0000";

/**
 * Drops tags whose id is not in [valid] (with the spaces before them) and
 * removes spaces between a tag or a dropped tag and the punctuation after it:
 * "Music [W3] ." -> "Music [W3].", "India [W9]." -> "India.".
 */
export function tidyCitations(s: string, valid?: ReadonlySet<string>): string {
  if (!s.includes("[")) return s;
  return s
    .replace(/[ \t]*\[([KWDGC]\d+)\](?!\()/g, (m, id: string) => (valid && !valid.has(id) ? DROPPED : m))
    .replace(/\u0000+[ \t]*(?=[.,;:!?)])/g, "")
    .replace(/\u0000+/g, "")
    .replace(/(\[[KWDGC]\d+\])[ \t]+(?=[.,;:!?)])/g, "$1");
}
