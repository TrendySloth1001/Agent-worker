import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  QUICK_ASK_MAX,
  QUICK_ASK_STORAGE_KEY,
  QUICK_ASK_URL,
  isQuickAskShortcut,
  stashQuickAsk,
  takeQuickAsk,
} from "./handoff";
import { QuickAsk } from "./quick-ask";

const push = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));

const key = (init: Partial<KeyboardEvent>) =>
  ({
    key: "k",
    metaKey: false,
    ctrlKey: false,
    shiftKey: false,
    altKey: false,
    ...init,
  }) as KeyboardEvent;

beforeEach(() => {
  push.mockClear();
  sessionStorage.clear();
});

describe("handoff", () => {
  it("stores the prompt in sessionStorage and hands it over exactly once", () => {
    expect(stashQuickAsk("  how do I rebase?  ")).toBe(true);
    expect(sessionStorage.getItem(QUICK_ASK_STORAGE_KEY)).toBe("how do I rebase?");
    expect(takeQuickAsk()).toBe("how do I rebase?");
    expect(takeQuickAsk()).toBeNull();
  });

  it("ignores empty prompts and caps long ones", () => {
    expect(stashQuickAsk("   ")).toBe(false);
    expect(takeQuickAsk()).toBeNull();
    stashQuickAsk("x".repeat(QUICK_ASK_MAX + 50));
    expect(takeQuickAsk()?.length).toBe(QUICK_ASK_MAX);
  });

  it("never puts the prompt in the url", () => {
    expect(QUICK_ASK_URL).toBe("/chat?quick=1");
  });

  it("recognises Cmd/Ctrl+Shift+K only", () => {
    expect(isQuickAskShortcut(key({ metaKey: true, shiftKey: true }))).toBe(true);
    expect(isQuickAskShortcut(key({ ctrlKey: true, shiftKey: true, key: "K" }))).toBe(true);
    expect(isQuickAskShortcut(key({ ctrlKey: true }))).toBe(false);
    expect(isQuickAskShortcut(key({ shiftKey: true }))).toBe(false);
    expect(isQuickAskShortcut(key({ ctrlKey: true, shiftKey: true, altKey: true }))).toBe(false);
  });
});

describe("QuickAsk", () => {
  it("opens on the shortcut, stashes the prompt and navigates to the chat", async () => {
    render(<QuickAsk />);
    expect(screen.queryByRole("dialog")).toBeNull();

    fireEvent.keyDown(window, { key: "K", ctrlKey: true, shiftKey: true });
    const box = await screen.findByLabelText("Your question");

    await userEvent.type(box, "explain CRDTs{Enter}");

    expect(sessionStorage.getItem(QUICK_ASK_STORAGE_KEY)).toBe("explain CRDTs");
    expect(push).toHaveBeenCalledWith("/chat?quick=1");
  });

  it("does nothing for an empty question", async () => {
    render(<QuickAsk />);
    fireEvent.keyDown(window, { key: "k", metaKey: true, shiftKey: true });
    const box = await screen.findByLabelText("Your question");
    await userEvent.type(box, "{Enter}");
    expect(push).not.toHaveBeenCalled();
    expect(sessionStorage.getItem(QUICK_ASK_STORAGE_KEY)).toBeNull();
  });
});
