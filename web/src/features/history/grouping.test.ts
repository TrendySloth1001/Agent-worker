import { describe, expect, it } from "vitest";
import type { ConversationSummary } from "@/features/chat/schemas/conversation";
import { groupConversations, historyBucket } from "./grouping";

const now = new Date(2026, 9, 20, 15, 0);

const conv = (id: string, updatedAt: Date, pinned = false): ConversationSummary => ({
  id,
  title: id,
  messageCount: 2,
  preview: null,
  pinned,
  archived: false,
  origin: null,
  updatedAt: updatedAt.toISOString(),
});

describe("historyBucket", () => {
  it("buckets by calendar day", () => {
    expect(historyBucket(new Date(2026, 9, 20, 1), now)).toBe("TODAY");
    expect(historyBucket(new Date(2026, 9, 19, 23), now)).toBe("YESTERDAY");
    expect(historyBucket(new Date(2026, 9, 14), now)).toBe("PREVIOUS 7 DAYS");
    expect(historyBucket(new Date(2026, 9, 1), now)).toBe("PREVIOUS 30 DAYS");
  });

  it("names older months and adds the year for other years", () => {
    expect(historyBucket(new Date(2026, 5, 3), now)).toBe("JUNE");
    expect(historyBucket(new Date(2025, 5, 3), now)).toBe("JUNE 2025");
  });
});

describe("groupConversations", () => {
  it("puts pinned first and keeps server order inside buckets", () => {
    const groups = groupConversations(
      [conv("p", new Date(2026, 0, 1), true), conv("a", new Date(2026, 9, 20)), conv("b", new Date(2026, 9, 20, 9)), conv("c", new Date(2026, 9, 19))],
      now,
    );
    expect(groups.map((g) => g.label)).toEqual(["PINNED", "TODAY", "YESTERDAY"]);
    expect(groups[1]?.items.map((c) => c.id)).toEqual(["a", "b"]);
  });
});
