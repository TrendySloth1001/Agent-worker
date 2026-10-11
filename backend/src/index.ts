import express from "express";
import cors from "cors";
import { config } from "./config.js";
import { log } from "./util/logger.js";
import { AppError, errorMiddleware } from "./util/errors.js";
import { rateLimit } from "./util/rateLimit.js";
import { initDb, closeDb, onDbUp } from "./db/prisma.js";
import { reembedAll } from "./embeddings/reembed.js";
import { knowledgeRouter } from "./routes/knowledge.js";
import { chatRouter } from "./routes/chat.js";
import { modelsRouter } from "./routes/models.js";
import { usageRouter } from "./routes/usage.js";
import { telemetryRouter } from "./routes/telemetry.js";
import { flush as flushUsage, telemetryScope } from "./db/usage.js";
import { healthRouter } from "./routes/health.js";
import { conversationsRouter } from "./routes/conversations.js";
import { imagesRouter } from "./routes/images.js";
import { iconsRouter } from "./routes/icons.js";
import { assistRouter } from "./routes/assist.js";
import { filesRouter } from "./routes/files.js";
import { githubRouter } from "./routes/github.js";
import { connectionsRouter } from "./routes/connections.js";
import { failInterrupted } from "./files/process.js";
import { authPublicRouter, authRouter, requireUser } from "./routes/auth.js";
import { chatLimit, docLimit } from "./auth/limits.js";
import { docsRouter } from "./routes/docs.js";
import { prismaStore as docStore } from "./docs/store.js";
import { liveIds as liveDocIds } from "./docs/registry.js";
import { githubGate } from "./auth/githubGate.js";

const app = express();
app.disable("x-powered-by");
// Saved conversations carry the full history, so they get a larger body limit.
const smallJson = express.json({ limit: "256kb" });
const largeJson = express.json({ limit: "4mb" });
app.use((req, res, next) => (req.path.startsWith("/conversations") ? largeJson : smallJson)(req, res, next));
app.use(cors());

// Public: health and the sign-in endpoints. Everything after requireUser
// needs an access token (Bearer JWT). The static API_TOKEN is still accepted
// as an admin/dev bypass that acts as the owner account (curl tests).
app.use("/health", healthRouter);
app.use("/auth", authPublicRouter);
app.use(requireUser);
app.use(telemetryScope);
app.use("/auth", authRouter);

app.post("/chat", rateLimit(20), chatLimit);
app.post("/docs", rateLimit(5), docLimit);
app.post("/docs/:id/sections/:sid/rewrite", rateLimit(20));
app.post("/knowledge/sources", rateLimit(10));
app.post("/connections/github/device", rateLimit(10));

app.use("/models", modelsRouter);
app.use("/usage", usageRouter);
app.use("/admin/telemetry", telemetryRouter);
app.use("/chat", chatRouter);
app.use("/knowledge", knowledgeRouter);
app.use("/conversations", conversationsRouter);
app.use("/images", imagesRouter);
app.use("/icons", iconsRouter);
app.use("/assist", assistRouter);
app.use("/files", filesRouter);
app.use("/github", githubGate, githubRouter);
app.use("/connections", connectionsRouter);
app.use("/docs", docsRouter);

app.use((_req, _res, next) => next(new AppError(404, "not_found", "Not found")));
app.use(errorMiddleware);

process.on("unhandledRejection", (reason) => {
  log.error("unhandledRejection", { message: reason instanceof Error ? reason.message.slice(0, 200) : String(reason).slice(0, 200) });
});

// After a model switch, rebuild stored vectors as soon as the database is ready.
onDbUp(() => void reembedAll());
onDbUp(() => void failInterrupted());
// Documents left mid-run by a restart can be resumed.
onDbUp(() => void docStore.sweepInterrupted(liveDocIds()).then((n) => n && log.info("docs interrupted", { count: n })).catch(() => undefined));
initDb();
const server = app.listen(config.port, () => log.info(`Server listening on http://localhost:${config.port}`));

let closing = false;
function shutdown() {
  if (closing) return;
  closing = true;
  server.close();
  server.closeAllConnections();
  flushUsage()
    .catch(() => {})
    .finally(() => closeDb().finally(() => process.exit(0)));
  setTimeout(() => process.exit(0), 3000).unref();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
