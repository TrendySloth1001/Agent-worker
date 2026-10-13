import type { ProviderId } from "../models.js";

/**
 * The providers a user can bring their own key for (the same ids the router
 * routes on). `keyUrl` is where the user gets a key; the app shows it from
 * GET /me/keys so no link is hard-coded in the client.
 */
export type KeyProvider = {
  id: ProviderId;
  name: string;
  blurb: string;
  keyUrl: string;
  /** Shown as the field hint, e.g. "gsk_…". */
  placeholder: string;
  /** Anything that does not match is rejected before it is stored. */
  format: RegExp;
};

export const KEY_PROVIDERS: KeyProvider[] = [
  { id: "groq", name: "Groq", blurb: "Very fast open models.", keyUrl: "https://console.groq.com/keys", placeholder: "gsk_…", format: /^gsk_[A-Za-z0-9]{20,200}$/ },
  { id: "openrouter", name: "OpenRouter", blurb: "One key, many models.", keyUrl: "https://openrouter.ai/settings/keys", placeholder: "sk-or-…", format: /^sk-or-[A-Za-z0-9_-]{20,200}$/ },
  { id: "nvidia", name: "NVIDIA", blurb: "NVIDIA-hosted models.", keyUrl: "https://build.nvidia.com/settings/api-keys", placeholder: "nvapi-…", format: /^nvapi-[A-Za-z0-9_-]{20,200}$/ },
  { id: "ollama", name: "Ollama Cloud", blurb: "Ollama's hosted models.", keyUrl: "https://ollama.com/settings/keys", placeholder: "Ollama API key", format: /^[A-Za-z0-9._-]{20,200}$/ },
];

export const keyProvider = (id: string): KeyProvider | undefined => KEY_PROVIDERS.find((p) => p.id === id);

/** Only the last 4 characters are ever kept readable. */
export const keyHintOf = (key: string): string => key.slice(-4);
