import { randomUUID } from "node:crypto";
import { AppError } from "../util/errors.js";

/**
 * GitHub OAuth device flow (no callback URL needed):
 *  1. start(): POST /login/device/code -> user_code + verification_uri.
 *  2. The user enters the code on github.com.
 *  3. poll(): the app polls this server; this server asks GitHub for the token
 *     at most once per `interval` seconds (whatever the client's pace), and
 *     honours slow_down (interval grows), expired_token and access_denied.
 *  4. On success the token is encrypted and saved through `deps.save`.
 * Flows live in memory: a restart only means the user taps CONNECT again.
 */

export const DEVICE_CODE_URL = "https://github.com/login/device/code";
export const ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token";
export const GITHUB_USER_URL = "https://api.github.com/user";
export const GITHUB_SCOPES = "repo read:user read:org";
const GRANT = "urn:ietf:params:oauth:grant-type:device_code";
const TIMEOUT_MS = 12_000;
/** Finished flows stay readable this long so a late poll still sees the result. */
const KEEP_MS = 10 * 60_000;

export type FlowStatus = "pending" | "connected" | "expired" | "denied" | "error";

export type GithubAccount = { login: string; id: string; avatarUrl: string | null; scopes: string[] };

/** What gets persisted: tokens are already encrypted. */
export type ConnectionRow = GithubAccount & {
  userId: string;
  accessTokenEnc: string;
  refreshTokenEnc: string | null;
  expiresAt: Date | null;
};

export type DeviceFlowDeps = {
  clientId: () => string | undefined;
  fetch: typeof fetch;
  now: () => number;
  encrypt: (plain: string) => string;
  save: (row: ConnectionRow) => Promise<void>;
};

type Flow = {
  id: string;
  userId: string;
  deviceCode: string;
  userCode: string;
  verificationUri: string;
  verificationUriComplete: string | null;
  intervalS: number;
  expiresAt: number;
  nextPollAt: number;
  status: FlowStatus;
  error: string | null;
  account: GithubAccount | null;
  finishedAt: number | null;
  inflight: Promise<void> | null;
};

export type StartResult = {
  flowId: string;
  userCode: string;
  verificationUri: string;
  verificationUriComplete: string | null;
  expiresIn: number;
  interval: number;
};

export type PollResult = {
  status: FlowStatus;
  /** Seconds the client should wait before polling again. */
  interval: number;
  expiresIn: number;
  account: GithubAccount | null;
  error: string | null;
};

export const notConfigured = () =>
  new AppError(503, "github_oauth_not_configured", "GitHub sign-in is not set up on this server (GITHUB_OAUTH_CLIENT_ID)");

export class DeviceFlows {
  private flows = new Map<string, Flow>();

  constructor(private deps: DeviceFlowDeps) {}

