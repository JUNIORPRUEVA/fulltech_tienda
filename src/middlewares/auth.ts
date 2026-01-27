import type { RequestHandler } from "express";
import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { AppError } from "../utils/errors.js";

type AccessTokenPayload = {
  sub: string;
  iat: number;
  exp: number;
};

export const authRequired: RequestHandler = (req, _res, next) => {
  const authHeader = req.header("authorization") ?? "";
  const token = authHeader.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length)
    : null;

  if (!token) {
    return next(new AppError("Missing Authorization header", 401, "UNAUTHORIZED"));
  }

  try {
    const decoded = jwt.verify(token, env.JWT_ACCESS_SECRET) as AccessTokenPayload;
    req.user = { id: decoded.sub };
    req.deviceId = req.header("x-device-id") ?? undefined;
    return next();
  } catch {
    return next(new AppError("Invalid token", 401, "UNAUTHORIZED"));
  }
};
