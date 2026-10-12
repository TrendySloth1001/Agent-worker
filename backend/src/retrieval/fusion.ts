/** Pure ranking helpers for retrieval: Reciprocal Rank Fusion, MMR, overlap-aware joining. */

export type RankedList<K> = { ids: K[]; weight?: number };
export type Fused<K> = { id: K; score: number; /** index of the lists this id appeared in */ lists: number[] };

/**
 * Reciprocal Rank Fusion: score(id) = sum over lists of weight / (k + rank), rank starting at 1.
 * Robust to score scales that differ between the vector and keyword searches.
 * Ties keep first-seen order.
 */
export function rrfFuse<K>(lists: Array<RankedList<K>>, k = 60): Fused<K>[] {
  const acc = new Map<K, Fused<K>>();
  lists.forEach((list, li) => {
    const w = list.weight ?? 1;
    const seen = new Set<K>();
    list.ids.forEach((id, i) => {
      if (seen.has(id)) return; // a duplicate within one list counts once, at its best rank
      seen.add(id);
      const e = acc.get(id) ?? { id, score: 0, lists: [] };
      e.score += w / (k + i + 1);
      e.lists.push(li);
      acc.set(id, e);
    });
  });
  return [...acc.values()].sort((a, b) => b.score - a.score);
}

export function cosine(a: ArrayLike<number>, b: ArrayLike<number>): number {
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na && nb ? dot / Math.sqrt(na * nb) : 0;
}

export type MmrItem = { id: string | number; relevance: number; vec: ArrayLike<number> | null };

/**
 * Maximal Marginal Relevance. Greedily picks the item maximising
 * lambda * relevance - (1 - lambda) * maxSimilarityToSelected.
 * Items nearer than [dupSim] to an already selected one are dropped outright.
 * Items without a vector are never penalised. Relevance is normalised to 0..1.
 */
export function mmr(items: MmrItem[], k: number, lambda = 0.7, dupSim = 0.93): Array<string | number> {
  if (items.length === 0 || k <= 0) return [];
  const top = Math.max(...items.map((i) => i.relevance)) || 1;
  const pool = items.map((i) => ({ ...i, rel: i.relevance / top }));
  const picked: typeof pool = [];
  while (picked.length < k && pool.length) {
    let best = -1;
    let bestScore = -Infinity;
    for (let i = 0; i < pool.length; i++) {
      const c = pool[i];
      let maxSim = 0;
      if (c.vec) for (const p of picked) if (p.vec) maxSim = Math.max(maxSim, cosine(c.vec, p.vec));
      if (maxSim >= dupSim) {
        pool.splice(i--, 1);
        continue;
      }
      const s = lambda * c.rel - (1 - lambda) * maxSim;
      if (s > bestScore) (bestScore = s), (best = i);
    }
    if (best < 0) break;
    picked.push(pool.splice(best, 1)[0]);
  }
  return picked.map((p) => p.id);
}

/** Parses pgvector's text form "[0.1,0.2,...]". */
export function parseVector(s: string): Float32Array {
  const parts = s.slice(1, -1).split(",");
  const v = new Float32Array(parts.length);
  for (let i = 0; i < parts.length; i++) v[i] = Number(parts[i]);
  return v;
}

/**
 * Appends [next] to [prev], dropping the text the chunker repeated as overlap
 * (a suffix of prev that is also a prefix of next, at least 20 chars).
 */
export function joinOverlap(prev: string, next: string, maxOverlap = 400): string {
  const max = Math.min(maxOverlap, prev.length, next.length);
  for (let n = max; n >= 20; n--) {
    if (prev.endsWith(next.slice(0, n))) return `${prev}${next.slice(n).replace(/^\s+/, "\n\n")}`;
  }
  return `${prev}\n\n${next}`;
}
