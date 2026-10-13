/**
 * Vision-capable models, fastest first. Auto uses only these when a turn
 * carries images or video frames. Each one was checked against its provider's
 * model list (Groq and OpenRouter report input_modalities: image; Ollama's
 * /api/show reports capability "vision") and with a real image request.
 * Llama 3.2 Vision on NVIDIA takes one image per prompt (see providers.ts).
 *
 * Order matters: fast non-reasoning models answer in a second or two, while
 * the reasoning/omni models think for 20-40 s before the first visible word,
 * so they are only a last resort.
 */
export const VISION_MODELS = [
  "groq:qwen/qwen3.8-27b",
  "nvidia:meta/llama-3.2-11b-vision-instruct",
  "openrouter:google/gemma-4-31b-it:free",
  "openrouter:google/gemma-4-26b-a4b-it:free",
  "ollama:gemma4:31b",
  "nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
  "openrouter:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
];

/** Reasoning vision models: slow to the first visible token, so never used for quick identification. */
export const REASONING_VISION = /reasoning|omni/i;

export const isVisionModel = (id: string): boolean => VISION_MODELS.includes(id);

/** OpenRouter's free vision models, for its server-side `models` fallback route. */
export const OPENROUTER_VISION_FREE = VISION_MODELS.filter((id) => id.startsWith("openrouter:") && id.endsWith(":free")).map((id) => id.slice("openrouter:".length));

/** A vision model that shows no visible text after this long gives way to the next one (when there is one). */
export const VISION_FIRST_TOKEN_MS = 12_000;

/** Images sent to a model are scaled to fit this long edge and re-encoded as JPEG: fewer image tokens, faster calls. */
export const IMAGE_MAX_EDGE = 1024;
export const IMAGE_JPEG_QUALITY = 80;
