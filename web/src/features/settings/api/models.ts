import { modelsSchema } from "../schemas/models";
import { request } from "./http";

export const fetchModels = () => request("/models", modelsSchema);
