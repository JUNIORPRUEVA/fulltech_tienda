import { createServer } from "node:http";

import { env } from "./config/env.js";
import { createApp } from "./app.js";
import { logger } from "./utils/logger.js";
import { prisma } from "./db/prisma.js";

const app = createApp();
const server = createServer(app);

server.listen(env.PORT, () => {
  logger.info({ port: env.PORT }, "api.listening");
});

const shutdown = async (signal: string) => {
  logger.info({ signal }, "api.shutdown.start");
  server.close(async () => {
    try {
      await prisma.$disconnect();
    } finally {
      logger.info("api.shutdown.done");
      process.exit(0);
    }
  });
};

process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));
