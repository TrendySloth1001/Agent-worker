import type { ProviderId } from "../models.js";

/** What a live check of a key found. `network` means we could not tell (nothing is stored for it). */
export type CheckResult = "valid" | "invalid" | "quota" | "network";

export const CHECK_TIMEOUT_MS = 8_000;

/** Friendly line per result (also what the app shows). */
export const CHECK_MESSAGE: Record<CheckResult, string> = {
  valid: "Works",
  invalid: "Key not accepted",
  quota: "Out of credit",
  network: "Couldn't reach provider",
};

type Call = { url: string; init: RequestInit };

/** One cheap, real call per provider: a key lookup where there is one, else a 1-token completion. */
function callFor(provider: ProviderId, key: string): Call {
  const bearer = { Authorization: `Bearer ${key}` };
  const json = { ...bearer, "Content-Type": "application/json" };
  switch (provider) {
    case "groq":
      return { url: "https://api.groq.com/openai/v1/models", init: { headers: bearer } };
    case "openrouter":
      return { url: "https://openrouter.ai/api/v1/key", init: { headers: bearer } };
    case "nvidia":
      return {
        url: "https://integrate.api.nvidia.com/v1/chat/completions",
        init: { method: "POST", headers: json, body: JSON.stringify({ model: "openai/gpt-oss-20b", messages: [{ role: "user", content: "hi" }], max_tokens: 1 }) },
      };
    case "ollama":
      return {
        url: "https://ollama.com/api/chat",
        init: { method: "POST", headers: json, body: JSON.stringify({ model: "gpt-oss:20b", messages: [{ role: "user", content: "hi" }], stream: false, options: { num_predict: 1 } }) },
      };
  }
}

const QUOTA_TEXT = /quota|credit|billing|insufficient|exceeded your|usage limit|payment|balance|upgrade/i;

/** Maps an HTTP status (+ body text) to a result. Exported for tests. */
export function classifyCheck(status: number, body: string): CheckResult {
  if (status >= 200 && status < 300) return "valid";
  if (status === 401 || status === 403) return "invalid";
  if (status === 402) return "quota";
  if (status === 429) return QUOTA_TEXT.test(body) ? "quota" : "valid"; // a plain rate limit means the key itself was accepted
  if (status >= 500 || status === 408) return "network";
  return "valid"; // 400/404/422: authenticated, the probe request itself was refused
}

/** Calls the provider with [key]. Never throws and never includes the key in what it returns. */
export async function checkKey(provider: ProviderId, key: string, fetchImpl: typeof fetch = fetch, timeoutMs = CHECK_TIMEOUT_MS): Promise<CheckResult> {
  const { url, init } = callFor(provider, key);
  try {
    const res = await fetchImpl(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
    const text = res.ok ? "" : await res.text().catch(() => "");
    return classifyCheck(res.status, text.slice(0, 2000));
  } catch {
    return "network";
  }
}
