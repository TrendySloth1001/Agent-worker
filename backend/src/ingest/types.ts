export type DocInput = { url: string; title: string | null; markdown: string; meta?: Record<string, unknown> };

export type IngestCtx = {
  limit: number;
  /** Declare how many documents are expected (for progress). */
  setTotal(n: number): void;
  setTitle(title: string): void;
  /** Hand a finished document to the pipeline (chunk, embed, store). Resolves when buffered or stored. */
  emit(doc: DocInput): Promise<void>;
  /** Count a document that was attempted but skipped/failed, so progress still advances. */
  skip(reason?: string): void;
};

export type SourceRow = { id: string; type: string; uri: string; options: Record<string, any>; userId: string | null };

export type Connector = {
  /** Validate + canonicalize user input. Throws AppError(400). */
  resolve(input: string, limit: number): Promise<{ uri: string; title?: string; options?: Record<string, unknown> }>;
  run(source: SourceRow, ctx: IngestCtx): Promise<void>;
};
