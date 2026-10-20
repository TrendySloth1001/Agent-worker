const MAX_WORDS = 4;

const DROPPED = new Set([
  "instruct",
  "it",
  "chat",
  "preview",
  "latest",
  "versatile",
  "hf",
  "fp8",
  "awq",
  "gguf",
  "turbo",
]);

const BRANDS: Record<string, string> = {
  llama: "Llama",
  gpt: "GPT",
  oss: "OSS",
  qwen: "Qwen",
  qwen3: "Qwen3",
  qwq: "QwQ",
  glm: "GLM",
  gemma: "Gemma",
  gemini: "Gemini",
  nemotron: "Nemotron",
  deepseek: "DeepSeek",
  mistral: "Mistral",
  mixtral: "Mixtral",
  kimi: "Kimi",
  claude: "Claude",
  phi: "Phi",
  vl: "VL",
  r1: "R1",
  v3: "V3",
};

const SIZE = /^[\d.x]+[bmk]$/;
const EXPERTS = /^\d+e$/i;
const DATE_SUFFIX = /[-_.]?\d{4}-?\d{2}-?\d{2}$/;

function prettyWord(word: string): string {
  const lower = word.toLowerCase();
  const brand = BRANDS[lower];
  if (brand) return brand;
  if (SIZE.test(lower)) return lower.slice(0, -1) + lower.slice(-1).toUpperCase();
  if (/^\d/.test(word)) return word;
  return word.charAt(0).toUpperCase() + word.slice(1);
}

export function prettyModelName(id: string): string {
  let s = id.trim();
  if (!s) return "";
  s = s.split("/").at(-1) ?? s;
  s = s.split(":")[0] ?? s;
  s = s.replace(DATE_SUFFIX, "");
  return s
    .split(/[-_\s]+/)
    .filter((w) => w && !DROPPED.has(w.toLowerCase()) && !EXPERTS.test(w))
    .map(prettyWord)
    .slice(0, MAX_WORDS)
    .join(" ");
}
