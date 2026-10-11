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
  RAG_TOP_K: num(6),
  GITHUB_TOKEN: str,
  GITHUB_OAUTH_CLIENT_ID: str,
  GITHUB_OAUTH_CLIENT_SECRET: str,
  CONNECTIONS_KEY: str,
  STACKEXCHANGE_KEY: str,
  OLLAMA_MONTHLY_REQUEST_BUDGET: optInt,
  API_TOKEN: str,
  S3_ENDPOINT: str,
  S3_REGION: str,
  S3_ACCESS_KEY_ID: str,
  S3_SECRET_ACCESS_KEY: str,
  S3_BUCKET: str,
  // ---- accounts ----
  AUTH_JWT_SECRET: str,
  OWNER_EMAIL: str,
  LIMIT_CHAT_PER_DAY: num(200),
  LIMIT_TABLE_PER_DAY: num(20),
  LIMIT_UPLOADS_PER_DAY: num(30),
  LIMIT_STORAGE_MB: num(500),
});

const env = schema.parse(process.env);

export const config = {
  port: env.PORT,
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
  ragTopK: env.RAG_TOP_K,
  githubToken: env.GITHUB_TOKEN,
  /** Per-user GitHub connections (OAuth device flow); see src/connections. */
  githubOAuth: { clientId: env.GITHUB_OAUTH_CLIENT_ID, clientSecret: env.GITHUB_OAUTH_CLIENT_SECRET },
  connectionsKey: env.CONNECTIONS_KEY,
  stackExchangeKey: env.STACKEXCHANGE_KEY,
  ollamaMonthlyBudget: env.OLLAMA_MONTHLY_REQUEST_BUDGET,
  apiToken: env.API_TOKEN,
  s3: {
    endpoint: env.S3_ENDPOINT,
    region: env.S3_REGION ?? "us-east-1",
    accessKeyId: env.S3_ACCESS_KEY_ID,
    secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    bucket: env.S3_BUCKET ?? "attachments",
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
  },
};
