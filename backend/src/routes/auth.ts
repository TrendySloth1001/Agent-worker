import { Router, type Request } from "express";
import { z } from "zod";
import { db } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { rateLimit } from "../util/rateLimit.js";
import { deleteFile, INFO_SELECT, toFileRow } from "../files/store.js";
import { userOf } from "../auth/context.js";
import { limitsFor, resetsAt, usageFor } from "../auth/limits.js";
import {
  BAD_LOGIN,
  checkPassword,
  deviceLabel,
  forgetUser,
  getUser,
  hashPassword,
  listSessions,
  login,
  publicUser,
  refresh,
  register,
  requireUser,
  revokeByRefresh,
  revokeFamily,
  revokeOthers,
  type Tokens,
  type UserRow,
} from "../auth/service.js";

/** Routes that need no session: register, login, refresh, logout. */
export const authPublicRouter = Router();
/** Routes for the signed-in user (mounted behind requireUser). */
export const authRouter = Router();

const PASSWORD_MIN = 8;
const PASSWORD_MAX = 200;
const NAME_MAX = 60;
// An avatar is a small data URL (the app sends a resized JPEG) or an https URL.
const AVATAR_MAX = 200_000;

const email = z.string().trim().max(254).email("Enter a valid email");
const password = z.string().min(PASSWORD_MIN, `Password must be at least ${PASSWORD_MIN} characters`).max(PASSWORD_MAX);
const device = z.string().max(120).optional();

const registerBody = z.object({
  email,
  password,
  name: z.string().trim().min(1, "Enter your name").max(NAME_MAX),
  device,
  // Proof for claiming OWNER_EMAIL (the static API_TOKEN).
  ownerToken: z.string().max(500).optional(),
});
const loginBody = z.object({ email: z.string().trim().max(254), password: z.string().max(PASSWORD_MAX), device });
const refreshBody = z.object({ refreshToken: z.string().min(10).max(200), device });

const session = (user: UserRow, t: Tokens) => ({
  user: publicUser(user),
  accessToken: t.accessToken,
  accessExpiresAt: t.accessExpiresAt,
  refreshToken: t.refreshToken,
  refreshExpiresAt: t.refreshExpiresAt,
  sessionId: t.sessionId,
});

// Brute-force guard per IP; login and register share no budget.
authPublicRouter.post("/register", rateLimit(10, 60 * 60_000));
authPublicRouter.post("/login", rateLimit(10, 60_000));
authPublicRouter.post("/refresh", rateLimit(60, 60_000));

authPublicRouter.post("/register", async (req, res) => {
  const body = registerBody.parse(req.body ?? {});
  const { user, tokens } = await register(body, deviceLabel(req, body));
  log.info("account registered", { role: user.role });
  res.status(201).json(session(user, tokens));
});

authPublicRouter.post("/login", async (req, res) => {
  const parsed = loginBody.safeParse(req.body ?? {});
  if (!parsed.success) throw new AppError(401, "invalid_credentials", BAD_LOGIN);
  const { user, tokens } = await login(parsed.data.email, parsed.data.password, deviceLabel(req, parsed.data));
  res.json(session(user, tokens));
});

authPublicRouter.post("/refresh", async (req, res) => {
  const parsed = refreshBody.safeParse(req.body ?? {});
  if (!parsed.success) throw new AppError(401, "invalid_refresh", "Session expired, please sign in again");
  const { user, tokens } = await refresh(parsed.data.refreshToken, deviceLabel(req, parsed.data));
  res.json(session(user, tokens));
});

// Ends the session of the given refresh token. Always 204, so it reveals nothing.
authPublicRouter.post("/logout", async (req, res) => {
  const token = typeof req.body?.refreshToken === "string" ? req.body.refreshToken : "";
  if (token) await revokeByRefresh(token).catch(() => undefined);
  res.status(204).end();
});

// ---- signed in ----------------------------------------------------------

async function me(req: Request) {
  const u = userOf(req);
  if (!u.id) throw new AppError(404, "no_owner", "The owner account has not been created yet");
  const user = await getUser(u.id);
  if (!user) throw new AppError(401, "unauthorized", "Session expired");
  return user;
}

authRouter.get("/me", async (req, res) => {
  const user = await me(req);
  const [limits, usage] = await Promise.all([limitsFor(userOf(req)), usageFor(user.id)]);
  res.json({ user: publicUser(user), limits, usage, resetsAt: resetsAt(), unlimited: limits === null });
});

const patchBody = z
  .object({
    name: z.string().trim().min(1).max(NAME_MAX).optional(),
    avatar: z
      .string()
      .max(AVATAR_MAX, "Avatar image is too large")
      .refine((s) => /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(s) || /^https:\/\/\S+$/.test(s), "Avatar must be an image")
      .nullable()
      .optional(),
  })
  .refine((b) => b.name !== undefined || b.avatar !== undefined, "Nothing to change");

authRouter.patch("/me", async (req, res) => {
  const user = await me(req);
  const b = patchBody.parse(req.body ?? {});
  const updated = await db().user.update({
    where: { id: user.id },
    data: { ...(b.name != null ? { name: b.name } : {}), ...(b.avatar !== undefined ? { avatarUrl: b.avatar } : {}) },
  });
  res.json({ user: publicUser(updated) });
});

const passwordBody = z.object({ current: z.string().max(PASSWORD_MAX), next: password });

// Changing the password signs out every other device.
authRouter.post("/password", async (req, res) => {
  const user = await me(req);
  const b = passwordBody.parse(req.body ?? {});
  if (!(await checkPassword(user.passwordHash, b.current))) throw new AppError(400, "wrong_password", "Current password is wrong");
  await db().user.update({ where: { id: user.id }, data: { passwordHash: await hashPassword(b.next) } });
  await revokeOthers(user.id, userOf(req).sid);
  res.status(204).end();
});

authRouter.get("/sessions", async (req, res) => {
  const user = await me(req);
  res.json({ sessions: await listSessions(user.id, userOf(req).sid) });
});

authRouter.delete("/sessions/:id", async (req, res) => {
  const user = await me(req);
  const id = String(req.params.id);
  if (!z.string().uuid().safeParse(id).success || !(await revokeFamily(user.id, id))) {
    throw new AppError(404, "not_found", "Session not found");
  }
  res.status(204).end();
});

const deleteBody = z.object({ password: z.string().max(PASSWORD_MAX) });

// Deletes the account and everything it owns, including stored files.
authRouter.delete("/me", async (req, res) => {
  const user = await me(req);
  if (user.role === "owner") throw new AppError(403, "owner_cannot_delete", "The owner account cannot be deleted");
  const b = deleteBody.safeParse(req.body ?? {});
  if (!b.success || !(await checkPassword(user.passwordHash, b.data.password))) {
    throw new AppError(400, "wrong_password", "Password is wrong");
  }
  const files = (await db().storedFile.findMany({ where: { userId: user.id }, select: INFO_SELECT })).map(toFileRow);
  for (const f of files) await deleteFile(f).catch(() => undefined);
  // Conversations, sources (documents, chunks), sessions and usage cascade.
  await db().user.deleteMany({ where: { id: user.id } });
  forgetUser(user.id);
  log.info("account deleted", { files: files.length });
  res.status(204).end();
});

export { requireUser };
