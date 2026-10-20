import { z } from "zod";

export const keyStatusSchema = z.enum(["valid", "invalid", "quota", "untested"]);
export type KeyStatus = z.infer<typeof keyStatusSchema>;

export const storedKeySchema = z.object({
  provider: z.string(),
  label: z.string(),
  hint: z.string(),
  status: keyStatusSchema,
  lastCheckedAt: z.string().nullable(),
  createdAt: z.string(),
});

export const keyProviderSchema = z.object({
  id: z.string(),
  name: z.string(),
  blurb: z.string(),
  keyUrl: z.string(),
  placeholder: z.string(),
  key: storedKeySchema.nullable(),
});
export type KeyProvider = z.infer<typeof keyProviderSchema>;

export const keysSchema = z.object({
  providers: z.array(keyProviderSchema),
  hasValidKey: z.boolean(),
});

export const checkResultSchema = z.enum(["valid", "invalid", "quota", "network"]);
export type CheckResult = z.infer<typeof checkResultSchema>;

export const saveKeySchema = z.object({
  key: storedKeySchema,
  result: checkResultSchema,
  message: z.string(),
});

export const testKeySchema = z.object({
  provider: z.string(),
  status: keyStatusSchema,
  result: checkResultSchema,
  message: z.string(),
  checkedAt: z.string().nullable(),
});
export type TestKeyResult = z.infer<typeof testKeySchema>;

export const KEY_MAX = 400;
export const keyInputSchema = z.string().trim().min(1, "Paste your key").max(KEY_MAX);

const bucketSchema = z.object({
  requests: z.number(),
  tokens: z.number(),
  errors: z.number(),
});

export const keyUsageSchema = z.object({
  enabled: z.boolean(),
  days: z.number(),
  totals: z.object({
    requests: z.number(),
    errors: z.number(),
    promptTokens: z.number(),
    completionTokens: z.number(),
    tokens: z.number(),
    avgLatencyMs: z.number().nullable(),
  }),
  byDay: z.array(bucketSchema.extend({ day: z.string() })),
  byProvider: z.array(
    bucketSchema.extend({ provider: z.string(), avgLatencyMs: z.number().nullable() }),
  ),
  byModel: z.array(
    bucketSchema.extend({
      provider: z.string(),
      model: z.string(),
      avgLatencyMs: z.number().nullable(),
    }),
  ),
});
export type KeyUsage = z.infer<typeof keyUsageSchema>;

export const USAGE_DAYS = [7, 30] as const;
export type UsageDays = (typeof USAGE_DAYS)[number];
