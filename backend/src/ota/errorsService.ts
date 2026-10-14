import { db, type Tx } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import {
  ERROR_RETENTION_DAYS,
  GROUP_STATUSES,
  SESSION_RETENTION_DAYS,
  SESSION_SETTLE_MS,
  crashFreeRate,
  prepareError,
  retentionCutoff,
  shouldStoreSample,
  type ErrorItem,
  type GroupStatus,
  type PreparedError,
  type SessionItem,
} from "./errorsLogic.js";

/** DB side of in-house error reporting. All writes take the user id from the session, never the body. */

const DAY_MS = 24 * 3600_000;

/** Records one prepared error: group counters, distinct users, and (capped) a sample event. */
async function recordOne(tx: Tx, userId: string, e: PreparedError): Promise<{ sampled: boolean }> {
  const fp = e.fingerprint;
  const at = e.at;
  // Group row. A resolved group seen on a newer build reopens (regression); counts always increment.
  await tx.$executeRaw`
    INSERT INTO app_error_groups (fingerprint, first_build, last_build, count, users, first_seen, last_seen, status, title, kind)
    VALUES (${fp}, ${e.build}, ${e.build}, 1, 0, ${at}, ${at}, 'open', ${e.title}, ${e.kind})
    ON CONFLICT (fingerprint) DO UPDATE SET
      count = app_error_groups.count + 1,
      status = CASE WHEN app_error_groups.status = 'resolved' AND ${e.build} > app_error_groups.last_build THEN 'open' ELSE app_error_groups.status END,
      first_build = LEAST(app_error_groups.first_build, ${e.build}),
      last_build = GREATEST(app_error_groups.last_build, ${e.build}),
      last_seen = GREATEST(app_error_groups.last_seen, ${at}),
      first_seen = LEAST(app_error_groups.first_seen, ${at})`;
  const inserted = await tx.$queryRaw<Array<{ inserted: boolean }>>`
    INSERT INTO app_error_group_users (fingerprint, build, user_id, last_seen)
    VALUES (${fp}, ${e.build}, ${userId}::uuid, ${at})
    ON CONFLICT (fingerprint, build, user_id) DO UPDATE SET last_seen = GREATEST(app_error_group_users.last_seen, EXCLUDED.last_seen)
    RETURNING (xmax = 0) AS inserted`;
  const newUser = inserted[0]?.inserted === true;
  await tx.$executeRaw`
    INSERT INTO app_error_group_builds (fingerprint, build, count, users, first_seen, last_seen)
    VALUES (${fp}, ${e.build}, 1, ${newUser ? 1 : 0}, ${at}, ${at})
    ON CONFLICT (fingerprint, build) DO UPDATE SET
      count = app_error_group_builds.count + 1,
      users = app_error_group_builds.users + ${newUser ? 1 : 0},
      last_seen = GREATEST(app_error_group_builds.last_seen, ${at})`;
  if (newUser) {
    // Distinct across builds, so recomputed from the user rows rather than incremented.
    await tx.$executeRaw`
      UPDATE app_error_groups SET users = (SELECT count(DISTINCT user_id)::int FROM app_error_group_users WHERE fingerprint = ${fp})
      WHERE fingerprint = ${fp}`;
  }
  const [{ n: forBuild }] = await tx.$queryRaw<Array<{ n: number }>>`
    SELECT count(*)::int AS n FROM app_error_events WHERE fingerprint = ${fp} AND build = ${e.build}`;
  const [{ n: today }] = await tx.$queryRaw<Array<{ n: number }>>`
    SELECT count(*)::int AS n FROM app_error_events WHERE user_id = ${userId}::uuid AND at > ${new Date(Date.now() - DAY_MS)}`;
  if (!shouldStoreSample(forBuild, today)) return { sampled: false };
  await tx.$executeRaw`
    INSERT INTO app_error_events (fingerprint, user_id, build, at, kind, message, stack, breadcrumbs, device, session_id)
    VALUES (${fp}, ${userId}::uuid, ${e.build}, ${at}, ${e.kind}, ${e.message}, ${e.stack},
            ${JSON.stringify(e.breadcrumbs)}::jsonb, ${JSON.stringify(e.device)}::jsonb, ${e.sessionId}::uuid)`;
  return { sampled: true };
}

/** POST /app/errors: scrub, fingerprint and record each error; returns how many were accepted and sampled. */
export async function ingestErrors(userId: string, items: ErrorItem[], now = Date.now()): Promise<{ accepted: number; sampled: number }> {
  const prepared = items.map((i) => prepareError(i, now));
  let sampled = 0;
  await db().$transaction(async (tx) => {
    for (const p of prepared) if ((await recordOne(tx, userId, p)).sampled) sampled++;
  });
  return { accepted: prepared.length, sampled };
}

