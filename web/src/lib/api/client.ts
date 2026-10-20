import type { ZodType } from "zod";
import { errorBodySchema } from "./schemas";

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

const NETWORK_MESSAGE = "Cannot reach the server. Check your connection.";
const GENERIC_MESSAGE = "Something went wrong. Please try again.";

export interface RequestOptions {
  body?: unknown;
  signal?: AbortSignal;
  headers?: HeadersInit;
}

async function toError(res: Response): Promise<ApiError> {
  const parsed = errorBodySchema.safeParse(await res.json().catch(() => null));
  if (parsed.success) {
    return new ApiError(res.status, parsed.data.error.code, parsed.data.error.message);
  }
  return new ApiError(res.status, "http_error", GENERIC_MESSAGE);
}

export function createClient(base: string) {
  async function raw(
    method: string,
    path: string,
    options: RequestOptions = {},
  ): Promise<Response> {
    const headers = new Headers(options.headers);
    let body: BodyInit | undefined;
    if (options.body instanceof FormData) {
      body = options.body;
    } else if (options.body !== undefined) {
      headers.set("content-type", "application/json");
      body = JSON.stringify(options.body);
    }
    let res: Response;
    try {
      res = await fetch(`${base}${path}`, {
        method,
        headers,
        body,
        signal: options.signal,
        credentials: "same-origin",
        cache: "no-store",
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") throw error;
      throw new ApiError(0, "network", NETWORK_MESSAGE);
    }
    if (!res.ok) throw await toError(res);
    return res;
  }

  async function json<T>(
    method: string,
    path: string,
    schema: ZodType<T>,
    options?: RequestOptions,
  ): Promise<T> {
    const res = await raw(method, path, options);
    const parsed = schema.safeParse(await res.json().catch(() => null));
    if (!parsed.success) throw new ApiError(res.status, "bad_response", GENERIC_MESSAGE);
    return parsed.data;
  }

  return {
    raw,
    get: <T>(path: string, schema: ZodType<T>, options?: RequestOptions) =>
      json("GET", path, schema, options),
    post: <T>(path: string, schema: ZodType<T>, options?: RequestOptions) =>
      json("POST", path, schema, options),
    patch: <T>(path: string, schema: ZodType<T>, options?: RequestOptions) =>
      json("PATCH", path, schema, options),
    delete: <T>(path: string, schema: ZodType<T>, options?: RequestOptions) =>
      json("DELETE", path, schema, options),
  };
}

export type ApiClient = ReturnType<typeof createClient>;

export const sparkyApi = createClient("/api/sparky");
export const authApi = createClient("/api/auth");
