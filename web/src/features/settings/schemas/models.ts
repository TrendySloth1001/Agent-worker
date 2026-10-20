import { z } from "zod";

export const modelSchema = z.object({
  id: z.string(),
  name: z.string(),
  provider: z.string(),
  maker: z.string(),
  about: z.string(),
  contextTokens: z.number(),
  speed: z.enum(["fast", "balanced", "deep"]),
  cooldownUntil: z.string().nullable(),
});
export type Model = z.infer<typeof modelSchema>;

export const modelsSchema = z.object({ models: z.array(modelSchema) });
