import { keysSchema, keyUsageSchema, saveKeySchema, testKeySchema } from "../schemas/keys";
import { command, request } from "./http";

export const fetchKeys = () => request("/me/keys", keysSchema);

export const saveKey = (provider: string, key: string) =>
  request(`/me/keys/${encodeURIComponent(provider)}`, saveKeySchema, {
    method: "PUT",
    body: { key },
  });

export const testKey = (provider: string) =>
  request(`/me/keys/${encodeURIComponent(provider)}/test`, testKeySchema, { method: "POST" });

export const removeKey = (provider: string) =>
  command(`/me/keys/${encodeURIComponent(provider)}`, { method: "DELETE" });

export const fetchKeyUsage = (days: number) =>
  request("/me/usage/keys", keyUsageSchema, { query: { days } });
