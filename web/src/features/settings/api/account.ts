import {
  meSchema,
  sessionsSchema,
  signInMethodsSchema,
  type PasswordChange,
} from "../schemas/account";
import { command, request } from "./http";

export const fetchMe = () => request("/auth/me", meSchema);

export const updateProfile = (patch: { name?: string; avatar?: string | null }) =>
  request("/auth/me", meSchema, { method: "PATCH", body: patch });

export const fetchSessions = () => request("/auth/sessions", sessionsSchema);

export const revokeSession = (id: string) =>
  command(`/auth/sessions/${encodeURIComponent(id)}`, { method: "DELETE" });

export const fetchSignInMethods = () => request("/auth/identities", signInMethodsSchema);

export const unlinkIdentity = (id: string) =>
  command(`/auth/identities/${encodeURIComponent(id)}`, { method: "DELETE" });

export const changePassword = (body: PasswordChange) =>
  command("/auth/password", { method: "POST", body });

export const deleteAccount = (password?: string) =>
  command("/auth/me", { method: "DELETE", body: password ? { password } : {} });

export const logout = async (): Promise<void> => {
  await fetch("/api/auth/logout", { method: "POST" });
};
