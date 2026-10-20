import type { z } from "zod";

export const API_BASE = "/api/sparky";

const FALLBACK = {
  generic: "Something went wrong. Please try again.",
  offline: "Can't reach sparky. Check your connection and try again.",
  expired: "Your session expired. Please sign in again.",
  busy: "You're going fast. Give it a few seconds.",
} as const;

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
    readonly retryable: boolean,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

const messageFor = (status: number): string => {
  if (status === 401) return FALLBACK.expired;
  if (status === 429) return FALLBACK.busy;
  return FALLBACK.generic;
};

async function failure(res: Response): Promise<ApiError> {
  let code = "http";
  let message = messageFor(res.status);
  let retryable = res.status >= 500;
  try {
    const body: unknown = await res.json();
    if (typeof body === "object" && body !== null && "error" in body) {
      const err = (body as { error: { code?: unknown; message?: unknown; retryable?: unknown } })
        .error;
      if (typeof err.code === "string") code = err.code;
      if (typeof err.message === "string" && err.message) message = err.message;
      if (typeof err.retryable === "boolean") retryable = err.retryable;
    }
  } catch {
    /* non-JSON error body */
  }
  return new ApiError(message, res.status, code, retryable);
}

export async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  let res: Response;
  try {
    res = await fetch(`${API_BASE}${path}`, { credentials: "same-origin", ...init });
  } catch (cause) {
    if (init.signal?.aborted) throw cause;
    throw new ApiError(FALLBACK.offline, 0, "offline", true);
  }
  if (!res.ok) throw await failure(res);
  return res;
}

export async function apiJson<S extends z.ZodType>(
  path: string,
  schema: S,
  init: RequestInit = {},
): Promise<z.infer<S>> {
  const res = await apiFetch(path, init);
  return schema.parse(await res.json());
}

export const jsonBody = (method: string, body: unknown): RequestInit => ({
  method,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(body),
});
