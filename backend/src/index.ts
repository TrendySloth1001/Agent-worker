import express from "express";
import cors from "cors";
import { config } from "./config.js";
import { log } from "./util/logger.js";
import { AppError, errorMiddleware } from "./util/errors.js";
import { rateLimit } from "./util/rateLimit.js";
import { initDb, closeDb, onDbUp } from "./db/pool.js";
import { reembedAll } from "./embeddings/reembed.js";
import { knowledgeRouter } from "./routes/knowledge.js";
import { chatRouter } from "./routes/chat.js";
import { modelsRouter } from "./routes/models.js";
import { usageRouter } from "./routes/usage.js";
import { healthRouter } from "./routes/health.js";
import { conversationsRouter } from "./routes/conversations.js";
import { imagesRouter } from "./routes/images.js";
import { iconsRouter } from "./routes/icons.js";
import { assistRouter } from "./routes/assist.js";
import { filesRouter } from "./routes/files.js";
import { failInterrupted } from "./files/process.js";

const app = express();
app.disable("x-powered-by");
// Saved conversations carry the full history, so they get a larger body limit.
const smallJson = express.json({ limit: "256kb" });
const largeJson = express.json({ limit: "4mb" });
app.use((req, res, next) => (req.path.startsWith("/conversations") ? largeJson : smallJson)(req, res, next));
app.use(cors());

// Optional bearer token; /health stays open.
app.use((req, _res, next) => {
  if (!config.apiToken || req.path === "/health") return next();
  if (req.headers.authorization === `Bearer ${config.apiToken}`) return next();
  next(new AppError(401, "unauthorized", "Missing or invalid token"));
});

app.post("/chat", rateLimit(20));
app.post("/knowledge/sources", rateLimit(10));

app.use("/health", healthRouter);
app.use("/models", modelsRouter);
app.use("/usage", usageRouter);
app.use("/chat", chatRouter);
app.use("/knowledge", knowledgeRouter);
app.use("/conversations", conversationsRouter);
app.use("/images", imagesRouter);
app.use("/icons", iconsRouter);
app.use("/assist", assistRouter);
app.use("/files", filesRouter);

app.use((_req, _res, next) => next(new AppError(404, "not_found", "Not found")));
app.use(errorMiddleware);

process.on("unhandledRejection", (reason) => {
  log.error("unhandledRejection", { message: reason instanceof Error ? reason.message.slice(0, 200) : String(reason).slice(0, 200) });
});

// After a model switch, rebuild stored vectors as soon as the database is ready.
onDbUp(() => void reembedAll());
onDbUp(() => void failInterrupted());
initDb();
const server = app.listen(config.port, () => log.info(`Server listening on http://localhost:${config.port}`));

let closing = false;
function shutdown() {
  if (closing) return;
  closing = true;
  server.close();
  server.closeAllConnections();
  closeDb().finally(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
