export const WAIT_PHASES: Record<string, string> = {
  processing_files: "Reading your files…",
  analyzing_image: "Looking at the image…",
  retrieving: "Checking your notes…",
  searching: "Searching the web…",
  round_table: "Gathering the round table…",
  queued: "In line, one moment…",
};

export const WAIT_COPY = {
  picking: "Picking the best model…",
  switching: "Switching models…",
  goingWith: (name: string) => `Going with ${name}`,
  switchingTo: (name: string) => `Switching to ${name}…`,
} as const;

export const MODEL_INFO_COPY = {
  title: "About this model",
  madeBy: "Made by",
  goodAt: "Good at",
  memory: "Memory",
  feel: "Feel",
  modelId: "Model id",
  noInfo: "No details about this model yet.",
  openHint: "About this model",
  speeds: {
    fast: "Quick replies",
    balanced: "Balanced speed and depth",
    deep: "Slower, more thorough",
  },
  memoryOf: (tokens: number): string => {
    const pages = Math.round((tokens * 0.75) / 300);
    const text = pages >= 1000 ? `${(pages / 1000).toFixed(pages % 1000 === 0 ? 0 : 1)}k` : `${pages}`;
    return `Remembers about ${text} pages of chat`;
  },
} as const;

export const EMPTY_PROMPTS = ["Explain a concept", "Review my code", "Plan my day"] as const;

export const CHAT_COPY = {
  inputHint: "Ask anything",
  send: "Send",
  stop: "Stop",
  attach: "Attach",
  web: "Web",
  kb: "KB",
  table: "Table",
  copy: "Copy",
  copied: "Copied",
  regenerate: "Regenerate",
  retry: "Retry",
  scrollDown: "Scroll to latest",
  interrupted: "The reply was interrupted.",
  stopped: "Stopped",
  saveFailed: "Couldn't save this chat. Your reply is still here.",
  loadFailed: "Couldn't open this chat.",
  webModes: { auto: "Web: auto", on: "Web: always", off: "Web: off" },
  kbOn: "Knowledge base on",
  kbOff: "Knowledge base off",
  tableOn: "Round table on",
  tableOff: "Round table off",
} as const;
