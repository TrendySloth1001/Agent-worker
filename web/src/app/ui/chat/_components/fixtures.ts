import type { AiModel } from "@/features/chat/api/models";
import type { ChatEvent } from "@/features/chat/schemas/events";
import type { ConversationSummary } from "@/features/chat/schemas/conversation";
import type { StoredMessage } from "@/features/chat/schemas/message";

export type Scenario = "empty" | "conversation" | "streaming" | "waiting";

export const SCENARIOS: readonly Scenario[] = ["empty", "conversation", "streaming", "waiting"];

const DAY = 86_400_000;
const at = (daysAgo: number): string => new Date(Date.now() - daysAgo * DAY).toISOString();

const summary = (id: string, title: string, daysAgo: number, pinned = false): ConversationSummary => ({
  id,
  title,
  messageCount: 4,
  preview: null,
  pinned,
  archived: false,
  origin: null,
  updatedAt: at(daysAgo),
});

export const FIXTURE_CONVERSATIONS: ConversationSummary[] = [
  summary("c0", "Roadmap for the web app", 3, true),
  summary("c1", "How does SSE streaming work?", 0.02),
  summary("c2", "Plan my week in Lisbon", 0.3),
  summary("c3", "Refactor the auth middleware", 1.2),
  summary("c4", "Sourdough starter troubleshooting", 4),
  summary("c5", "Explain Postgres vacuum", 12),
  summary("c6", "Cover letter draft", 45),
];

export const FIXTURE_MODELS: AiModel[] = [
  {
    id: "openai/gpt-oss-120b",
    name: "GPT OSS 120B",
    provider: "groq",
    maker: "OpenAI",
    about: "A strong all-rounder for reasoning, writing and code. Thoughtful answers on harder questions.",
    contextTokens: 128_000,
    speed: "balanced",
  },
];

const MODEL_ID = FIXTURE_MODELS[0]?.id ?? "";

export const REPLY_MARKDOWN = `Server-sent events keep one HTTP response open and push **named events** down it [W1]. The browser reads the body as a stream and splits it on blank lines.

## The wire format

Each event is a few \`field: value\` lines followed by an empty line:

\`\`\`text
event: delta
data: {"text":"Hello"}
\`\`\`

## Parsing it

- Buffer chunks until a newline arrives
- Join repeated \`data:\` lines with \`\\n\`
- Ignore lines that start with a colon [K1]

\`\`\`ts
export async function* readSse(body: ReadableStream<Uint8Array>) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = ""; // carries a partial line between chunks
  for (;;) {
    const { done, value } = await reader.read();
    if (done) return;
    buffer += decoder.decode(value, { stream: true });
    yield* buffer.split("\\n\\n");
  }
}
\`\`\`

| Event | Meaning |
| --- | --- |
| \`delta\` | A piece of the reply |
| \`sources\` | Citations used |
| \`done\` | The turn finished |

> Stopping is just aborting the fetch; the server notices the closed socket.`;

export const SOURCES = [
  { id: "W1", kind: "web" as const, title: "Using server-sent events", url: "https://developer.mozilla.org/docs/Web/API/Server-sent_events/Using_server-sent_events", snippet: "", site: "developer.mozilla.org" },
  { id: "W2", kind: "web" as const, title: "Server-sent events", url: "https://html.spec.whatwg.org/multipage/server-sent-events.html", snippet: "", site: "html.spec.whatwg.org" },
  { id: "K1", kind: "kb" as const, title: "Streaming notes", url: "", snippet: "", site: "Streaming notes" },
];

export const FOLLOW_UPS = ["How do I reconnect after a drop?", "Compare SSE with WebSockets", "Show a React hook for this"];

export const STORED_CONVERSATION: StoredMessage[] = [
  {
    role: "user",
    content: "How does SSE streaming work, and how do I parse it in the browser?",
    meta: {},
    citations: [],
    usedIds: [],
    images: [],
    evidence: [],
    attachments: [],
    isError: false,
  },
  {
    role: "assistant",
    content: REPLY_MARKDOWN,
    model: MODEL_ID,
    meta: { suggestions: FOLLOW_UPS, webAuto: true },
    citations: SOURCES,
    usedIds: ["W1", "K1"],
    images: [],
    evidence: [],
    attachments: [],
    isError: false,
  },
];

const sleep = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    const t = setTimeout(resolve, ms);
    signal.addEventListener("abort", () => {
      clearTimeout(t);
      reject(new DOMException("aborted", "AbortError"));
    });
  });

const CHUNK = 14;

export function fakeStream(hold: boolean) {
  return async function* (_request: unknown, signal: AbortSignal): AsyncGenerator<ChatEvent> {
    yield { type: "start", data: { candidates: [MODEL_ID, "meta-llama/llama-4-scout-17b-16e-instruct"] } };
    await sleep(600, signal);
    yield { type: "status", data: { phase: "searching" } };
    await sleep(900, signal);
    if (hold) {
      await sleep(10 * 60_000, signal);
      return;
    }
    yield { type: "model", data: { model: MODEL_ID, attempt: 1 } };
    yield { type: "status", data: { phase: "generating" } };
    for (let i = 0; i < REPLY_MARKDOWN.length; i += CHUNK) {
      await sleep(18, signal);
      yield { type: "delta", data: { text: REPLY_MARKDOWN.slice(i, i + CHUNK) } };
    }
    yield { type: "sources", data: { citations: SOURCES } };
    yield { type: "suggestions", data: { items: FOLLOW_UPS } };
    yield { type: "done", data: { model: MODEL_ID, used: ["W1", "K1"], latencyMs: 4200 } };
  };
}
