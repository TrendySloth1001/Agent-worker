/**
 * Vision-capable models, most reliable first. Auto uses only these when a turn
 * carries images or video frames. Each one was checked against its provider's
 * model list (Groq and OpenRouter report input_modalities: image; Ollama's
 * /api/show reports capability "vision") and with a real image request.
 * Llama 3.2 Vision on NVIDIA takes one image per prompt (see providers.ts).
 */
export const VISION_MODELS = [
  "groq:qwen/qwen3.8-27b",
  "nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
  "nvidia:meta/llama-3.2-11b-vision-instruct",
  "ollama:gemma4:31b",
  "openrouter:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
  "openrouter:google/gemma-4-31b-it:free",
  "openrouter:google/gemma-4-26b-a4b-it:free",
];

export const isVisionModel = (id: string): boolean => VISION_MODELS.includes(id);

/** OpenRouter's free vision models, for its server-side `models` fallback route. */
export const OPENROUTER_VISION_FREE = VISION_MODELS.filter((id) => id.startsWith("openrouter:") && id.endsWith(":free")).map((id) => id.slice("openrouter:".length));
