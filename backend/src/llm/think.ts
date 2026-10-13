/**
 * Streaming filter that drops inline reasoning (<think>...</think>), even when
 * a tag is split across chunks. What remains is the visible answer, so the
 * router can tell "the model wrote something" from "it only thought".
 */
const OPEN = "<think>";
const CLOSE = "</think>";

/** Length of the longest suffix of [s] that is a prefix of [tag] (a tag cut by a chunk boundary). */
function partial(s: string, tag: string): number {
  const low = s.toLowerCase();
  for (let n = Math.min(tag.length - 1, low.length); n > 0; n--) if (tag.startsWith(low.slice(-n))) return n;
  return 0;
}

export class ThinkFilter {
  private inside = false;
  private held = "";

  push(chunk: string): string {
    let s = this.held + chunk;
    this.held = "";
    let out = "";
    while (s) {
      const low = s.toLowerCase();
      if (this.inside) {
        const end = low.indexOf(CLOSE);
        if (end < 0) {
          const keep = partial(s, CLOSE);
          this.held = keep ? s.slice(-keep) : "";
          return out;
        }
        this.inside = false;
        s = s.slice(end + CLOSE.length);
        continue;
      }
      const start = low.indexOf(OPEN);
      if (start < 0) {
        const keep = partial(s, OPEN);
        this.held = keep ? s.slice(-keep) : "";
        return out + (keep ? s.slice(0, -keep) : s);
      }
      out += s.slice(0, start);
      this.inside = true;
      s = s.slice(start + OPEN.length);
    }
    return out;
  }

  /** End of stream: a dangling partial "<thi" was ordinary text; an unclosed block is dropped. */
  flush(): string {
    const rest = this.inside ? "" : this.held;
    this.held = "";
    return rest;
  }
}

/** The visible part of a complete reply. */
export const stripThink = (s: string): string => s.replace(/<think>[\s\S]*?(<\/think>|$)/gi, "");
