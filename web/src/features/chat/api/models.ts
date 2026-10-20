import { z } from "zod";
import { apiJson } from "./http";

export const modelSchema = z.looseObject({
  id: z.string(),
  name: z.string(),
  provider: z.string().catch(""),
  maker: z.string().optional(),
  about: z.string().optional(),
  contextTokens: z.number().optional(),
  speed: z.enum(["fast", "balanced", "deep"]).optional().catch(undefined),
});

const modelsSchema = z.object({ models: z.array(modelSchema) });

export type AiModel = z.infer<typeof modelSchema>;

export async function fetchModels(): Promise<AiModel[]> {
  const { models } = await apiJson("/models", modelsSchema);
  return models;
}