  private async post(url: string, body: Record<string, string>): Promise<{ status: number; json: any }> {
    const res = await this.deps.fetch(url, {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "AgentWorker" },
      body: new URLSearchParams(body).toString(),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    let json: any = null;
    try {
      json = await res.json();
    } catch {
      /* not JSON */
    }
    return { status: res.status, json };
  }

  private purge() {
    const now = this.deps.now();
    for (const [id, f] of this.flows) {
      const end = f.finishedAt ?? f.expiresAt;
      if (now - end > KEEP_MS) this.flows.delete(id);
    }
  }

  async start(userId: string): Promise<StartResult> {
    const clientId = this.deps.clientId();
    if (!clientId) throw notConfigured();
    this.purge();
    // One live flow per user: a new CONNECT replaces the previous attempt.
    for (const [id, f] of this.flows) if (f.userId === userId && f.status === "pending") this.flows.delete(id);

    let r: { status: number; json: any };
    try {
      r = await this.post(DEVICE_CODE_URL, { client_id: clientId, scope: GITHUB_SCOPES });
    } catch {
      throw new AppError(504, "upstream_timeout", "GitHub did not answer in time", true);
    }
    const j = r.json ?? {};
    if (r.status >= 400 || j.error || !j.device_code || !j.user_code) {
      const code = String(j.error ?? r.status);
      if (code === "device_flow_disabled") {
        throw new AppError(503, "github_oauth_not_configured", "Device flow is disabled for this GitHub OAuth app (enable it in the app settings)");
      }
      if (code === "incorrect_client_credentials" || r.status === 404 || r.status === 401) {
        throw new AppError(503, "github_oauth_not_configured", "GitHub did not accept GITHUB_OAUTH_CLIENT_ID");
      }
      throw new AppError(502, "upstream_failed", `GitHub could not start sign-in (${code})`.slice(0, 160), true);
    }
    const now = this.deps.now();
    const expiresIn = Number(j.expires_in) > 0 ? Number(j.expires_in) : 900;
    const intervalS = Number(j.interval) > 0 ? Number(j.interval) : 5;
    const flow: Flow = {
      id: randomUUID(),
      userId,
      deviceCode: String(j.device_code),
      userCode: String(j.user_code),
      verificationUri: String(j.verification_uri ?? "https://github.com/login/device"),
      verificationUriComplete: j.verification_uri_complete ? String(j.verification_uri_complete) : null,
      intervalS,
      expiresAt: now + expiresIn * 1000,
      nextPollAt: now + intervalS * 1000,
      status: "pending",
      error: null,
      account: null,
      finishedAt: null,
      inflight: null,
    };
    this.flows.set(flow.id, flow);
    return {
      flowId: flow.id,
      userCode: flow.userCode,
      verificationUri: flow.verificationUri,
      verificationUriComplete: flow.verificationUriComplete,
      expiresIn,
      interval: intervalS,
    };
  }

  /** Status of [flowId]; asks GitHub only when the interval has passed. */
  async poll(userId: string, flowId: string): Promise<PollResult> {
    const flow = this.flows.get(flowId);
    if (!flow || flow.userId !== userId) throw new AppError(404, "not_found", "Sign-in attempt not found; start again");
    if (flow.status === "pending") {
      if (this.deps.now() >= flow.expiresAt) this.finish(flow, "expired");
      else if (flow.inflight) await flow.inflight;
      else if (this.deps.now() >= flow.nextPollAt) {
        flow.inflight = this.exchange(flow).finally(() => {
          flow.inflight = null;
        });
        await flow.inflight;
      }
    }
    return this.view(flow);
  }

  /** For tests and diagnostics. */
  peek(flowId: string): Readonly<Omit<Flow, "inflight">> | null {
    return this.flows.get(flowId) ?? null;
  }

  private view(f: Flow): PollResult {
    const now = this.deps.now();
    return {
      status: f.status,
      interval: f.intervalS,
      expiresIn: Math.max(0, Math.round((f.expiresAt - now) / 1000)),
      account: f.account,
      error: f.error,
    };
  }

  private finish(f: Flow, status: FlowStatus, error: string | null = null) {
    f.status = status;
    f.error = error;
    f.finishedAt = this.deps.now();
  }

  private async exchange(f: Flow): Promise<void> {
    const clientId = this.deps.clientId();
    if (!clientId) return this.finish(f, "error", "GitHub sign-in is no longer configured");
    let r: { status: number; json: any };
    try {
      r = await this.post(ACCESS_TOKEN_URL, { client_id: clientId, device_code: f.deviceCode, grant_type: GRANT });
    } catch {
      // Network hiccup: try again after the interval.
      f.nextPollAt = this.deps.now() + f.intervalS * 1000;
      return;
    }
    const j = r.json ?? {};
    if (j.access_token) {
      try {
        f.account = await this.store(f.userId, j);
        this.finish(f, "connected");
      } catch (e) {
        this.finish(f, "error", (e as Error).message.slice(0, 160) || "Could not save the connection");
      }
      return;
    }
    switch (j.error) {
      case "authorization_pending":
        f.nextPollAt = this.deps.now() + f.intervalS * 1000;
        return;
      case "slow_down": {
        // GitHub sends the new minimum interval; otherwise add 5 seconds.
        const next = Number(j.interval);
        f.intervalS = next > f.intervalS ? next : f.intervalS + 5;
        f.nextPollAt = this.deps.now() + f.intervalS * 1000;
        return;
      }
      case "expired_token":
        return this.finish(f, "expired");
      case "access_denied":
        return this.finish(f, "denied");
      default:
        if (r.status >= 500) {
          f.nextPollAt = this.deps.now() + f.intervalS * 1000;
          return;
        }
        return this.finish(f, "error", String(j.error_description ?? j.error ?? `GitHub error ${r.status}`).slice(0, 160));
    }
  }

  /** Reads the account behind [tok] and persists the encrypted token. */
  private async store(userId: string, tok: any): Promise<GithubAccount> {
    const accessToken = String(tok.access_token);
    const res = await this.deps.fetch(GITHUB_USER_URL, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/vnd.github+json",
        "User-Agent": "AgentWorker",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`GitHub rejected the new token (${res.status})`);
    const u = (await res.json()) as any;
    if (!u?.login) throw new Error("GitHub returned no account");
    const header = res.headers.get("x-oauth-scopes");
    const scopeText = typeof tok.scope === "string" && tok.scope ? tok.scope : (header ?? "");
    const account: GithubAccount = {
      login: String(u.login),
      id: String(u.id ?? ""),
      avatarUrl: u.avatar_url ? String(u.avatar_url) : null,
      scopes: scopeText.split(/[,\s]+/).map((s: string) => s.trim()).filter(Boolean),
    };
    const expiresIn = Number(tok.expires_in);
    await this.deps.save({
      ...account,
      userId,
      accessTokenEnc: this.deps.encrypt(accessToken),
      refreshTokenEnc: tok.refresh_token ? this.deps.encrypt(String(tok.refresh_token)) : null,
      expiresAt: expiresIn > 0 ? new Date(this.deps.now() + expiresIn * 1000) : null,
    });
    return account;
  }
}
