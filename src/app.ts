import { randomUUID } from "node:crypto";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import pinoHttp from "pino-http";

import { env, corsOrigins } from "./config/env.js";
import { ensureUploadsDir, uploadsDir } from "./config/paths.js";
import { logger } from "./utils/logger.js";
import { apiRateLimit } from "./middlewares/rateLimit.js";
import { errorHandler } from "./middlewares/errorHandler.js";

import { authRouter } from "./modules/auth/auth.router.js";
import { syncRouter } from "./modules/sync/sync.router.js";
import { customersRouter } from "./modules/customers/customers.router.js";
import { productsRouter } from "./modules/products/products.router.js";
import { salesRouter } from "./modules/sales/sales.router.js";
import { filesRouter } from "./modules/files/files.router.js";

export const createApp = () => {
  const app = express();

  app.set("trust proxy", 1);

  const httpLogger = pinoHttp as unknown as (options: any) => any;

  app.use(
    httpLogger({
      logger,
      genReqId: (req: any, res: any) => {
        const existing = req.headers["x-request-id"];
        const id = Array.isArray(existing) ? existing[0] : existing;
        if (id) return id;
        const fallback = randomUUID();
        res.setHeader("x-request-id", fallback);
        return fallback;
      },
    }),
  );

  app.use(helmet());

  app.use(
    cors({
      origin:
        corsOrigins === "*"
          ? true
          : (origin, callback) => {
              if (!origin) return callback(null, true);
              return callback(null, corsOrigins.includes(origin));
            },
      credentials: false,
    }),
  );

  app.use(apiRateLimit);
  app.use(express.json({ limit: "1mb" }));

  ensureUploadsDir();
  app.use("/uploads", express.static(uploadsDir));

  app.get("/", (_req, res) => {
    res.status(200).json({ status: "ok" });
  });

  app.get("/health", (_req, res) => {
    res.status(200).json({ status: "ok", env: env.NODE_ENV });
  });

  app.use("/auth", authRouter);
  app.use("/sync", syncRouter);
  app.use("/customers", customersRouter);
  app.use("/products", productsRouter);
  app.use("/sales", salesRouter);
  app.use("/files", filesRouter);

  app.use((_req, res) => {
    res.status(404).json({
      error: { code: "NOT_FOUND", message: "Route not found" },
    });
  });

  app.use(errorHandler);

  return app;
};
