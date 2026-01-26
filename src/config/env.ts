import { z } from "zod";
import "dotenv/config";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),

  DATABASE_URL: z.string().min(1),

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

export type Env = z.infer<typeof envSchema>;

export const env: Env = envSchema.parse(process.env);

export const corsOrigins: string[] | "*" = (() => {
  const raw = env.CORS_ORIGINS.trim();
  if (raw === "*") return "*";
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
})();
