import { describe, expect, it, vi } from "vitest";
import {
  FilesApiError,
  getInsight,
  getText,
  proxiedBlobPath,
  readWithSparky,
  uploadFile,
} from "./client";

const FILE = {
  id: "11111111-1111-4111-8111-111111111111",
  name: "a.png",
  mime: "image/png",
  size: 3,
  kind: "image",
  status: "ready",
  url: "https://api.example.com/files/blob/11111111-1111-4111-8111-111111111111/original?exp=1&sig=ab",
  meta: {},
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

class FakeXhr {
  status = 0;
  responseText = "";
  timeout = 0;
  upload: {
    onprogress:
      ((event: { lengthComputable: boolean; loaded: number; total: number }) => void) | null;
  } = { onprogress: null };
  onload: (() => void) | null = null;
  onerror: (() => void) | null = null;
  ontimeout: (() => void) | null = null;
  onabort: (() => void) | null = null;
  opened: [string, string] | null = null;
  sent: FormData | null = null;
  open(method: string, url: string) {
    this.opened = [method, url];
  }
  send(body: FormData) {
    this.sent = body;
  }
  abort() {
    this.onabort?.();
  }
  respond(status: number, body: unknown) {
    this.status = status;
    this.responseText = JSON.stringify(body);
    this.onload?.();
  }
}

function start(options: Parameters<typeof uploadFile>[1] = {}) {
  const xhr = new FakeXhr();
  const file = new File(["abc"], "a.png", { type: "image/png" });
  const promise = uploadFile(file, {
    ...options,
    createRequest: () => xhr as unknown as XMLHttpRequest,
  });
  return { xhr, promise };
}

describe("uploadFile", () => {
  it("posts multipart to the proxy, reports progress and resolves the file", async () => {
    const onProgress = vi.fn();
    const { xhr, promise } = start({ conversationId: "c1", onProgress });
    expect(xhr.opened).toEqual(["POST", "/api/sparky/files"]);
    expect(xhr.sent?.get("conversationId")).toBe("c1");
    expect((xhr.sent?.get("file") as File).name).toBe("a.png");
    xhr.upload.onprogress?.({ lengthComputable: true, loaded: 1, total: 4 });
    xhr.respond(201, { file: FILE });
    await expect(promise).resolves.toMatchObject({ id: FILE.id, kind: "image" });
    expect(onProgress.mock.calls.map(([ratio]) => ratio)).toEqual([0.25, 1]);
  });

  it("rejects with the server message", async () => {
    const { xhr, promise } = start();
    xhr.respond(413, { error: { code: "payload_too_large", message: "File is too large." } });
    await expect(promise).rejects.toMatchObject({ message: "File is too large.", status: 413 });
  });

  it("rejects an unexpected success body", async () => {
    const { xhr, promise } = start();
    xhr.respond(201, { nope: true });
    await expect(promise).rejects.toBeInstanceOf(FilesApiError);
  });

  it("aborts through the signal", async () => {
    const controller = new AbortController();
    const { promise } = start({ signal: controller.signal });
    controller.abort();
    await expect(promise).rejects.toMatchObject({ name: "AbortError" });
  });

  it("fails on network errors", async () => {
    const { xhr, promise } = start();
    xhr.onerror?.();
    await expect(promise).rejects.toMatchObject({ status: 0 });
  });
});

describe("file reads", () => {
  it("reads insight and requests a reading", async () => {
    const payload = {
      id: FILE.id,
      kind: "image",
      status: "ready",
      chars: 0,
      hasText: false,
      insight: null,
      video: null,
    };
    const fetcher = vi.fn().mockImplementation(async () => json(payload));
    await expect(getInsight(FILE.id, fetcher)).resolves.toMatchObject({ kind: "image" });
    expect(fetcher).toHaveBeenLastCalledWith(`/api/sparky/files/${FILE.id}/insight`, undefined);
    await readWithSparky(FILE.id, fetcher);
    expect(fetcher.mock.lastCall?.[1]).toMatchObject({ method: "POST" });
  });

  it("pages extracted text", async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValue(json({ text: "hi", offset: 10, truncated: true, chars: 99 }));
    await expect(getText(FILE.id, 10, 5, fetcher)).resolves.toMatchObject({ truncated: true });
    expect(fetcher.mock.lastCall?.[0]).toBe(`/api/sparky/files/${FILE.id}/text?offset=10&limit=5`);
  });

  it("surfaces api errors", async () => {
    const fetcher = vi.fn().mockResolvedValue(json({ error: { message: "File not found" } }, 404));
    await expect(getInsight(FILE.id, fetcher)).rejects.toMatchObject({
      message: "File not found",
      status: 404,
    });
  });
});

describe("proxiedBlobPath", () => {
  it("rewrites signed backend links onto the same-origin proxy", () => {
    expect(proxiedBlobPath(FILE.url)).toBe(
      `/api/sparky/files/blob/${FILE.id}/original?exp=1&sig=ab`,
    );
    expect(proxiedBlobPath("https://x.test/other")).toBeNull();
  });
});
