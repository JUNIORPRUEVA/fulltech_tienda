import type { ErrorRequestHandler } from "express";
import { ZodError } from "zod";
import { AppError, isRecord } from "../utils/errors.js";
import { logger } from "../utils/logger.js";

export const errorHandler: ErrorRequestHandler = (
  err,
  req,
  res,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  next,
) => {
  const requestId = req.id;

  if (err instanceof ZodError) {
    return res.status(400).json({
      error: {
        code: "VALIDATION_ERROR",
        message: "Invalid request",
        details: err.issues,
        requestId,
      },
    });
  }

  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: {
        code: err.code,
        message: err.message,
        requestId,
      },
    });
  }

  // Prisma known errors (keep generic to avoid leaking internals)
  if (isRecord(err) && typeof err["code"] === "string") {
    const code = String(err["code"]);
    if (code.startsWith("P")) {
      logger.error({ err, requestId }, "prisma.error");
      return res.status(400).json({
        error: {
          code: "DB_ERROR",
          message: "Database error",
          requestId,
        },
      });
    }
  }

  logger.error({ err, requestId }, "unhandled.error");
  return res.status(500).json({
    error: {
      code: "INTERNAL_ERROR",
      message: "Internal server error",
      requestId,
    },
  });
};
