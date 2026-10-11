import { randomUUID } from "node:crypto";
import { AppError } from "../util/errors.js";

/**
 * GitHub OAuth device flow (no callback URL needed):
 *  1. start(): POST /login/device/code -> user_code + verification_uri.
 *  2. The user enters the code on github.com.
 *  3. poll(): the app polls this server; this server asks GitHub for the token
 *     at most once per `interval` seconds (whatever the client's pace), and
 *     honours slow_down (interval grows), expired_token and access_denied.
 *  4. On success the grant goes to `complete`, whose result the poll returns.
 * Flows live in memory: a restart only means the user starts again.
 *
 * `GithubDeviceFlow` is the shared machinery; `DeviceFlows` (below) is the
 * "Connect GitHub" use (token saved as the user's connection) and
 * src/auth/githubSso.ts the "Continue with GitHub" sign-in.
 */

export const DEVICE_CODE_URL = "https://github.com/login/device/code";
export const ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token";
export const GITHUB_USER_URL = "https://api.github.com/user";
export const GITHUB_EMAILS_URL = "https://api.github.com/user/emails";
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

/** The token GitHub granted (still plain; never leaves the server). */
export type DeviceGrant = { accessToken: string; refreshToken: string | null; expiresIn: number; scope: string };

/** Who a flow belongs to: a user id, or null for a signed-out sign-in. */
export type FlowOwner = string | null;

export type CoreStatus = "pending" | "slow_down" | "done" | "expired" | "denied" | "error";

export type GithubDeviceFlowOptions<R, M> = {
  clientId: () => string | undefined;
  fetch: typeof fetch;
  now: () => number;
  scope: string;
  /** Turns the grant into the flow's result. An AppError's status/code/message reach the poller. */
  complete: (grant: DeviceGrant, flow: { owner: FlowOwner; meta: M }) => Promise<R>;
  /** Hand the result out once, then forget the flow (it carries a session). */
  once?: boolean;
};

