import { createServer } from "node:http";

// Some platforms inject PRISMA_CLIENT_ENGINE_TYPE=client, which requires an adapter/accelerateUrl.
// Force the standard engine before importing the Prisma Client.
process.env.PRISMA_CLIENT_ENGINE_TYPE = "library";

const { env } = await import("./config/env.js");
const { createApp } = await import("./app.js");
const { logger } = await import("./utils/logger.js");
const { prisma } = await import("./db/prisma.js");

const app = createApp();
const server = createServer(app);

server.listen(env.PORT, "0.0.0.0", () => {
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
