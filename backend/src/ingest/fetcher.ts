import dns from "node:dns";
import http from "node:http";
import https from "node:https";
import net from "node:net";
import zlib from "node:zlib";
import { AppError } from "../util/errors.js";

export const USER_AGENT = "AgentWorkerBot/1.0";
const MAX_REDIRECTS = 5;
const TIMEOUT_MS = 10_000;
const MAX_BYTES = 5 * 1024 * 1024;

export class FetchError extends Error {
  constructor(
    message: string,
    public status = 0,
    public headers: Record<string, string> = {},
  ) {
    super(message);
  }
}

function ipv4Private(ip: string): boolean {
  const p = ip.split(".").map(Number);
  const [a, b] = p;
  return (
    a === 0 || a === 10 || a === 127 || a >= 224 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 192 && b === 0 && p[2] === 0) ||
    (a === 198 && (b === 18 || b === 19))
  );
}

export function isPrivateIp(ip: string): boolean {
  const v = net.isIP(ip);
  if (v === 4) return ipv4Private(ip);
  if (v === 6) {
    const l = ip.toLowerCase();
    if (l === "::" || l === "::1") return true;
    const mapped = l.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return ipv4Private(mapped[1]);
    const mappedHex = l.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
    if (mappedHex) {
      const n = (parseInt(mappedHex[1], 16) << 16) | parseInt(mappedHex[2], 16);
      return ipv4Private([(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255].join("."));
    }
    return /^(fc|fd|fe[89ab])/.test(l) || l.startsWith("ff");
  }
  return true;
}

/** DNS lookup that refuses private/loopback/link-local addresses. Re-run on every connection, so redirects and rebinding are covered. */
const guardedLookup: net.LookupFunction = (hostname, options, cb) => {
  dns.lookup(hostname, { ...(options as object), all: true }, (err, addrs) => {
    if (err) return (cb as any)(err);
    const list = (addrs as unknown as dns.LookupAddress[]).filter((a) => !isPrivateIp(a.address));
    if (list.length === 0) return (cb as any)(new FetchError("Blocked: host resolves to a private network address"));
    if ((options as any)?.all) return (cb as any)(null, list);
    return (cb as any)(null, list[0].address, list[0].family);
  });
};

/** Validate a user-supplied URL before queueing: protocol and literal/DNS private-network check. */
export async function assertPublicUrl(raw: string): Promise<URL> {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new AppError(400, "bad_request", "Invalid URL");
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") throw new AppError(400, "bad_request", "Only http and https URLs are allowed");
  const host = u.hostname.replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local") || host.endsWith(".internal")) {
    throw new AppError(400, "bad_request", "Private network URLs are not allowed");
  }
  if (net.isIP(host)) {
    if (isPrivateIp(host)) throw new AppError(400, "bad_request", "Private network URLs are not allowed");
    return u;
  }
  try {
    const addrs = await dns.promises.lookup(host, { all: true });
    if (addrs.length === 0 || addrs.some((a) => isPrivateIp(a.address))) {
      throw new AppError(400, "bad_request", "Private network URLs are not allowed");
    }
  } catch (e) {
    if (e instanceof AppError) throw e;
    throw new AppError(400, "bad_request", "Host could not be resolved");
  }
  return u;
}

const TYPE_OK = /^(text\/|application\/(json|xml|xhtml\+xml|x-yaml|yaml|toml|javascript|x-httpd-php)|application\/[\w.+-]*\+(json|xml))/i;

const hostNext = new Map<string, number>();
async function politeWait(host: string, delayMs: number) {
  if (delayMs <= 0) return;
  const now = Date.now();
  const at = Math.max(now, hostNext.get(host) ?? 0);
  hostNext.set(host, at + delayMs);
  if (at > now) await new Promise((r) => setTimeout(r, at - now));
}

export type FetchOpts = {
  headers?: Record<string, string>;
  /** minimum gap between requests to the same host (ms). Default 1000. */
  delayMs?: number;
  maxBytes?: number;
  /** skip content-type allowlist (API responses) */
  anyType?: boolean;
  /** do not throw on these statuses */
  okStatuses?: number[];
};
export type FetchResult = { status: number; url: string; contentType: string; body: string; headers: Record<string, string> };