/** POST /app/sessions: upsert by client session id; a row only ever changes for the user who created it. */
export async function ingestSessions(userId: string, items: SessionItem[]): Promise<number> {
  let n = 0;
  await db().$transaction(async (tx) => {
    for (const s of items) {
      const started = new Date(s.startedAt);
      const ended = s.endedAt != null ? new Date(s.endedAt) : null;
      const rows = await tx.$executeRaw`
        INSERT INTO app_sessions (id, user_id, build, patch_number, started_at, ended_at, outcome)
        VALUES (${s.id}::uuid, ${userId}::uuid, ${s.build}, ${s.patchNumber ?? null}, ${started}, ${ended}, ${s.outcome})
        ON CONFLICT (id) DO UPDATE SET
          ended_at = COALESCE(EXCLUDED.ended_at, app_sessions.ended_at),
          outcome = CASE
            WHEN app_sessions.outcome = 'unknown' THEN EXCLUDED.outcome
            WHEN app_sessions.outcome = 'killed' AND EXCLUDED.outcome IN ('crash', 'anr') THEN EXCLUDED.outcome
            ELSE app_sessions.outcome END
        WHERE app_sessions.user_id = EXCLUDED.user_id`;
      n += rows;
    }
  });
  return n;
}

// ---- owner views ---------------------------------------------------------------------

export type GroupRow = {
  fingerprint: string;
  title: string;
  kind: string;
  status: string;
  count: number;
  users: number;
  firstBuild: number;
  lastBuild: number;
  firstSeen: string;
  lastSeen: string;
  buildCount: number | null;
  buildUsers: number | null;
};

type RawGroup = {
  fingerprint: string;
  title: string;
  kind: string;
  status: string;
  count: bigint;
  users: number;
  first_build: number;
  last_build: number;
  first_seen: Date;
  last_seen: Date;
  b_count: bigint | null;
  b_users: number | null;
};

const toGroup = (r: RawGroup): GroupRow => ({
  fingerprint: r.fingerprint,
  title: r.title,
  kind: r.kind,
  status: r.status,
  count: Number(r.count),
  users: r.users,
  firstBuild: r.first_build,
  lastBuild: r.last_build,
  firstSeen: r.first_seen.toISOString(),
  lastSeen: r.last_seen.toISOString(),
  buildCount: r.b_count == null ? null : Number(r.b_count),
  buildUsers: r.b_users,
});

/** Groups seen on [build] (or all builds), most users affected first. */
export async function listGroups(opts: { build?: number; status?: GroupStatus | "all"; limit: number }) {
  const status = opts.status ?? "open";
  const rows =
    opts.build != null
      ? await db().$queryRaw<RawGroup[]>`
          SELECT g.*, b.count AS b_count, b.users AS b_users
          FROM app_error_groups g JOIN app_error_group_builds b ON b.fingerprint = g.fingerprint AND b.build = ${opts.build}
          WHERE (${status}::text = 'all' OR g.status = ${status})
          ORDER BY b.users DESC, b.count DESC, g.last_seen DESC LIMIT ${opts.limit}`
      : await db().$queryRaw<RawGroup[]>`
          SELECT g.*, NULL::bigint AS b_count, NULL::int AS b_users
          FROM app_error_groups g
          WHERE (${status}::text = 'all' OR g.status = ${status})
          ORDER BY g.users DESC, g.count DESC, g.last_seen DESC LIMIT ${opts.limit}`;
  const builds = await db().$queryRaw<Array<{ build: number }>>`SELECT DISTINCT build FROM app_error_group_builds ORDER BY build DESC LIMIT 30`;
  return { groups: rows.map(toGroup), builds: builds.map((b) => b.build) };
}

