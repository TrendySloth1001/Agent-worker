import "server-only";
import { z } from "zod";

const blankToUndefined = (value: unknown) =>
  typeof value === "string" && value.trim() === "" ? undefined : value;

const schema = z.object({
  NODE_ENV: z.string().optional(),
  SPARKY_API_URL: z.preprocess(blankToUndefined, z.url().default("https://sparky.cloudnsofts.com")),
  SESSION_COOKIE_SECURE: z.preprocess(blankToUndefined, z.enum(["true", "false"]).optional()),
  APP_ORIGIN: z.preprocess(blankToUndefined, z.url().optional()),
});

export interface ServerEnv {
  apiUrl: string;
  cookieSecure: boolean;
  appOrigin: string | undefined;
}

const trimSlash = (value: string) => value.replace(/\/+$/, "");

export function parseEnv(source: Record<string, string | undefined>): ServerEnv {
  const parsed = schema.parse(source);
  return {
    apiUrl: trimSlash(parsed.SPARKY_API_URL),
    cookieSecure:
      parsed.SESSION_COOKIE_SECURE === undefined
        ? parsed.NODE_ENV === "production"
        : parsed.SESSION_COOKIE_SECURE === "true",
    appOrigin: parsed.APP_ORIGIN ? new URL(parsed.APP_ORIGIN).origin : undefined,
  };
}

export const env = parseEnv(process.env);