function once(url: URL, opts: FetchOpts): Promise<{ status: number; headers: http.IncomingHttpHeaders; body: Buffer }> {
  return new Promise((resolve, reject) => {
    const mod = url.protocol === "https:" ? https : http;
    const maxBytes = opts.maxBytes ?? MAX_BYTES;
    const req = mod.request(
      url,
      {
        method: "GET",
        lookup: guardedLookup,
        timeout: TIMEOUT_MS,
        headers: { "User-Agent": USER_AGENT, Accept: "*/*", "Accept-Encoding": "gzip, deflate, br", ...opts.headers },
      },
      (res) => {
        const status = res.statusCode ?? 0;
        const ct = String(res.headers["content-type"] ?? "");
        if (status < 300 && !opts.anyType && ct && !TYPE_OK.test(ct)) {
          res.destroy();
          return reject(new FetchError(`Unsupported content type: ${ct.slice(0, 60)}`, status));
        }
        const enc = String(res.headers["content-encoding"] ?? "").toLowerCase();
        let stream: NodeJS.ReadableStream = res;
        if (enc === "gzip") stream = res.pipe(zlib.createGunzip());
        else if (enc === "deflate") stream = res.pipe(zlib.createInflate());
        else if (enc === "br") stream = res.pipe(zlib.createBrotliDecompress());
        const chunks: Buffer[] = [];
        let size = 0;
        const deadline = setTimeout(() => req.destroy(new FetchError("Download timed out")), TIMEOUT_MS * 3);
        stream.on("data", (c: Buffer) => {
          size += c.length;
          if (size > maxBytes) {
            req.destroy(new FetchError("Response too large"));
            return;
          }
          chunks.push(c);
        });
        stream.on("end", () => {
          clearTimeout(deadline);
          resolve({ status, headers: res.headers, body: Buffer.concat(chunks) });
        });
        stream.on("error", (e) => {
          clearTimeout(deadline);
          reject(e);
        });
      },
    );
    req.on("timeout", () => req.destroy(new FetchError("Request timed out")));
    req.on("error", (e) => reject(e instanceof FetchError ? e : new FetchError(e.message || "Network error")));
    req.end();
  });
}

export async function fetchText(rawUrl: string, opts: FetchOpts = {}): Promise<FetchResult> {
  let url = new URL(rawUrl);
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    if (url.protocol !== "http:" && url.protocol !== "https:") throw new FetchError("Only http and https URLs are allowed");
    const host = url.hostname.replace(/^\[|\]$/g, "");
    if (net.isIP(host) && isPrivateIp(host)) throw new FetchError("Blocked: private network address");
    await politeWait(url.host, opts.delayMs ?? 1000);
    const r = await once(url, opts);
    if (r.status >= 300 && r.status < 400 && r.headers.location) {
      url = new URL(String(r.headers.location), url);
      continue;
    }
    const headers: Record<string, string> = {};
    for (const [k, v] of Object.entries(r.headers)) headers[k] = Array.isArray(v) ? v.join(", ") : String(v ?? "");
    if (r.status >= 400 && !opts.okStatuses?.includes(r.status)) {
      throw new FetchError(`HTTP ${r.status} from ${url.hostname}`, r.status, headers);
    }
    return { status: r.status, url: url.toString(), contentType: headers["content-type"] ?? "", body: r.body.toString("utf8"), headers };
  }
  throw new FetchError("Too many redirects");
}

export async function fetchJson<T = any>(url: string, opts: FetchOpts = {}): Promise<{ data: T; headers: Record<string, string>; status: number }> {
  const r = await fetchText(url, { delayMs: 0, anyType: true, ...opts, headers: { Accept: "application/json", ...opts.headers } });
  try {
    return { data: JSON.parse(r.body) as T, headers: r.headers, status: r.status };
  } catch {
    throw new FetchError(`Invalid JSON from ${new URL(url).hostname}`, r.status, r.headers);
  }
}
