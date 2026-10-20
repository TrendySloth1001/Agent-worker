import {
  authorizeSchema,
  connectionsSchema,
  deviceFlowSchema,
  devicePollSchema,
} from "../schemas/connections";
import { command, request } from "./http";

export const fetchConnections = () => request("/connections", connectionsSchema);

export const startGithub = () =>
  request("/connections/github/device", deviceFlowSchema, { method: "POST" });

export const pollGithub = (flowId: string) =>
  request(`/connections/github/device/${encodeURIComponent(flowId)}`, devicePollSchema);

export const disconnectGithub = () => command("/connections/github", { method: "DELETE" });

export const startConnector = (provider: string) =>
  request(`/connect/${encodeURIComponent(provider)}/start`, authorizeSchema, { method: "POST" });

export const disconnectConnector = (provider: string) =>
  command(`/connect/${encodeURIComponent(provider)}`, { method: "DELETE" });
