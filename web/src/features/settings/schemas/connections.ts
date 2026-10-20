import { z } from "zod";

export const PROVIDER_GITHUB = "github";
export const PROVIDER_DRIVE = "google_drive";

export const connectionSchema = z.object({
  provider: z.string(),
  accountLogin: z.string(),
  avatarUrl: z.string().nullable(),
  accountName: z.string().nullable(),
  accountEmail: z.string().nullable(),
  scopes: z.array(z.string()),
  missingScopes: z.array(z.string()),
  needsReauth: z.boolean(),
});
export type Connection = z.infer<typeof connectionSchema>;

const availabilitySchema = z.object({ configured: z.boolean(), web: z.boolean() });

export const connectionsSchema = z.object({
  items: z.array(connectionSchema),
  providers: z.record(z.string(), availabilitySchema),
});
export type Connections = z.infer<typeof connectionsSchema>;

export const deviceFlowSchema = z.object({
  flowId: z.string(),
  userCode: z.string(),
  verificationUri: z.string(),
  verificationUriComplete: z.string().nullable(),
  expiresIn: z.number(),
  interval: z.number(),
});
export type DeviceFlow = z.infer<typeof deviceFlowSchema>;

export const devicePollSchema = z.object({
  status: z.enum(["pending", "connected", "expired", "denied", "error"]),
  interval: z.number().optional(),
  error: z.string().nullable().optional(),
});
export type DevicePoll = z.infer<typeof devicePollSchema>;

export const authorizeSchema = z.object({ authorizeUrl: z.string(), state: z.string() });
