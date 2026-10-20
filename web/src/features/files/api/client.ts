import { z } from "zod";
import { TEXT_PAGE_CHARS, UPLOAD_TIMEOUT_MS } from "../lib/limits";
import {
  fileInfoSchema,
  insightPayloadSchema,
  textPageSchema,
  uploadResponseSchema,
  type FileInfo,
  type InsightPayload,
  type TextPage,
} from "./schemas";

export const FILES_BASE = "/api/sparky/files";

const errorBodySchema = z.object({ error: z.object({ message: z.string() }) });

export class FilesApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "FilesApiError";
  }
}

async function failure(response: Response): Promise<FilesApiError> {
  const body = errorBodySchema.safeParse(await response.json().catch(() => null));
  return new FilesApiError(
    body.success ? body.data.error.message : "Something went wrong.",
    response.status,
  );
}

async function request<T>(
  path: string,
  schema: z.ZodType<T>,
  init?: RequestInit,
  fetcher: typeof fetch = fetch,
): Promise<T> {
  const response = await fetcher(`${FILES_BASE}${path}`, init);
  if (!response.ok) throw await failure(response);
  return schema.parse(await response.json());
}

export async function getFile(id: string, fetcher?: typeof fetch): Promise<FileInfo> {
  return (await request(`/${id}`, z.object({ file: fileInfoSchema }), undefined, fetcher)).file;
}

export function getInsight(id: string, fetcher?: typeof fetch): Promise<InsightPayload> {
  return request(`/${id}/insight`, insightPayloadSchema, undefined, fetcher);
}

export function readWithSparky(id: string, fetcher?: typeof fetch): Promise<InsightPayload> {
  const init = { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" };
  return request(`/${id}/insight`, insightPayloadSchema, init, fetcher);
}

export function getText(
  id: string,
  offset = 0,
  limit = TEXT_PAGE_CHARS,
  fetcher?: typeof fetch,
): Promise<TextPage> {
  return request(`/${id}/text?offset=${offset}&limit=${limit}`, textPageSchema, undefined, fetcher);
}

export function proxiedBlobPath(url: string): string | null {
  try {
    const parsed = new URL(url, "http://local");
    const match = /\/files\/blob\/([0-9a-f-]{36})\/(original|thumb)$/i.exec(parsed.pathname);
    return match ? `${FILES_BASE}/blob/${match[1]}/${match[2]}${parsed.search}` : null;
  } catch {
    return null;
  }
}

export interface UploadOptions {
  conversationId?: string;
  signal?: AbortSignal;
  onProgress?: (ratio: number) => void;
  createRequest?: () => XMLHttpRequest;
}

export function uploadFile(file: File, options: UploadOptions = {}): Promise<FileInfo> {
  return new Promise((resolve, reject) => {
    const xhr = options.createRequest ? options.createRequest() : new XMLHttpRequest();
    const form = new FormData();
    if (options.conversationId) form.append("conversationId", options.conversationId);
    form.append("file", file, file.name);

    xhr.open("POST", FILES_BASE);
    xhr.timeout = UPLOAD_TIMEOUT_MS;
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && event.total > 0)
        options.onProgress?.(event.loaded / event.total);
    };
    xhr.onerror = () => reject(new FilesApiError("Upload failed. Check your connection.", 0));
    xhr.ontimeout = () => reject(new FilesApiError("The upload took too long.", 0));
    xhr.onabort = () => reject(new DOMException("Upload cancelled", "AbortError"));
    xhr.onload = () => {
      let body: unknown = null;
      try {
        body = JSON.parse(xhr.responseText);
      } catch {
        body = null;
      }
      const parsed = uploadResponseSchema.safeParse(body);
      if (xhr.status >= 200 && xhr.status < 300 && parsed.success) {
        options.onProgress?.(1);
        resolve(parsed.data.file);
        return;
      }
      const failed = errorBodySchema.safeParse(body);
      reject(
        new FilesApiError(
          failed.success ? failed.data.error.message : "Upload failed.",
          xhr.status,
        ),
      );
    };

    const { signal } = options;
    if (signal) {
      if (signal.aborted) return reject(new DOMException("Upload cancelled", "AbortError"));
      signal.addEventListener("abort", () => xhr.abort(), { once: true });
    }
    xhr.send(form);
  });
}
