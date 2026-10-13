import "dotenv/config";
import { z } from "zod";

const blank = (v: unknown) => (typeof v === "string" && v.trim() === "" ? undefined : v);
const str = z.preprocess(blank, z.string().optional());
const num = (def: number) => z.preprocess(blank, z.coerce.number().default(def));
const optInt = z.preprocess(blank, z.coerce.number().int().positive().optional());

const schema = z.object({
  PORT: num(3000),
  OPENROUTER_API_KEY: str,
  OLLAMA_API_KEY: str,
  GROQ_API_KEY: str,
  NVIDIA_API_KEY: str,
  DATABASE_URL: str,
  EMBEDDING_PROVIDER: z.preprocess(blank, z.enum(["nvidia", "openrouter"]).optional()),
  EMBEDDING_MODEL: str,
  EMBEDDING_DIMENSIONS: num(1024),
  EMBEDDING_BATCH_SIZE: num(64),
  RAG_MIN_SIM: num(0.3),
  CHAT_RECALL_MIN_SIM: num(0.5),
  RAG_TOP_K: num(6),
  /** Resolve follow-up questions into standalone queries with a small model (time-boxed). */
  RAG_REWRITE: z.preprocess(blank, z.enum(["true", "false"]).default("true")),
  /** LLM rerank of the fused top candidates (adds up to ~2.5s; off by default). */
  RAG_RERANK: z.preprocess(blank, z.enum(["true", "false"]).default("false")),
  GITHUB_TOKEN: str,
  GITHUB_OAUTH_CLIENT_ID: str,
  GITHUB_OAUTH_CLIENT_SECRET: str,
  CONNECTIONS_KEY: str,
  /**
   * Master key (32 bytes, base64 or 64 hex chars; `openssl rand -base64 32`) that wraps every user's data key
   * (src/crypto/userData.ts). Required in production. Losing it makes all stored user content unreadable.
   */
  DATA_KEY: str,
  /** Comma-separated earlier DATA_KEY values, only for unwrapping during a key rotation (`pnpm data:encrypt --rewrap`). */
  DATA_KEY_PREVIOUS: str,
  NODE_ENV: str,
  /** Where this server is reachable from phones/browsers (OAuth callback URLs). */
  PUBLIC_BASE_URL: str,
  GOOGLE_WEB_CLIENT_ID: str,
  GOOGLE_WEB_CLIENT_SECRET: str,
  /** Optional browser API key for the Google Picker (Drive "Pick files"). */
  GOOGLE_PICKER_API_KEY: str,
  /** Notion public integration (Apps → Notion); optional. */
  NOTION_CLIENT_ID: str,
  NOTION_CLIENT_SECRET: str,
  STACKEXCHANGE_KEY: str,
  /** Comma-separated self-hosted SearXNG base URLs (JSON format enabled); last-resort web search fallback. */
  SEARXNG_URLS: str,
  /** "1" enables the Reddit search source (usually blocked from server IPs). */
  WEB_SEARCH_REDDIT: str,
  /** Optional Brave Search API key (free tier); adds Brave as the first general web engine. */
  BRAVE_SEARCH_API_KEY: str,
  /** Optional comma-separated web search providers to turn off (e.g. "bing,duckduckgo"). */
  WEB_SEARCH_DISABLE: str,
  OLLAMA_MONTHLY_REQUEST_BUDGET: optInt,
  API_TOKEN: str,
  /** Bearer token for scripts/publish-apk.sh (POST /app/releases only); unset disables that path. */
  RELEASE_TOKEN: str,
  S3_ENDPOINT: str,
  S3_REGION: str,
  S3_ACCESS_KEY_ID: str,
  S3_SECRET_ACCESS_KEY: str,
  S3_BUCKET: str,
  /** Largest object the storage accepts (Supabase Free: 50 MiB). Bigger videos are transcoded to fit. */
  S3_MAX_OBJECT_BYTES: num(50 * 1024 * 1024),
  // ---- accounts ----
  AUTH_JWT_SECRET: str,
  OWNER_EMAIL: str,
  LIMIT_CHAT_PER_DAY: num(200),
  LIMIT_TABLE_PER_DAY: num(20),
  LIMIT_UPLOADS_PER_DAY: num(30),
  LIMIT_STORAGE_MB: num(1024),
  LIMIT_DOCS_PER_DAY: num(5),
  LIMIT_AI_PER_DAY: num(150),
  /** On SIGTERM, how long in-flight answer streams may keep running before the process exits. */
  SHUTDOWN_GRACE_MS: num(60_000),
});

const env = schema.parse(process.env);

