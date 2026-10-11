import { Router } from "express";
import { config } from "../config.js";
import { userOf } from "../auth/context.js";
import { AppError } from "../util/errors.js";
import { notConfigured } from "../connections/deviceFlow.js";
import { deleteGithubConnection, deviceFlows, listConnections } from "../connections/store.js";

/** The signed-in user's linked accounts (GitHub today). Tokens never leave the server. */
export const connectionsRouter = Router();

const uid = (req: Parameters<typeof userOf>[0]) => {
  const id = userOf(req).id;
  if (!id) throw new AppError(403, "forbidden", "Sign in with an account to connect services");
  return id;
};

connectionsRouter.use((_req, res, next) => {
  res.setHeader("Cache-Control", "no-store");
  next();
});

connectionsRouter.get("/", async (req, res) => {
  const user = userOf(req);
  res.json({
    items: user.id ? await listConnections(user.id) : [],
    // web: the one-tap OAuth web flow is available (needs the client secret).
    providers: { github: { configured: !!config.githubOAuth.clientId, web: !!(config.githubOAuth.clientId && config.githubOAuth.clientSecret) } },
    isOwner: user.role === "owner",
  });
});

connectionsRouter.post("/github/device", async (req, res) => {
  if (!config.githubOAuth.clientId) throw notConfigured();
  const id = uid(req);
  res.json(await deviceFlows.start(id));
});

connectionsRouter.get("/github/device/:flowId", async (req, res) => {
  res.json(await deviceFlows.poll(uid(req), String(req.params.flowId)));
});

connectionsRouter.delete("/github", async (req, res) => {
  res.json(await deleteGithubConnection(uid(req)));
});