export async function groupDetail(fingerprint: string) {
  const rows = await db().$queryRaw<RawGroup[]>`
    SELECT g.*, NULL::bigint AS b_count, NULL::int AS b_users FROM app_error_groups g WHERE g.fingerprint = ${fingerprint}`;
  if (!rows[0]) throw new AppError(404, "not_found", "Unknown error group");
  const [perBuild, events] = await Promise.all([
    db().appErrorGroupBuild.findMany({ where: { fingerprint }, orderBy: { build: "desc" }, take: 30 }),
    db().appErrorEvent.findMany({ where: { fingerprint }, orderBy: { at: "desc" }, take: 20 }),
  ]);
  return {
    group: toGroup(rows[0]),
    builds: perBuild.map((b) => ({ build: b.build, count: Number(b.count), users: b.users, lastSeen: b.lastSeen.toISOString() })),
    samples: events.map((e) => ({
      id: String(e.id),
      build: e.build,
      at: e.at.toISOString(),
      kind: e.kind,
      message: e.message,
      stack: e.stack,
      breadcrumbs: e.breadcrumbs,
      device: e.device,
      // The id prefix only; the e-mail is fetched on an explicit tap (userOfEvent).
      user: e.userId.slice(0, 8),
    })),
  };
}

export async function userOfEvent(eventId: string): Promise<{ email: string | null }> {
  if (!/^\d{1,18}$/.test(eventId)) throw new AppError(400, "bad_request", "Invalid event id");
  const ev = await db().appErrorEvent.findUnique({ where: { id: BigInt(eventId) }, select: { userId: true } });
  if (!ev) throw new AppError(404, "not_found", "Unknown event");
  const u = await db().user.findUnique({ where: { id: ev.userId }, select: { email: true } });
  return { email: u?.email ?? null };
}

export async function setGroupStatus(fingerprint: string, status: string): Promise<void> {
  if (!(GROUP_STATUSES as readonly string[]).includes(status)) throw new AppError(400, "bad_request", "Invalid status");
  const n = await db().$executeRaw`UPDATE app_error_groups SET status = ${status} WHERE fingerprint = ${fingerprint}`;
  if (!n) throw new AppError(404, "not_found", "Unknown error group");
}

export type BuildHealth = {
  build: number;
  sessions: number;
  users: number;
  crashed: number;
  crashFree: number | null;
  errorGroups: number;
};

/** Crash-free sessions per build over the last [days] days (sessions still possibly running are left out). */
export async function buildsHealth(days: number, now = Date.now()): Promise<BuildHealth[]> {
  const since = new Date(now - days * DAY_MS);
  const settled = new Date(now - SESSION_SETTLE_MS);
  const rows = await db().$queryRaw<Array<{ build: number; total: number; users: number; crashed: number }>>`
    SELECT build, count(*)::int AS total, count(DISTINCT user_id)::int AS users,
           (count(*) FILTER (WHERE outcome IN ('crash', 'anr')))::int AS crashed
    FROM app_sessions WHERE started_at >= ${since} AND started_at < ${settled}
    GROUP BY build ORDER BY build DESC`;
  const groups = await db().$queryRaw<Array<{ build: number; n: number }>>`
    SELECT build, count(*)::int AS n FROM app_error_group_builds WHERE last_seen >= ${since} GROUP BY build`;
  const byBuild = new Map(groups.map((g) => [g.build, g.n]));
  return rows.map((r) => ({
    build: r.build,
    sessions: r.total,
    users: r.users,
    crashed: r.crashed,
    crashFree: crashFreeRate(r.total, r.crashed),
    errorGroups: byBuild.get(r.build) ?? 0,
  }));
}

// ---- retention -----------------------------------------------------------------------

/** Deletes error samples older than 30 d and sessions (and per-user group rows) older than 90 d. Group counts stay. */
export async function sweepAppErrors(now = Date.now()): Promise<{ events: number; sessions: number; groupUsers: number }> {
  const events = await db().$executeRaw`DELETE FROM app_error_events WHERE at < ${retentionCutoff(now, ERROR_RETENTION_DAYS)}`;
  const sessions = await db().$executeRaw`DELETE FROM app_sessions WHERE started_at < ${retentionCutoff(now, SESSION_RETENTION_DAYS)}`;
  const groupUsers = await db().$executeRaw`DELETE FROM app_error_group_users WHERE last_seen < ${retentionCutoff(now, SESSION_RETENTION_DAYS)}`;
  return { events, sessions, groupUsers };
}

const SWEEP_EVERY_MS = DAY_MS;
let sweeper: NodeJS.Timeout | null = null;

/** In-process daily sweeper (no cron container). Idempotent; the timer never keeps the process alive. */
export function startAppErrorSweeper(): void {
  if (sweeper) return;
  const run = () =>
    sweepAppErrors()
      .then((r) => (r.events || r.sessions || r.groupUsers) && log.info("app error sweep", r))
      .catch((e: unknown) => log.warn("app error sweep failed", { err: String(e) }));
  setTimeout(run, 60_000).unref();
  sweeper = setInterval(run, SWEEP_EVERY_MS);
  sweeper.unref();
}
