import type { IconName } from "@/components/ui/icons";

export interface AboutItem {
  icon: IconName;
  title: string;
  detail: string;
}

export interface AboutCredit {
  label: string;
  value: string;
  url: string;
}

export const FEATURES: ReadonlyArray<AboutItem> = [
  {
    icon: "models",
    title: "Multi-model chat",
    detail:
      "Automatic model routing across free cloud models: Groq, Ollama Cloud, NVIDIA and OpenRouter.",
  },
  {
    icon: "web",
    title: "Web search",
    detail: "Answers grounded in the web, with sentence-level citations.",
  },
  {
    icon: "knowledge",
    title: "Knowledge base",
    detail: "Save notes and documents; sparky searches them when you ask.",
  },
  {
    icon: "roundTable",
    title: "Round Table",
    detail: "Several models debate a question and agree on one answer.",
  },
  {
    icon: "doc",
    title: "DOC mode",
    detail: "Long-form documents, written section by section.",
  },
  {
    icon: "fork",
    title: "Your chats, your way",
    detail: "Fork, merge, share and export any conversation.",
  },
];

export const PRIVACY: ReadonlyArray<AboutItem> = [
  {
    icon: "server",
    title: "Stored on your sparky server",
    detail: "Chats and files are only visible to your account.",
  },
  {
    icon: "key",
    title: "Encrypted tokens and keys",
    detail: "GitHub tokens and your own API keys are encrypted at rest.",
  },
  {
    icon: "delete",
    title: "Delete anything",
    detail: "Remove any file in Storage, or your whole account in Profile.",
  },
  {
    icon: "chat",
    title: "Model providers",
    detail: "Your messages are sent to third-party model providers to generate answers.",
  },
];

export const CREDITS: ReadonlyArray<AboutCredit> = [
  {
    label: "Illustrations",
    value: "Open Peeps and Open Doodles by Pablo Stanley (CC0)",
    url: "https://www.openpeeps.com/",
  },
  { label: "Icons", value: "Hugeicons", url: "https://hugeicons.com/" },
  {
    label: "Model logos",
    value: "LobeHub Icons (MIT). Logos are trademarks of their owners.",
    url: "https://github.com/lobehub/lobe-icons",
  },
];
