import { z } from "zod";

export const TONES = [
  "none",
  "friendly",
  "professional",
  "casual",
  "direct",
  "enthusiastic",
] as const;
export const LENGTHS = ["concise", "balanced", "detailed"] as const;
export const MODES = ["engineer", "debug", "review", "architect", "explain"] as const;
export const TEXT_SIZES = ["small", "normal", "large", "huge"] as const;
export const MODEL_PRESETS = ["auto", "fast", "smart"] as const;

export const FAST_MODEL_ID = "groq:openai/gpt-oss-20b";
export const SMART_MODEL_ID = "nvidia:nvidia/nemotron-3-ultra-550b-a55b";

export const TEXT_SCALE: Record<(typeof TEXT_SIZES)[number], number> = {
  small: 0.9,
  normal: 1,
  large: 1.15,
  huge: 1.3,
};

export const LANGUAGE_MAX = 40;
export const INSTRUCTIONS_MAX = 1000;

export const preferencesSchema = z.object({
  model: z.string().min(1).catch("auto"),
  tone: z.enum(TONES).catch("none"),
  length: z.enum(LENGTHS).catch("balanced"),
  mode: z.enum(MODES).nullable().catch(null),
  language: z.string().max(LANGUAGE_MAX).catch(""),
  instructions: z.string().max(INSTRUCTIONS_MAX).catch(""),
  textSize: z.enum(TEXT_SIZES).catch("normal"),
});
export type Preferences = z.infer<typeof preferencesSchema>;
export type Tone = Preferences["tone"];
export type ReplyLength = Preferences["length"];
export type WorkMode = NonNullable<Preferences["mode"]>;
export type TextSize = Preferences["textSize"];

export const DEFAULT_PREFERENCES: Preferences = {
  model: "auto",
  tone: "none",
  length: "balanced",
  mode: null,
  language: "",
  instructions: "",
  textSize: "normal",
};

export const resolveModelId = (model: string): string | null => {
  if (model === "auto") return null;
  if (model === "fast") return FAST_MODEL_ID;
  if (model === "smart") return SMART_MODEL_ID;
  return model;
};
