import "server-only";
import { providersSchema, type Providers } from "@/lib/api/schemas";
import { env } from "./env";

const REVALIDATE_SECONDS = 60;
const TIMEOUT_MS = 3_000;
const NONE: Providers = { github: false, githubWeb: false };

export async function fetchProviders(): Promise<Providers> {
  try {
    const res = await fetch(`${env.apiUrl}/auth/providers`, {
      next: { revalidate: REVALIDATE_SECONDS },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) return NONE;
    const parsed = providersSchema.safeParse(await res.json());
    return parsed.success ? parsed.data : NONE;
  } catch {
    return NONE;
  }
}
