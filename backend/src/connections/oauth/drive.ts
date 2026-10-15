import { AppError } from "../../util/errors.js";
import { extractText, MAX_TEXT_CHARS } from "../../files/extract.js";
import { connectorTokens, providerFetch, type TokenManager } from "./tokens.js";

/**
 * Google Drive with the drive.file scope: sparky sees only the files the user
 * picked (Google Picker) or that sparky created (Save to Drive). Reads turn a
 * file into text: Docs → Markdown, Sheets → CSV, Slides → text, PDFs and
 * Office files → the upload pipeline's extractor, plain text as is; anything
 * else is described by its metadata.
 */

export const DRIVE_API = "https://www.googleapis.com/drive/v3";
export const DRIVE_UPLOAD = "https://www.googleapis.com/upload/drive/v3/files";
const FIELDS = "id,name,mimeType,modifiedTime,size,iconLink,webViewLink,thumbnailLink,owners(displayName)";
/** Bigger binaries are described, not downloaded. */
export const MAX_DOWNLOAD_BYTES = 15 * 1024 * 1024;
/** Text handed back to the app / chat per file. */
export const MAX_READ_CHARS = 120_000;

export const GDOC = "application/vnd.google-apps.document";
export const GSHEET = "application/vnd.google-apps.spreadsheet";
export const GSLIDES = "application/vnd.google-apps.presentation";
export const GFOLDER = "application/vnd.google-apps.folder";

export type DriveFile = {
  id: string;
  name: string;
  mimeType: string;
  modifiedTime: string | null;
  size: number | null;
  iconLink: string | null;
  webViewLink: string | null;
  thumbnailLink: string | null;
  owner: string | null;
  /** What reading it gives: markdown | csv | text | pdf | office | none. */
  kind: ReadKind;
};

export type DriveContent = { file: DriveFile; format: "markdown" | "csv" | "text" | "metadata"; text: string; truncated: boolean };

export type ReadKind = "markdown" | "csv" | "text" | "pdf" | "office" | "none";

const OFFICE = new Set([
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/msword",
  "application/rtf",
]);
const OFFICE_EXT: Record<string, string> = {
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
  "application/msword": "doc",
  "application/rtf": "rtf",
  "application/pdf": "pdf",
};

/** How a file of [mime] is read. */
export function readKind(mime: string): ReadKind {
  if (mime === GDOC) return "markdown";
  if (mime === GSHEET) return "csv";
  if (mime === GSLIDES) return "text";
  if (mime === "application/pdf") return "pdf";
  if (OFFICE.has(mime)) return "office";
  if (mime.startsWith("text/") || mime === "application/json" || mime === "application/xml") return "text";
  return "none";
}

/** Export target of a native Google file. */
export function exportMime(mime: string): string | null {
  if (mime === GDOC) return "text/markdown";
  if (mime === GSHEET) return "text/csv";
  if (mime === GSLIDES) return "text/plain";
  return null;
}

export const PDF_MIME = "application/pdf";
/** Largest file the preview proxy streams (the app caches it on disk). */
export const MAX_PROXY_BYTES = 150 * 1024 * 1024;
/** Google-native files the preview shows as an exported PDF. */
const EXPORT_PDF = new Set([GDOC, GSHEET, GSLIDES, "application/vnd.google-apps.drawing"]);

/** What the preview proxy sends for [mime]: the exported PDF of a native Google file, or the stored bytes. */
export function previewExport(mime: string): string | null {
  return EXPORT_PDF.has(mime) ? PDF_MIME : null;
}

/** A `Range` request header Drive can take (single range); anything else is dropped. */
export function safeRange(h: string | undefined | null): string | null {
  return h && /^bytes=\d*-\d*$/.test(h) && h !== "bytes=-" ? h : null;
}

export type DriveStream = { file: DriveFile; status: number; contentType: string; headers: Record<string, string>; body: ReadableStream<Uint8Array> | null };

export function toDriveFile(j: Record<string, unknown>): DriveFile {
  const s = (v: unknown) => (typeof v === "string" && v ? v : null);
  const owners = Array.isArray(j.owners) ? (j.owners as Array<Record<string, unknown>>) : [];
  const mimeType = s(j.mimeType) ?? "application/octet-stream";
  return {
    id: String(j.id ?? ""),
    name: s(j.name) ?? "Untitled",
    mimeType,
    modifiedTime: s(j.modifiedTime),
    size: j.size != null && Number.isFinite(Number(j.size)) ? Number(j.size) : null,
    iconLink: s(j.iconLink),
    webViewLink: s(j.webViewLink),
    thumbnailLink: s(j.thumbnailLink),
    owner: s(owners[0]?.displayName),
    kind: readKind(mimeType),
  };
}

