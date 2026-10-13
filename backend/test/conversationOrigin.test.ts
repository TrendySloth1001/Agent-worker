import { test } from "node:test";
import assert from "node:assert/strict";
import { putSchema } from "../src/routes/conversations.js";

const messages = [
  { role: "user", content: "Open on youtube music" },
  { role: "assistant", content: "Ready to play it." },
];

test("PUT /conversations/:id: an assistant-overlay chat is marked by origin", () => {
  assert.equal(putSchema.parse({ messages, origin: "assistant" }).origin, "assistant");
  assert.equal(putSchema.parse({ messages }).origin, undefined);
  // Only known origins (fork / merge are set by the server itself); anything else is dropped, not a 400.
  assert.equal(putSchema.parse({ messages, origin: "fork" }).origin, undefined);
});
