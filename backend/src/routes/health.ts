import { Router } from "express";
import { config } from "../config.js";
import { isDbUp } from "../db/prisma.js";
import { embeddingsHealthy } from "../embeddings/index.js";
import { kbStats } from "../retrieval/search.js";

export const healthRouter = Router();

healthRouter.get("/", async (_req, res) => {
  try {
    const db = isDbUp();
    const embeddings = embeddingsHealthy();
    const kb = db ? await kbStats().catch(() => null) : null;
    const providers = {
      groq: config.groqApiKey ? "configured" : "missing",
      nvidia: config.nvidiaApiKey ? "configured" : "missing",
      ollama: config.ollamaApiKey ? "configured" : "missing",
      openrouter: config.openrouterApiKey ? "configured" : "missing",
    };
    const ok = db && embeddings !== "down" && Object.values(providers).some((p) => p === "configured");
    res.json({
      status: ok ? "ok" : "degraded",
      uptimeS: Math.round(process.uptime()),
      db: db ? "up" : "down",
      embeddings,
      providers,
      kb,
    });
  } catch {
    res.json({ status: "degraded", uptimeS: Math.round(process.uptime()), db: "down", embeddings: "down", providers: {}, kb: null });
  }
});
