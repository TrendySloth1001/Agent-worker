/**
 * What users read. Every `message` the app can show (HTTP error bodies, SSE
 * `error`/`notice` events, stored file/source failures) is plain and friendly:
 * no provider or model names, no status codes, no stack or upstream text.
 * The machine `code` next to it stays stable for app logic; details go to
 * the logs and the owner-only telemetry.
 */
export const USER_MSG = {
  generic: "Something went wrong — please try again.",
  busy: "sparky is busy right now — try again in a minute.",
  slowDown: "You're going fast — give it a few seconds.",
  allQuota: "sparky has reached its limit for now — try again a bit later.",
  modelBusy: "That model is busy right now — try another one or use Auto.",
  modelQuota: "That model has reached its limit for now — try another one or use Auto.",
  modelRejected: "That model couldn't answer this one — try another one or use Auto.",
  unknownModel: "That model isn't available — pick another one.",
  badRequest: "Something about that request wasn't right — please try again.",
  notFound: "Couldn't find that.",
  unavailable: "That isn't available right now — try again shortly.",
  timeout: "That took too long — try again.",
  storage: "sparky can't reach its storage right now — try again shortly.",
  tooLong: "This chat is getting long — start a new one to keep going.",
  generating: "Something went wrong while writing the answer — please try again.",
  visionSwitched: "That model can't see images, so another one is answering.",
  visionUnavailable: "Couldn't read that image, so I answered from your text.",
  webSearchFailed: "Couldn't search the web just now, so I answered without it.",
  answerIncomplete: "I couldn't put an answer together just now — please try again.",
  kbUnavailable: "Your knowledge base isn't available right now, so I answered without it.",
  fallback: "Switching to another model…",
  roundTableSkipped: "Short message, so I answered without the round table.",
  roundTableDegraded: "Not enough voices joined the round table, so one model answered.",
  signInUnavailable: "This sign-in option isn't available right now.",
  signInFailed: "Sign-in didn't finish — please try again.",
  appsUnavailable: "Connected apps aren't available right now.",
  githubUnavailable: "GitHub isn't available right now — try again shortly.",
  githubNotFound: "Couldn't find that on GitHub — it may be private.",
  githubRefused: "GitHub didn't allow that.",
  githubRejected: "GitHub couldn't make that change — check the details and try again.",
  webUnavailable: "Web search isn't available right now — try again in a bit.",
  voiceUnavailable: "Voice typing isn't available right now.",
  voiceFailed: "Couldn't hear that recording — try again.",
  uploadsUnavailable: "File uploads aren't available right now.",
  uploadFailed: "Couldn't upload that file — try again.",
  fileFailed: "Couldn't process this file.",
  insightUnavailable: "sparky couldn't read this one just now — try again in a moment.",
  insightNoText: "sparky hasn't found any text in this file to read.",
  insightNotReady: "sparky is still reading this file — try again in a moment.",
  transcribeFailed: "Couldn't transcribe this file.",
  knowledgeFailed: "Couldn't add this to your knowledge base — try again later.",
  knowledgeUnavailable: "Your knowledge base isn't available right now — try again shortly.",
} as const;

/** Fallback per error code when a message is not fit to show. */
const BY_CODE: Record<string, string> = {
  rate_limited: USER_MSG.slowDown,
  fair_use: USER_MSG.slowDown,
  busy: USER_MSG.busy,
  all_models_failed: USER_MSG.busy,
  model_busy: USER_MSG.modelBusy,
  upstream_failed: USER_MSG.unavailable,
  upstream_timeout: USER_MSG.timeout,
  connector_timeout: USER_MSG.timeout,
  unavailable: USER_MSG.unavailable,
  bad_request: USER_MSG.badRequest,
  not_found: USER_MSG.notFound,
  payload_too_large: "That's too large to send.",
  internal: USER_MSG.generic,
};

// Words and shapes that only make sense to a developer.
const DEV_WORDS =
  /\b(4\d\d|5\d\d|HTTP|exception|stack(?!\s*overflow)|undefined|null|NaN|provider|quota|ollama|groq|openrouter|nvidia|graphql|multipart|uuid|json|econn\w*|etimedout|enotfound|eai_again|socket|fetch failed|api key|env|stderr|ffmpeg|prisma|sql|s3)\b/i;
const ENV_VAR = /\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b/;
const MODEL_ID = /\b[a-z0-9-]+:[\w.-]+\/[\w.:-]+/i;
const CODEY = /`|=>|\{|\}|\w\(\)|\bat \w+ \(|https?:\/\/|^[a-z]\w*(\.\w+)*:\s|\b[a-z]\w*\.\d+\b/;

/** True when [message] reads like something written for a person, not a log. */
export function isUserSafe(message: string | null | undefined): message is string {
  if (!message) return false;
  const m = message.trim();
  if (!m || m.length > 200) return false;
  return !DEV_WORDS.test(m) && !ENV_VAR.test(m) && !MODEL_ID.test(m) && !CODEY.test(m);
}

/** [message] when it is fit for the user, else the friendly line for [code] (or a generic one). */
export function userMessage(code: string, message: string | null | undefined, fallback?: string): string {
  if (isUserSafe(message)) return message.trim();
  return fallback ?? BY_CODE[code] ?? USER_MSG.generic;
}

/** A stored failure text (files, knowledge sources) as the app should show it. */
export const userSafe = (message: string | null | undefined, fallback: string): string | null => (message == null ? null : isUserSafe(message) ? message : fallback);
