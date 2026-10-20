import { describe, expect, it } from "vitest";
import type { ChatEvent } from "../schemas/events";
import {
  applyEvent,
  chatReducer,
  initialChatState,
  pendingAssistant,
  toStored,
} from "./stream-reducer";
import { emptyMessage } from "./types";

const delta = (text: string): ChatEvent => ({ type: "delta", data: { text } });

describe("applyEvent", () => {
  it("accumulates deltas and resets on a reset event", () => {
    let m = pendingAssistant("a");
    m = applyEvent(m, delta("Hel"));
    m = applyEvent(m, delta("lo"));
    expect(m.content).toBe("Hello");
    m = applyEvent(m, { type: "reset", data: { reason: "fallback" } });
    expect(m.content).toBe("");
  });

  it("tracks the wait step from start, status and model events", () => {
    let m = pendingAssistant("a");
    m = applyEvent(m, { type: "start", data: { candidates: ["x", "y"] } });
    expect(m.waitLast).toBe("start");
    m = applyEvent(m, { type: "status", data: { phase: "searching" } });
    expect(m).toMatchObject({ waitLast: "status", phase: "searching" });
    m = applyEvent(m, { type: "model", data: { model: "openai/gpt-oss-120b", attempt: 2 } });
    expect(m).toMatchObject({ waitLast: "model", modelId: "openai/gpt-oss-120b", attempt: 2 });
  });

  it("finishes on done with the used sources and the final model", () => {
    const m = applyEvent(applyEvent(pendingAssistant("a"), delta("x")), {
      type: "done",
      data: { model: "m", used: ["W1"], latencyMs: 12 },
    });
    expect(m).toMatchObject({ streaming: false, modelId: "m", usedIds: ["W1"], latencyMs: 12 });
  });

  it("marks an error with no text as an error reply and keeps partial text otherwise", () => {
    const err: ChatEvent = {
      type: "error",
      data: { error: { code: "x", message: "Nope", retryable: true } },
    };
    expect(applyEvent(pendingAssistant("a"), err)).toMatchObject({
      isError: true,
      error: "Nope",
      streaming: false,
    });
    const partial = applyEvent(applyEvent(pendingAssistant("a"), delta("abc")), err);
    expect(partial).toMatchObject({ isError: false, content: "abc", error: "Nope" });
  });

  it("trims suggestions and drops blanks", () => {
    const m = applyEvent(pendingAssistant("a"), {
      type: "suggestions",
      data: { items: [" one ", " "] },
    });
    expect(m.suggestions).toEqual(["one"]);
  });
});

describe("chatReducer", () => {
  const user = { ...emptyMessage("u", "user"), content: "hi" };

  it("appends a turn and routes events to the right message", () => {
    let s = chatReducer(initialChatState, { type: "send", user, assistant: pendingAssistant("a") });
    s = chatReducer(s, { type: "event", id: "a", event: delta("yo") });
    expect(s.messages.map((m) => m.content)).toEqual(["hi", "yo"]);
  });

  it("stop keeps partial text and turns an empty reply into an interrupted one", () => {
    const base = chatReducer(initialChatState, {
      type: "send",
      user,
      assistant: pendingAssistant("a"),
    });
    const empty = chatReducer(base, { type: "stop", id: "a" });
    expect(empty.messages[1]).toMatchObject({ streaming: false, isError: true, interrupted: true });
    const partial = chatReducer(chatReducer(base, { type: "event", id: "a", event: delta("x") }), {
      type: "stop",
      id: "a",
    });
    expect(partial.messages[1]).toMatchObject({
      streaming: false,
      isError: false,
      interrupted: false,
    });
  });

  it("truncates for regenerate", () => {
    const s = chatReducer(initialChatState, {
      type: "send",
      user,
      assistant: pendingAssistant("a"),
    });
    expect(chatReducer(s, { type: "truncate", keep: 1 }).messages).toHaveLength(1);
  });
});

describe("toStored", () => {
  it("keeps follow-ups and the searched flag in meta", () => {
    const m = { ...pendingAssistant("a"), content: "x", suggestions: ["more"], webSearched: true };
    expect(toStored(m).meta).toEqual({ suggestions: ["more"], webAuto: true });
  });
});
