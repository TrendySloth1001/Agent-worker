import { Router } from "express";
import { MODELS, cooldownUntil } from "../models.js";
import { aboutModel } from "../modelAbout.js";

export const modelsRouter = Router();

// The app adds its own "Auto" row, so only real models are listed here.
modelsRouter.get("/", (_req, res) => {
  res.json({
    models: MODELS.map((m) => {
      const until = cooldownUntil(m.id);
      return { ...m, ...aboutModel(m), cooldownUntil: until ? new Date(until).toISOString() : null };
    }),
    default: "auto",
  });
});
