import type { Connector } from "../types.js";

/** Saved chat replies. Content lives in sources.options; one document per note. */
export const note: Connector = {
  async resolve(input) {
    return { uri: input };
  },
  async run(source, ctx) {
    const content = String(source.options.content ?? "");
    const question = String(source.options.question ?? "").trim();
    ctx.setTotal(1);
    const markdown = question ? `> Question: ${question}\n\n${content}` : content;
    await ctx.emit({ url: source.uri, title: (source.options.title as string) ?? null, markdown, meta: { question: question || undefined, conversationId: source.options.conversationId } });
  },
};
