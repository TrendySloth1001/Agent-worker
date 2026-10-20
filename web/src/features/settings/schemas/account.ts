import { z } from "zod";

export const userSchema = z.object({
  id: z.string(),
  email: z.string().nullable(),
  name: z.string().nullable(),
  avatarUrl: z.string().nullable(),
  role: z.enum(["owner", "member"]),
  createdAt: z.string(),
  hasPassword: z.boolean(),
});
export type User = z.infer<typeof userSchema>;

export const meSchema = z.object({ user: userSchema });

export const sessionSchema = z.object({
  id: z.string(),
  device: z.string().nullable(),
  createdAt: z.string(),
  lastUsedAt: z.string(),
  expiresAt: z.string(),
  current: z.boolean(),
});
export type Session = z.infer<typeof sessionSchema>;
export const sessionsSchema = z.object({ sessions: z.array(sessionSchema) });

export const identitySchema = z.object({
  id: z.string(),
  provider: z.string(),
  email: z.string().nullable(),
  login: z.string().nullable(),
  createdAt: z.string(),
});
export type Identity = z.infer<typeof identitySchema>;
export const signInMethodsSchema = z.object({
  hasPassword: z.boolean(),
  identities: z.array(identitySchema),
});

export const NAME_MAX = 60;
export const AVATAR_MAX = 200_000;
export const PASSWORD_MIN = 8;

export const nameSchema = z.string().trim().min(1, "Add your name").max(NAME_MAX);

export const passwordChangeSchema = z.object({
  current: z.string().optional(),
  next: z.string().min(PASSWORD_MIN, `Use at least ${PASSWORD_MIN} characters`),
});
export type PasswordChange = z.infer<typeof passwordChangeSchema>;