const ID_RE = /^[A-Za-z0-9_-]{10,200}$/;
export function checkFileId(id: string): string {
  if (!ID_RE.test(id)) throw new AppError(400, "bad_request", "Couldn't find that Drive file. Pick it again.");
  return id;
}

/** Escapes a value for a Drive `q` string literal. */
export const qEscape = (s: string) => s.replace(/\\/g, "\\\\").replace(/'/g, "\\'");

async function errorOf(res: Response, what: string): Promise<AppError> {
  const j = (await res.json().catch(() => ({}))) as { error?: { message?: string } };
  if (res.status === 404) return new AppError(404, "not_found", "That Drive file is gone or sparky cannot see it. Pick it again.");
  if (res.status === 403) return new AppError(403, "drive_forbidden", "Google Drive refused access to that file. Pick it again in Drive.");
  return new AppError(502, "drive_failed", `${what} didn't work on Google Drive — try again.`);
}

export function createDrive(tokens: TokenManager = connectorTokens, f: typeof fetch = fetch) {
  const call = (userId: string, url: string, init: RequestInit & { timeoutMs?: number } = {}) => providerFetch(userId, "google_drive", url, init, tokens, f);

  /** Files sparky can see (picked or created), newest first; [q] filters by name. */
  async function list(userId: string, opts: { q?: string; pageToken?: string; pageSize?: number } = {}): Promise<{ files: DriveFile[]; nextPageToken: string | null }> {
    const clauses = ["trashed = false", `mimeType != '${GFOLDER}'`];
    const q = opts.q?.trim().slice(0, 200);
    if (q) clauses.push(`(name contains '${qEscape(q)}' or fullText contains '${qEscape(q)}')`);
    const params = new URLSearchParams({
      q: clauses.join(" and "),
      fields: `nextPageToken,files(${FIELDS})`,
      pageSize: String(Math.min(Math.max(opts.pageSize ?? 50, 1), 100)),
      spaces: "drive",
      supportsAllDrives: "true",
      includeItemsFromAllDrives: "true",
    });
    // Drive rejects orderBy together with a fullText search.
    if (!q) params.set("orderBy", "modifiedTime desc");
    if (opts.pageToken) params.set("pageToken", opts.pageToken.slice(0, 500));
    const res = await call(userId, `${DRIVE_API}/files?${params}`);
    if (!res.ok) throw await errorOf(res, "Listing files");
    const j = (await res.json()) as { files?: Array<Record<string, unknown>>; nextPageToken?: string };
    return { files: (j.files ?? []).map(toDriveFile), nextPageToken: j.nextPageToken ?? null };
  }

  async function meta(userId: string, id: string): Promise<DriveFile> {
    const res = await call(userId, `${DRIVE_API}/files/${checkFileId(id)}?fields=${encodeURIComponent(FIELDS)}&supportsAllDrives=true`);
    if (!res.ok) throw await errorOf(res, "Reading the file");
    return toDriveFile((await res.json()) as Record<string, unknown>);
  }

  const describe = (file: DriveFile) =>
    [
      `# ${file.name}`,
      "",
      `- Type: ${file.mimeType}`,
      file.size != null ? `- Size: ${Math.round(file.size / 1024)} KB` : null,
      file.modifiedTime ? `- Modified: ${file.modifiedTime.slice(0, 10)}` : null,
      file.owner ? `- Owner: ${file.owner}` : null,
      file.webViewLink ? `- Link: ${file.webViewLink}` : null,
      "",
      "sparky cannot read the contents of this kind of file.",
    ]
      .filter((l) => l !== null)
      .join("\n");

  const clip = (text: string, max = MAX_READ_CHARS) => ({ text: text.length > max ? text.slice(0, max) : text, truncated: text.length > max });

  /** The file as text (see the module comment). */
  async function read(userId: string, id: string, maxChars = MAX_READ_CHARS): Promise<DriveContent> {
    const file = await meta(userId, id);
    const exp = exportMime(file.mimeType);
    if (exp) {
      let res = await call(userId, `${DRIVE_API}/files/${file.id}/export?mimeType=${encodeURIComponent(exp)}`);
      // Older Drive deployments lack the Markdown export: plain text then.
      if (!res.ok && exp === "text/markdown") res = await call(userId, `${DRIVE_API}/files/${file.id}/export?mimeType=text%2Fplain`);
      if (!res.ok) throw await errorOf(res, "Exporting the file");
      const text = await res.text();
      const format = exp === "text/csv" ? "csv" : exp === "text/markdown" ? "markdown" : "text";
      return { file, format, ...clip(text, maxChars) };
    }
    if (file.kind === "none" || (file.size != null && file.size > MAX_DOWNLOAD_BYTES)) {
      return { file, format: "metadata", text: describe(file), truncated: false };
    }
    const res = await call(userId, `${DRIVE_API}/files/${file.id}?alt=media&supportsAllDrives=true`, { headers: {} });
    if (!res.ok) throw await errorOf(res, "Downloading the file");
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.length > MAX_DOWNLOAD_BYTES) return { file, format: "metadata", text: describe(file), truncated: false };
    if (file.kind === "text") return { file, format: "text", ...clip(buf.toString("utf8"), maxChars) };
    const ext = OFFICE_EXT[file.mimeType] ?? "bin";
    const name = /\.[a-z0-9]{2,5}$/i.test(file.name) ? file.name : `${file.name}.${ext}`;
    try {
      const out = await extractText(buf, name);
      return { file, format: "text", ...clip(out.text.slice(0, MAX_TEXT_CHARS), maxChars) };
    } catch {
      return { file, format: "metadata", text: describe(file), truncated: false };
    }
  }

  /**
   * The file's bytes for the app's preview (the user's token never leaves the server): native Google
   * files as an exported PDF, everything else as stored, with a single `Range` passed through.
   */
  async function stream(userId: string, id: string, range?: string | null): Promise<DriveStream> {
    const file = await meta(userId, id);
    if (file.mimeType === GFOLDER) throw new AppError(422, "unprocessable", "A folder has nothing to preview.");
    const exp = previewExport(file.mimeType);
    if (!exp && file.size != null && file.size > MAX_PROXY_BYTES) throw new AppError(413, "too_large", "This file is too big to preview here. Open it in Drive.");
    const url = exp ? `${DRIVE_API}/files/${file.id}/export?mimeType=${encodeURIComponent(exp)}` : `${DRIVE_API}/files/${file.id}?alt=media&supportsAllDrives=true`;
    const r = safeRange(range);
    const res = await call(userId, url, { headers: r && !exp ? { Range: r } : {}, timeoutMs: 120_000 });
    if (res.status === 403 && exp) throw new AppError(413, "too_large", "Google can't turn this one into a PDF preview (too big). Open it in Drive.");
    if (!res.ok && res.status !== 206) throw await errorOf(res, "Opening the file");
    const headers: Record<string, string> = {};
    for (const k of ["content-length", "content-range", "accept-ranges"]) {
      const v = res.headers.get(k);
      if (v) headers[k] = v;
    }
    if (exp) delete headers["content-range"];
    if (!exp) headers["accept-ranges"] ??= "bytes";
    return { file, status: res.status === 206 ? 206 : 200, contentType: exp ?? file.mimeType, headers, body: res.body };
  }

  /**
   * The files directly inside a folder that the token can see. Under drive.file this is usually empty or
   * denied for a folder the user picked; the caller treats both as "ask for the files inside".
   */
  async function children(userId: string, folderId: string, max = 100): Promise<{ ok: boolean; status: number; files: DriveFile[] }> {
    const params = new URLSearchParams({
      q: `'${qEscape(checkFileId(folderId))}' in parents and trashed = false`,
      fields: `files(${FIELDS})`,
      pageSize: String(Math.min(Math.max(max, 1), 100)),
      supportsAllDrives: "true",
      includeItemsFromAllDrives: "true",
    });
    const res = await call(userId, `${DRIVE_API}/files?${params}`);
    if (!res.ok) return { ok: false, status: res.status, files: [] };
    const j = (await res.json().catch(() => ({}))) as { files?: Array<Record<string, unknown>> };
    return { ok: true, status: res.status, files: (j.files ?? []).map(toDriveFile) };
  }

  /**
   * Creates a file in the user's Drive. [convert] turns it into a native Google
   * Doc (docx/markdown/html sources). Returns the new file.
   */
  async function upload(
    userId: string,
    input: { name: string; mimeType: string; data: Buffer; convert?: boolean },
  ): Promise<DriveFile> {
    const boundary = `sparky${Math.random().toString(36).slice(2)}`;
    const metadata = { name: input.name.slice(0, 250), ...(input.convert ? { mimeType: GDOC } : {}) };
    const body = Buffer.concat([
      Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n`),
      Buffer.from(`--${boundary}\r\nContent-Type: ${input.mimeType}\r\n\r\n`),
      input.data,
      Buffer.from(`\r\n--${boundary}--`),
    ]);
    const res = await call(userId, `${DRIVE_UPLOAD}?uploadType=multipart&supportsAllDrives=true&fields=${encodeURIComponent(FIELDS)}`, {
      method: "POST",
      headers: { "Content-Type": `multipart/related; boundary=${boundary}` },
      body,
    });
    if (!res.ok) throw await errorOf(res, "Saving to Drive");
    return toDriveFile((await res.json()) as Record<string, unknown>);
  }

  return { list, meta, read, stream, children, upload };
}

export const drive = createDrive();