type Flow<R, M> = {
  id: string;
  owner: FlowOwner;
  meta: M;
  deviceCode: string;
  userCode: string;
  verificationUri: string;
  verificationUriComplete: string | null;
  intervalS: number;
  expiresAt: number;
  nextPollAt: number;
  status: CoreStatus;
  /** GitHub said slow_down on the last exchange (reported once). */
  slowed: boolean;
  error: string | null;
  errorCode: string | null;
  errorStatus: number | null;
  result: R | null;
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

export type CorePoll<R> = {
  status: CoreStatus;
  /** Seconds the client should wait before polling again. */
  interval: number;
  expiresIn: number;
  result: R | null;
  error: string | null;
  /** Machine code of an error raised by `complete` (e.g. email_in_use_link_from_profile). */
  errorCode: string | null;
  errorStatus: number | null;
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

const ghHeaders = (token: string) => ({
  Authorization: `Bearer ${token}`,
  Accept: "application/vnd.github+json",
  "User-Agent": "AgentWorker",
  "X-GitHub-Api-Version": "2022-11-28",
});

export type GithubUser = GithubAccount & { name: string | null; publicEmail: string | null };

/** The account behind [token] (GET /user); scopes from the grant, else the header. */
export async function fetchGithubUser(f: typeof fetch, token: string, grantScope = ""): Promise<GithubUser> {
  const res = await f(GITHUB_USER_URL, { headers: ghHeaders(token), signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!res.ok) throw new Error(`GitHub rejected the new token (${res.status})`);
  const u = (await res.json()) as any;
  if (!u?.login) throw new Error("GitHub returned no account");
  const header = res.headers.get("x-oauth-scopes");
  const scopeText = grantScope || (header ?? "");
  return {
    login: String(u.login),
    id: String(u.id ?? ""),
    avatarUrl: u.avatar_url ? String(u.avatar_url) : null,
    scopes: scopeText.split(/[,\s]+/).map((s: string) => s.trim()).filter(Boolean),
    name: typeof u.name === "string" && u.name.trim() ? u.name.trim() : null,
    publicEmail: typeof u.email === "string" && u.email.includes("@") ? u.email : null,
  };
}

export type GithubEmail = { email: string; primary: boolean; verified: boolean };

/** GET /user/emails (needs user:email); empty when GitHub refuses. */
export async function fetchGithubEmails(f: typeof fetch, token: string): Promise<GithubEmail[]> {
  try {
    const res = await f(GITHUB_EMAILS_URL, { headers: ghHeaders(token), signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!res.ok) return [];
    const list = (await res.json()) as unknown;
    if (!Array.isArray(list)) return [];
    return list
      .filter((e) => typeof e?.email === "string" && e.email.includes("@"))
      .map((e) => ({ email: String(e.email), primary: e.primary === true, verified: e.verified === true }));
  } catch {
    return [];
  }
}

/**
 * The email to sign in with: the primary one when verified, else any verified
 * one, else the primary (or public) one marked unverified.
 */
export function pickGithubEmail(emails: GithubEmail[], publicEmail: string | null): { email: string; verified: boolean } | null {
  const usable = emails.filter((e) => !/@users\.noreply\.github\.com$/i.test(e.email));
  const primary = usable.find((e) => e.primary);
  if (primary?.verified) return { email: primary.email, verified: true };
  const verified = usable.find((e) => e.verified);
  if (verified) return { email: verified.email, verified: true };
  if (primary) return { email: primary.email, verified: false };
  return publicEmail ? { email: publicEmail, verified: false } : null;
}

/** The device-flow state machine, shared by "Connect GitHub" and "Continue with GitHub". */
export class GithubDeviceFlow<R, M = undefined> {
  private flows = new Map<string, Flow<R, M>>();

  constructor(private opts: GithubDeviceFlowOptions<R, M>) {}

  private async post(url: string, body: Record<string, string>): Promise<{ status: number; json: any }> {
    const res = await this.opts.fetch(url, {
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
    const now = this.opts.now();
    for (const [id, f] of this.flows) {
      const end = f.finishedAt ?? f.expiresAt;
      if (now - end > KEEP_MS) this.flows.delete(id);
    }
  }

  async start(owner: FlowOwner, meta: M): Promise<StartResult> {
    const clientId = this.opts.clientId();
    if (!clientId) throw notConfigured();
    this.purge();
    // One live flow per user: a new CONNECT replaces the previous attempt.
    if (owner !== null) for (const [id, f] of this.flows) if (f.owner === owner && f.status === "pending") this.flows.delete(id);

    let r: { status: number; json: any };
    try {
      r = await this.post(DEVICE_CODE_URL, { client_id: clientId, scope: this.opts.scope });
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
    const now = this.opts.now();
    const expiresIn = Number(j.expires_in) > 0 ? Number(j.expires_in) : 900;
    const intervalS = Number(j.interval) > 0 ? Number(j.interval) : 5;
    const flow: Flow<R, M> = {
      id: randomUUID(),
      owner,
      meta,
      deviceCode: String(j.device_code),
      userCode: String(j.user_code),
      verificationUri: String(j.verification_uri ?? "https://github.com/login/device"),
      verificationUriComplete: j.verification_uri_complete ? String(j.verification_uri_complete) : null,
      intervalS,
      expiresAt: now + expiresIn * 1000,
      nextPollAt: now + intervalS * 1000,
      status: "pending",
      slowed: false,
      error: null,
      errorCode: null,
      errorStatus: null,
      result: null,
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
  async poll(owner: FlowOwner, flowId: string): Promise<CorePoll<R>> {
    const flow = this.flows.get(flowId);
    if (!flow || flow.owner !== owner) throw new AppError(404, "not_found", "Sign-in attempt not found; start again");
    if (flow.status === "pending") {
      if (this.opts.now() >= flow.expiresAt) this.finish(flow, "expired");
      else if (flow.inflight) await flow.inflight;
      else if (this.opts.now() >= flow.nextPollAt) {
        flow.inflight = this.exchange(flow).finally(() => {
          flow.inflight = null;
        });
        await flow.inflight;
      }
    }
    const view = this.view(flow);
    flow.slowed = false;
    if (this.opts.once && view.status === "done") this.flows.delete(flow.id);
    return view;
  }

  /** For tests and diagnostics. */
  peek(flowId: string): Readonly<Omit<Flow<R, M>, "inflight">> | null {
    return this.flows.get(flowId) ?? null;
  }

  private view(f: Flow<R, M>): CorePoll<R> {
    const now = this.opts.now();
    return {
      status: f.status === "pending" && f.slowed ? "slow_down" : f.status,
      interval: f.intervalS,
      expiresIn: Math.max(0, Math.round((f.expiresAt - now) / 1000)),
      result: f.result,
      error: f.error,
      errorCode: f.errorCode,
      errorStatus: f.errorStatus,
    };
  }

  private finish(f: Flow<R, M>, status: CoreStatus, error: string | null = null, code: string | null = null, httpStatus: number | null = null) {
    f.status = status;
    f.error = error;
    f.errorCode = code;
    f.errorStatus = httpStatus;
    f.finishedAt = this.opts.now();
  }

  private async exchange(f: Flow<R, M>): Promise<void> {
    const clientId = this.opts.clientId();
    if (!clientId) return this.finish(f, "error", "GitHub sign-in is no longer configured");
    let r: { status: number; json: any };
    try {
      r = await this.post(ACCESS_TOKEN_URL, { client_id: clientId, device_code: f.deviceCode, grant_type: GRANT });
    } catch {
      // Network hiccup: try again after the interval.
      f.nextPollAt = this.opts.now() + f.intervalS * 1000;
      return;
    }
    const j = r.json ?? {};
    if (j.access_token) {
      const grant: DeviceGrant = {
        accessToken: String(j.access_token),
        refreshToken: j.refresh_token ? String(j.refresh_token) : null,
        expiresIn: Number(j.expires_in) > 0 ? Number(j.expires_in) : 0,
        scope: typeof j.scope === "string" ? j.scope : "",
      };
      try {
        f.result = await this.opts.complete(grant, { owner: f.owner, meta: f.meta });
        this.finish(f, "done");
      } catch (e) {
        if (e instanceof AppError) this.finish(f, "error", e.message.slice(0, 200), e.code, e.status);
        else this.finish(f, "error", (e as Error).message.slice(0, 160) || "Could not finish sign-in");
      }
      return;
    }
    switch (j.error) {
      case "authorization_pending":
        f.nextPollAt = this.opts.now() + f.intervalS * 1000;
        return;
      case "slow_down": {
        // GitHub sends the new minimum interval; otherwise add 5 seconds.
        const next = Number(j.interval);
        f.intervalS = next > f.intervalS ? next : f.intervalS + 5;
        f.nextPollAt = this.opts.now() + f.intervalS * 1000;
        f.slowed = true;
        return;
      }
      case "expired_token":
        return this.finish(f, "expired");
      case "access_denied":
        return this.finish(f, "denied");
      default:
        if (r.status >= 500) {
          f.nextPollAt = this.opts.now() + f.intervalS * 1000;
          return;
        }
        return this.finish(f, "error", String(j.error_description ?? j.error ?? `GitHub error ${r.status}`).slice(0, 160));
    }
  }
}

/** "Connect GitHub": the grant is saved (encrypted) as the user's connection. */
export class DeviceFlows {
  private core: GithubDeviceFlow<GithubAccount>;

  constructor(private deps: DeviceFlowDeps) {
    this.core = new GithubDeviceFlow<GithubAccount>({
      clientId: deps.clientId,
      fetch: deps.fetch,
      now: deps.now,
      scope: GITHUB_SCOPES,
      complete: (grant, flow) => this.store(flow.owner!, grant),
    });
  }

  start(userId: string): Promise<StartResult> {
    return this.core.start(userId, undefined);
  }

  /** Status of [flowId]; asks GitHub only when the interval has passed. */
  async poll(userId: string, flowId: string): Promise<PollResult> {
    const r = await this.core.poll(userId, flowId);
    const status: FlowStatus = r.status === "done" ? "connected" : r.status === "slow_down" ? "pending" : r.status;
    return { status, interval: r.interval, expiresIn: r.expiresIn, account: r.result, error: r.error };
  }

  /** For tests and diagnostics. */
  peek(flowId: string) {
    return this.core.peek(flowId);
  }

  /** Reads the account behind the grant and persists the encrypted token. */
  private async store(userId: string, grant: DeviceGrant): Promise<GithubAccount> {
    const u = await fetchGithubUser(this.deps.fetch, grant.accessToken, grant.scope);
    const account: GithubAccount = { login: u.login, id: u.id, avatarUrl: u.avatarUrl, scopes: u.scopes };
    await this.deps.save({
      ...account,
      userId,
      accessTokenEnc: this.deps.encrypt(grant.accessToken),
      refreshTokenEnc: grant.refreshToken ? this.deps.encrypt(grant.refreshToken) : null,
      expiresAt: grant.expiresIn > 0 ? new Date(this.deps.now() + grant.expiresIn * 1000) : null,
    });
    return account;
  }
}
