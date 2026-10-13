import type { ModelInfo } from "./models.js";

/** Plain-language profile of a model family, served to the app so it never hardcodes it. */
export type ModelAbout = {
  /** Who made the model (not who serves it). */
  maker: string;
  /** One or two friendly sentences on what it is good at. */
  about: string;
  /** Context window in tokens (how much text it can keep in mind). */
  contextTokens: number;
  /** Rough feel: fast, balanced or deep. */
  speed: "fast" | "balanced" | "deep";
};

const FAMILIES: { match: RegExp; about: ModelAbout }[] = [
  {
    match: /gpt-oss-120b|gpt-oss:120b/,
    about: {
      maker: "OpenAI",
      about: "A strong all-rounder for reasoning, writing and code. Thoughtful answers on harder questions.",
      contextTokens: 128_000,
      speed: "balanced",
    },
  },
  {
    match: /gpt-oss-20b|gpt-oss:20b/,
    about: {
      maker: "OpenAI",
      about: "A light, quick model for everyday questions, short writing and simple code.",
      contextTokens: 128_000,
      speed: "fast",
    },
  },
  {
    match: /nemotron-3-ultra/,
    about: {
      maker: "NVIDIA",
      about: "NVIDIA's largest model. Great for long documents, deep reasoning and detailed answers.",
      contextTokens: 1_000_000,
      speed: "deep",
    },
  },
  {
    match: /nemotron-3-super/,
    about: {
      maker: "NVIDIA",
      about: "A capable mid-size model that handles research, analysis and coding well.",
      contextTokens: 1_000_000,
      speed: "balanced",
    },
  },
  {
    match: /nemotron-3\.5-lightning|nemotron-3-nano/,
    about: {
      maker: "NVIDIA",
      about: "Built for speed. Good for quick replies, summaries and everyday chat.",
      contextTokens: 128_000,
      speed: "fast",
    },
  },
  {
    match: /qwen/,
    about: {
      maker: "Alibaba (Qwen)",
      about: "Strong at maths, code and many languages, with clear step-by-step answers.",
      contextTokens: 128_000,
      speed: "balanced",
    },
  },
  {
    match: /gemma/,
    about: {
      maker: "Google",
      about: "A friendly, well-rounded model for conversation, explanations and writing.",
      contextTokens: 128_000,
      speed: "balanced",
    },
  },
  {
    match: /glm/,
    about: {
      maker: "Z.ai (Zhipu)",
      about: "Quick and capable for chat, writing and everyday coding help.",
      contextTokens: 128_000,
      speed: "fast",
    },
  },
];

/** Descriptive fields for a model, or an empty object when the family is unknown. */
export function aboutModel(m: Pick<ModelInfo, "id">): Partial<ModelAbout> {
  const id = m.id.toLowerCase();
  return FAMILIES.find((f) => f.match.test(id))?.about ?? {};
}
