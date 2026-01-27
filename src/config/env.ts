import { z } from "zod";
import "dotenv/config";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),

  // Prefer full DSN, but allow deriving it from PG_* variables in some platforms.
  DATABASE_URL: z.string().min(1).optional(),

  PG_HOST: z.string().min(1).optional(),
  PG_PORT: z.coerce.number().int().positive().optional(),
  PG_USER: z.string().min(1).optional(),
  PG_PASSWORD: z.string().optional(),
  PG_DATABASE: z.string().min(1).optional(),
  PG_SSLMODE: z.string().optional(),

  JWT_ACCESS_SECRET: z.string().min(16),
  JWT_ACCESS_EXPIRES_IN: z.string().min(1).default("15m"),

  JWT_REFRESH_SECRET: z.string().min(16),
  JWT_REFRESH_EXPIRES_IN: z.string().min(1).default("30d"),

  CORS_ORIGINS: z.string().default("*"),

  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(60_000),
  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(300),

  LOG_LEVEL: z
    .enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"])
    .default("info"),

  // Files/uploads
  UPLOAD_DIR: z.string().min(1).default("uploads"),
});

type ParsedEnv = z.infer<typeof envSchema>;
export type Env = Omit<ParsedEnv, "DATABASE_URL"> & { DATABASE_URL: string };

const buildDatabaseUrl = (e: ParsedEnv): string | undefined => {
  if (!e.PG_HOST || !e.PG_USER || !e.PG_DATABASE) return undefined;

  const user = encodeURIComponent(e.PG_USER);
  const password = e.PG_PASSWORD ? encodeURIComponent(e.PG_PASSWORD) : undefined;
  const auth = password ? `${user}:${password}` : user;
  const port = e.PG_PORT ?? 5432;

  const sslmode = e.PG_SSLMODE?.trim();
  const query = sslmode ? `?sslmode=${encodeURIComponent(sslmode)}` : "";

  return `postgresql://${auth}@${e.PG_HOST}:${port}/${e.PG_DATABASE}${query}`;
};

let parsed: ParsedEnv;
try {
  parsed = envSchema.parse(process.env);
} catch (err) {
  // Make startup errors more actionable in container logs.
  // eslint-disable-next-line no-console
  console.error("Invalid environment variables", err);
  throw err;
}

const databaseUrl = parsed.DATABASE_URL ?? buildDatabaseUrl(parsed);
if (!databaseUrl) {
  throw new Error(
    "DATABASE_URL is required (or provide PG_HOST/PG_USER/PG_PASSWORD/PG_DATABASE).",
  );
}

export const env: Env = {
  ...parsed,
  DATABASE_URL: databaseUrl,
};

export const corsOrigins: string[] | "*" = (() => {
  const raw = env.CORS_ORIGINS.trim();
  if (raw === "*") return "*";
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
})();
