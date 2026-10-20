import type { ConversationSummary } from "@/features/chat/schemas/conversation";

export const HISTORY_COPY = {
  pinned: "PINNED",
  today: "TODAY",
  yesterday: "YESTERDAY",
  previous7: "PREVIOUS 7 DAYS",
  previous30: "PREVIOUS 30 DAYS",
  untitled: "New chat",
  justNow: "now",
  searchHint: "Search chats",
  newChat: "New chat",
  noChats: "No chats yet. Start one and it appears here.",
  noMatches: "No chats match",
  loadFailed: "Couldn't load your chats.",
  rename: "Rename",
  pin: "Pin",
  unpin: "Unpin",
  delete: "Delete",
  moreActions: "More actions",
  chatName: "Chat name",
  deleteKicker: "Delete chat",
  deleteTitle: "Delete this chat?",
  deleteBody: "The conversation and its files are removed for good.",
  closeMenu: "Close menu",
  openMenu: "Open menu",
  settings: "Settings",
} as const;

const MONTHS = [
  "JANUARY",
  "FEBRUARY",
  "MARCH",
  "APRIL",
  "MAY",
  "JUNE",
  "JULY",
  "AUGUST",
  "SEPTEMBER",
  "OCTOBER",
  "NOVEMBER",
  "DECEMBER",
] as const;

export interface HistoryGroup {
  label: string;
  items: ConversationSummary[];
  pinned: boolean;
}

const DAY_MS = 86_400_000;

const dayOf = (d: Date): number => Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());

export function historyBucket(at: Date, now: Date): string {
  const days = Math.round((dayOf(now) - dayOf(at)) / DAY_MS);
  if (days <= 0) return HISTORY_COPY.today;
  if (days === 1) return HISTORY_COPY.yesterday;
  if (days <= 7) return HISTORY_COPY.previous7;
  if (days <= 30) return HISTORY_COPY.previous30;
  const month = MONTHS[at.getMonth()] ?? "";
  return at.getFullYear() === now.getFullYear() ? month : `${month} ${at.getFullYear()}`;
}

export function groupConversations(items: readonly ConversationSummary[], now: Date): HistoryGroup[] {
  const pinned = items.filter((c) => c.pinned);
  const buckets = new Map<string, ConversationSummary[]>();
  for (const c of items) {
    if (c.pinned) continue;
    const label = historyBucket(new Date(c.updatedAt), now);
    buckets.set(label, [...(buckets.get(label) ?? []), c]);
  }
  return [
    ...(pinned.length > 0 ? [{ label: HISTORY_COPY.pinned, items: pinned, pinned: true }] : []),
    ...[...buckets].map(([label, group]) => ({ label, items: group, pinned: false })),
  ];
}
