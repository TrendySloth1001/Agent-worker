import "dotenv/config";
import { defineConfig, env } from "prisma/config";

// Prisma CLI configuration (migrate, db pull, generate). The app itself
// connects through src/db/prisma.ts with the same DATABASE_URL.
export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations" },
  datasource: { url: env("DATABASE_URL") },
});
