import { userCrypto } from "../../crypto/userData.js";
import type { Connector } from "../types.js";

/** Saved chat replies. Content lives in sources.options; one document per note. */
export const note: Connector = {
  async resolve(input) {
    return { uri: input };
  },
  async run(source, ctx) {
    const c = await userCrypto(source.userId);
    const content = c.open("sources", "options.content", String(source.options.content ?? ""));
    const question = c.open("sources", "options.question", String(source.options.question ?? "")).trim();
    const noteTitle = source.options.title ? c.open("sources", "options.title", String(source.options.title)) : null;
    ctx.setTotal(1);
    const markdown = question ? `> Question: ${question}\n\n${content}` : content;
    await ctx.emit({ url: source.uri, title: noteTitle, markdown, meta: { conversationId: source.options.conversationId } });
  },
};
