import { z } from "zod";

export const userSchema = z.object({
  id: z.string(),
  email: z.string(),
  name: z.string(),
  avatarUrl: z.string().nullable(),
  role: z.string(),
  createdAt: z.string(),
  lastLoginAt: z.string().nullable(),
  hasPassword: z.boolean(),
  onboarded: z.boolean(),
});
export type User = z.infer<typeof userSchema>;

const limitsSchema = z.object({
  chat: z.number(),
  table: z.number(),
  uploads: z.number(),
  storageBytes: z.number(),
  docs: z.number(),
  ai: z.number(),
});

const usageSchema = z.object({
  chats: z.number(),
  tables: z.number(),
  uploads: z.number(),
  bytes: z.number(),
  storageBytes: z.number(),
  docs: z.number(),
  ai: z.number(),
});

export const meSchema = z.object({
  user: userSchema,
  limits: limitsSchema.nullable(),
  usage: usageSchema,
  resetsAt: z.string(),
  unlimited: z.boolean(),
});
export type Me = z.infer<typeof meSchema>;

export const upstreamSessionSchema = z.object({
  user: userSchema,
  accessToken: z.string(),
  accessExpiresAt: z.string(),
  refreshToken: z.string(),
  refreshExpiresAt: z.string(),
});
export type UpstreamSession = z.infer<typeof upstreamSessionSchema>;

export const authResultSchema = z.object({ user: userSchema });

export const webStartSchema = z.object({ authorizeUrl: z.url(), state: z.string() });

export const providersSchema = z.object({ github: z.boolean(), githubWeb: z.boolean() });
export type Providers = z.infer<typeof providersSchema>;

export const errorBodySchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    retryable: z.boolean().optional(),
  }),
});

export const loginInputSchema = z.object({
  email: z.string().trim().min(1).max(254),
  password: z.string().min(1).max(200),
});
export type LoginInput = z.infer<typeof loginInputSchema>;

export const registerInputSchema = z.object({
  name: z.string().trim().min(1).max(60),
  email: z.string().trim().max(254).pipe(z.email()),
  password: z.string().min(8).max(200),
});
export type RegisterInput = z.infer<typeof registerInputSchema>;
