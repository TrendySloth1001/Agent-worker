/**
 * Normalizes citation tags while the reply streams:
 * - gpt-oss writes 【W1】; the app expects [W1].
 * - Models sometimes combine tags as [K1, W2]; that becomes [K1][W2].
 * An unfinished "[..." at the end of a chunk is held back (briefly) until its
 * "]" arrives, so a tag split across chunks is still rewritten.
 */
export class TagStream {
  private pending = "";

  push(chunk: string): string {
    let s = this.pending + chunk.replace(/【/g, "[").replace(/】/g, "]");
    this.pending = "";
    const open = s.lastIndexOf("[");
    if (open >= 0 && s.indexOf("]", open) < 0 && s.length - open <= 24) {
      this.pending = s.slice(open);
      s = s.slice(0, open);
    }
    return normalize(s);
  }

  /** Whatever is still held back, at the end of the reply. */
  flush(): string {
    const rest = normalize(this.pending);
    this.pending = "";
    return rest;
  }

  reset(): void {
    this.pending = "";
  }
}

function normalize(s: string): string {
  return s.replace(/\[([KWD]\d+(?:\s*[,;]\s*[KWD]\d+)+)\]/g, (_m, list: string) =>
    list
      .split(/\s*[,;]\s*/)
      .map((t) => `[${t}]`)
      .join(""),
  );
}
