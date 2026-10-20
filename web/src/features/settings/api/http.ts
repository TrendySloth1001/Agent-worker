import { z } from "zod";

export const API_BASE = "/api/sparky";

const errorBody = z.object({
  error: z.object({ code: z.string().optional(), message: z.string().optional() }),
});

export class ApiError extends Error {
  readonly status: number;
  readonly code: string | undefined;

  constructor(status: number, message: string, code?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

export interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  query?: Record<string, string | number | undefined>;
  signal?: AbortSignal;
}

const buildUrl = (path: string, query: RequestOptions["query"]): string => {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined) params.set(key, String(value));
  }
  const qs = params.toString();
  return `${API_BASE}${path}${qs ? `?${qs}` : ""}`;
};

const failure = async (res: Response): Promise<ApiError> => {
  const parsed = errorBody.safeParse(await res.json().catch(() => null));
  const detail = parsed.success ? parsed.data.error : undefined;
  return new ApiError(
    res.status,
    detail?.message ?? "Something went wrong. Try again.",
    detail?.code,
  );
};

const send = async (path: string, options: RequestOptions): Promise<Response> => {
  const res = await fetch(buildUrl(path, options.query), {
    method: options.method ?? "GET",
    headers: options.body === undefined ? undefined : { "Content-Type": "application/json" },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
    signal: options.signal,
    cache: "no-store",
  });
  if (!res.ok) throw await failure(res);
  return res;
};

export async function request<S extends z.ZodType>(
  path: string,
  schema: S,
  options: RequestOptions = {},
): Promise<z.infer<S>> {
  const res = await send(path, options);
  return schema.parse(await res.json());
}

export async function command(path: string, options: RequestOptions = {}): Promise<void> {
  await send(path, options);
}

export const errorMessage = (error: unknown): string =>
  error instanceof Error ? error.message : "Something went wrong. Try again.";