export const config = {
  port: env.PORT,
  shutdownGraceMs: env.SHUTDOWN_GRACE_MS,
  openrouterApiKey: env.OPENROUTER_API_KEY,
  ollamaApiKey: env.OLLAMA_API_KEY,
  groqApiKey: env.GROQ_API_KEY,
  nvidiaApiKey: env.NVIDIA_API_KEY,
  databaseUrl: env.DATABASE_URL,
  // NVIDIA has no daily cap; OpenRouter's free embeddings share the 50/day chat quota.
  embeddingProvider: env.EMBEDDING_PROVIDER ?? (env.NVIDIA_API_KEY ? "nvidia" : "openrouter"),
  embeddingModel:
    env.EMBEDDING_MODEL ??
    ((env.EMBEDDING_PROVIDER ?? (env.NVIDIA_API_KEY ? "nvidia" : "openrouter")) === "nvidia"
      ? "nvidia/llama-nemotron-embed-vl-1b-v2"
      : "nvidia/llama-nemotron-embed-vl-1b-v2:free"),
  embeddingDimensions: env.EMBEDDING_DIMENSIONS,
  embeddingBatchSize: env.EMBEDDING_BATCH_SIZE,
  ragMinSim: env.RAG_MIN_SIM,
  /** Cosine similarity a past chat needs to be surfaced unasked (cross-chat recall). */
  chatRecallMinSim: env.CHAT_RECALL_MIN_SIM,
  ragTopK: env.RAG_TOP_K,
  ragRewrite: env.RAG_REWRITE === "true",
  ragRerank: env.RAG_RERANK === "true",
  githubToken: env.GITHUB_TOKEN,
  /** Per-user GitHub connections (OAuth device flow); see src/connections. */
  githubOAuth: { clientId: env.GITHUB_OAUTH_CLIENT_ID, clientSecret: env.GITHUB_OAUTH_CLIENT_SECRET },
  connectionsKey: env.CONNECTIONS_KEY,
  dataKey: env.DATA_KEY,
  dataKeyPrevious: env.DATA_KEY_PREVIOUS,
  production: env.NODE_ENV === "production",
  /** Public origin, no trailing slash; GitHub's OAuth callback is `${publicBaseUrl}/auth/github/callback`. */
  publicBaseUrl: (env.PUBLIC_BASE_URL?.trim() || "https://sparky.cloudnsofts.com").replace(/\/+$/, ""),
  /**
   * "Continue with Google": the app gets an ID token for this Web client id
   * (serverClientId) and the server checks it is the token's audience. The
   * secret is optional, reserved for later server-side Drive access.
   */
  google: { webClientId: env.GOOGLE_WEB_CLIENT_ID?.trim(), webClientSecret: env.GOOGLE_WEB_CLIENT_SECRET },
  /** Google Picker browser key (Drive "Pick files"); without it the picker page explains what is missing. */
  googlePickerApiKey: env.GOOGLE_PICKER_API_KEY?.trim() || undefined,
  /** Notion public integration (OAuth); unset = "Not set up on this server". */
  notion: { clientId: env.NOTION_CLIENT_ID?.trim() || undefined, clientSecret: env.NOTION_CLIENT_SECRET?.trim() || undefined },
  stackExchangeKey: env.STACKEXCHANGE_KEY,
  webSearch: {
    searxngUrls: (env.SEARXNG_URLS ?? "").split(",").map((s) => s.trim().replace(/\/+$/, "")).filter(Boolean),
    reddit: env.WEB_SEARCH_REDDIT === "1",
    braveKey: env.BRAVE_SEARCH_API_KEY?.trim() || undefined,
    disabled: new Set((env.WEB_SEARCH_DISABLE ?? "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean)),
  },
  ollamaMonthlyBudget: env.OLLAMA_MONTHLY_REQUEST_BUDGET,
  apiToken: env.API_TOKEN,
  releaseToken: env.RELEASE_TOKEN?.trim() || undefined,
  s3: {
    endpoint: env.S3_ENDPOINT,
    region: env.S3_REGION ?? "us-east-1",
    accessKeyId: env.S3_ACCESS_KEY_ID,
    secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    bucket: env.S3_BUCKET ?? "attachments",
    maxObjectBytes: env.S3_MAX_OBJECT_BYTES,
  },
  auth: {
    jwtSecret: env.AUTH_JWT_SECRET,
    /** The account registering with this email becomes the owner. */
    ownerEmail: env.OWNER_EMAIL?.trim().toLowerCase(),
    accessTtlS: 15 * 60,
    refreshTtlDays: 30,
  },
  /** Default per-user daily limits; the owner is unlimited. */
  limits: {
    chat: env.LIMIT_CHAT_PER_DAY,
    table: env.LIMIT_TABLE_PER_DAY,
    uploads: env.LIMIT_UPLOADS_PER_DAY,
    storageBytes: env.LIMIT_STORAGE_MB * 1024 * 1024,
    docs: env.LIMIT_DOCS_PER_DAY,
    ai: env.LIMIT_AI_PER_DAY,
  },
};
