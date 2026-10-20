import { QueryClient } from "@tanstack/react-query";
import { settingsKeys } from "@/features/settings/api/query-keys";

const NOW = "2026-10-18T09:30:00.000Z";

const day = (offset: number): string =>
  new Date(Date.UTC(2026, 9, 20 - offset)).toISOString().slice(0, 10);

const requestsPerDay = [4, 9, 0, 14, 22, 11, 17];

export function createFixtureClient(): QueryClient {
  const client = new QueryClient({
    defaultOptions: { queries: { staleTime: Infinity, retry: false, refetchOnWindowFocus: false } },
  });

  client.setQueryData(settingsKeys.me, {
    user: {
      id: "u1",
      email: "nikhil@example.com",
      name: "Nikhil Kumawat",
      avatarUrl: null,
      role: "member",
      createdAt: NOW,
      hasPassword: true,
    },
  });

  client.setQueryData(settingsKeys.sessions, {
    sessions: [
      {
        id: "s1",
        device: "Chrome on macOS",
        createdAt: NOW,
        lastUsedAt: NOW,
        expiresAt: NOW,
        current: true,
      },
      {
        id: "s2",
        device: "Pixel 9, sparky app",
        createdAt: "2026-10-02T09:30:00.000Z",
        lastUsedAt: NOW,
        expiresAt: NOW,
        current: false,
      },
    ],
  });

  client.setQueryData(settingsKeys.signIn, {
    hasPassword: true,
    identities: [{ id: "i1", provider: "github", email: null, login: "nikhil-k", createdAt: NOW }],
  });

  client.setQueryData(settingsKeys.models, {
    models: [
      {
        id: "groq:openai/gpt-oss-120b",
        name: "GPT-OSS 120B",
        provider: "groq",
        maker: "OpenAI",
        about: "",
        contextTokens: 128000,
        speed: "balanced",
        cooldownUntil: null,
      },
      {
        id: "nvidia:nvidia/nemotron-3-ultra-550b-a55b",
        name: "Nemotron 3 Ultra",
        provider: "nvidia",
        maker: "NVIDIA",
        about: "",
        contextTokens: 1000000,
        speed: "deep",
        cooldownUntil: null,
      },
      {
        id: "groq:openai/gpt-oss-20b",
        name: "GPT-OSS 20B",
        provider: "groq",
        maker: "OpenAI",
        about: "",
        contextTokens: 128000,
        speed: "fast",
        cooldownUntil: NOW,
      },
    ],
  });

  client.setQueryData(settingsKeys.keys, {
    hasValidKey: true,
    providers: [
      {
        id: "groq",
        name: "Groq",
        blurb: "Very fast open models.",
        keyUrl: "https://console.groq.com/keys",
        placeholder: "gsk_…",
        key: {
          provider: "groq",
          label: "",
          hint: "a1B2",
          status: "valid",
          lastCheckedAt: NOW,
          createdAt: NOW,
        },
      },
      {
        id: "openrouter",
        name: "OpenRouter",
        blurb: "One key, many models.",
        keyUrl: "https://openrouter.ai/settings/keys",
        placeholder: "sk-or-…",
        key: {
          provider: "openrouter",
          label: "",
          hint: "9xZq",
          status: "quota",
          lastCheckedAt: NOW,
          createdAt: NOW,
        },
      },
      {
        id: "nvidia",
        name: "NVIDIA",
        blurb: "NVIDIA-hosted models.",
        keyUrl: "https://build.nvidia.com/settings/api-keys",
        placeholder: "nvapi-…",
        key: null,
      },
      {
        id: "ollama",
        name: "Ollama Cloud",
        blurb: "Ollama's hosted models.",
        keyUrl: "https://ollama.com/settings/keys",
        placeholder: "Ollama API key",
        key: null,
      },
    ],
  });

  client.setQueryData(settingsKeys.keyUsage(7), {
    enabled: true,
    days: 7,
    totals: {
      requests: 77,
      errors: 3,
      promptTokens: 52000,
      completionTokens: 31000,
      tokens: 83000,
      avgLatencyMs: 1840,
    },
    byDay: requestsPerDay.map((requests, i) => ({
      day: day(requestsPerDay.length - 1 - i),
      requests,
      tokens: requests * 1000,
      errors: 0,
    })),
    byProvider: [{ provider: "groq", requests: 77, tokens: 83000, errors: 3, avgLatencyMs: 1840 }],
    byModel: [
      {
        provider: "groq",
        model: "openai/gpt-oss-120b",
        requests: 77,
        tokens: 83000,
        errors: 3,
        avgLatencyMs: 1840,
      },
    ],
  });

  client.setQueryData(settingsKeys.memory(""), {
    enabled: true,
    chatRecall: false,
    total: 3,
    max: 500,
    items: [
      {
        id: "m1",
        text: "Name is Nikhil. Works on the sparky Flutter app.",
        kind: "identity",
        pinned: true,
        createdAt: NOW,
        updatedAt: NOW,
      },
      {
        id: "m2",
        text: "Prefers short answers with code first.",
        kind: "preference",
        pinned: false,
        createdAt: NOW,
        updatedAt: NOW,
      },
      {
        id: "m3",
        text: "Lives in Pune.",
        kind: "fact",
        pinned: false,
        createdAt: NOW,
        updatedAt: NOW,
      },
    ],
  });

  client.setQueryData(settingsKeys.sources, {
    sources: [
      {
        id: "k1",
        type: "web",
        uri: "https://nextjs.org/docs",
        title: "Next.js documentation",
        status: "ready",
        progress: null,
        docCount: 42,
        chunkCount: 610,
        error: null,
        lastIngestedAt: NOW,
        createdAt: NOW,
      },
      {
        id: "k2",
        type: "note",
        uri: "note:abc",
        title: "Deploy checklist",
        status: "ready",
        progress: null,
        docCount: 1,
        chunkCount: 4,
        error: null,
        lastIngestedAt: NOW,
        createdAt: NOW,
      },
      {
        id: "k3",
        type: "repo",
        uri: "github.com/acme/api",
        title: "acme/api",
        status: "failed",
        progress: null,
        docCount: 0,
        chunkCount: 0,
        error: "Couldn't read that repository.",
        lastIngestedAt: null,
        createdAt: NOW,
      },
    ],
  });
  client.setQueryData(settingsKeys.stats, { sources: 3, documents: 43, chunks: 614 });

  client.setQueryData(settingsKeys.connections, {
    items: [
      {
        provider: "github",
        accountLogin: "nikhil-k",
        avatarUrl: null,
        accountName: null,
        accountEmail: null,
        scopes: ["repo"],
        missingScopes: [],
        needsReauth: false,
      },
    ],
    providers: {
      github: { configured: true, web: true },
      google_drive: { configured: true, web: true },
    },
  });

  return client;
}
