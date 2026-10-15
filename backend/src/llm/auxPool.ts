/**
 * The small-model pool for helper calls (follow-up chips, starters, autocomplete, titles).
 *
 * They used to share the big answer models (Groq's 120B has the same 8k tokens-per-minute window the
 * reply needs), so a chip generation could be the request that tipped a reply into a 429. The pool is
 * only small models, ordered by who has headroom right now, and never includes a model that is cooling
 * down, out of quota or not configured.
 */
import { cooldownUntil } from "../models.js";
import { providerConfigured } from "./router.js";
import { check } from "./budget.js";
import { isQuotaBlocked } from "./quota.js";
import { AUX_HEADROOM_REQUESTS, AUX_HEADROOM_TOKENS } from "./aux.js";

/** Each Groq model has its own minute window, so the 20B here never touches the 120B the replies use. */
export const AUX_POOL = ["groq:openai/gpt-oss-20b", "nvidia:nvidia/nemotron-3.5-lightning-30b-a3b", "ollama:gpt-oss:20b"];

const providerOf = (id: string) => id.slice(0, id.indexOf(":")) as "ollama" | "openrouter" | "groq" | "nvidia";

/** Pool models usable now, those with budget headroom for a call of [tokens] first. */
export function auxModels(tokens = 1_500, pool: string[] = AUX_POOL): string[] {
  const usable = pool.filter((id) => providerConfigured(providerOf(id)) && cooldownUntil(id) === null && !isQuotaBlocked(id));
  const fits = usable.filter((id) => check(id, tokens + AUX_HEADROOM_TOKENS, { requests: AUX_HEADROOM_REQUESTS }).ok);
  return [...fits, ...usable.filter((id) => !fits.includes(id))];
}
