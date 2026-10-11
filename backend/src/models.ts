export type ProviderId = "ollama" | "openrouter" | "groq" | "nvidia";
export type ModelInfo = { id: string; name: string; provider: ProviderId };

// Free models on our accounts. Order is the "Auto" order: fast, generous
// quotas first, so the scarce OpenRouter daily requests are used last.
export const MODELS: ModelInfo[] = [
  { id: "groq:openai/gpt-oss-120b", name: "GPT-OSS 120B", provider: "groq" },
  { id: "ollama:gpt-oss:120b", name: "GPT-OSS 120B", provider: "ollama" },
  { id: "nvidia:nvidia/nemotron-3-ultra-550b-a55b", name: "Nemotron 3 Ultra", provider: "nvidia" },
  { id: "groq:qwen/qwen3.8-27b", name: "Qwen 3.8 27B", provider: "groq" },
  { id: "nvidia:nvidia/nemotron-3-super-120b-a12b", name: "Nemotron 3 Super", provider: "nvidia" },
  { id: "ollama:gemma4:31b", name: "Gemma 4 31B", provider: "ollama" },
  { id: "nvidia:z-ai/glm-5.3-flash", name: "GLM 5.3 Flash", provider: "nvidia" },
  { id: "openrouter:nvidia/nemotron-3-ultra-550b-a55b:free", name: "Nemotron 3 Ultra", provider: "openrouter" },
  { id: "ollama:nemotron-3-ultra", name: "Nemotron 3 Ultra", provider: "ollama" },
  { id: "groq:openai/gpt-oss-20b", name: "GPT-OSS 20B", provider: "groq" },
  { id: "nvidia:nvidia/nemotron-3.5-lightning-30b-a3b", name: "Nemotron 3.5 Lightning", provider: "nvidia" },
  { id: "openrouter:nvidia/nemotron-3-super-120b-a12b:free", name: "Nemotron 3 Super", provider: "openrouter" },
  { id: "ollama:nemotron-3-super", name: "Nemotron 3 Super", provider: "ollama" },
  { id: "openrouter:google/gemma-4-31b-it:free", name: "Gemma 4 31B", provider: "openrouter" },
  { id: "ollama:gpt-oss:20b", name: "GPT-OSS 20B", provider: "ollama" },
  { id: "nvidia:openai/gpt-oss-20b", name: "GPT-OSS 20B", provider: "nvidia" },
  { id: "ollama:nemotron-3-nano:30b", name: "Nemotron 3 Nano", provider: "ollama" },
];

// Per-model cooldowns after quota/auth/rate-limit failures.
const cooldowns = new Map<string, number>();

export function setCooldown(id: string, ms: number) {
  cooldowns.set(id, Date.now() + ms);
}

export function clearCooldown(id: string) {
  cooldowns.delete(id);
}

/** Epoch ms until which the model is skipped by Auto, or null. */
export function cooldownUntil(id: string): number | null {
  const until = cooldowns.get(id);
  if (!until) return null;
  if (until <= Date.now()) {
    cooldowns.delete(id);
    return null;
  }
  return until;
}
