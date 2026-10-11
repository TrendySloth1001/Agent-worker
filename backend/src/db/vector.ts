/**
 * pgvector values travel as text literals ("[0.1,0.2,...]") bound as query
 * parameters and cast in SQL: $queryRaw`... ${toVector(v)}::vector ...`.
 * Prisma cannot read or write `Unsupported("vector(...)")` columns otherwise.
 */
export const toVector = (v: number[]): string => `[${v.join(",")}]`;
