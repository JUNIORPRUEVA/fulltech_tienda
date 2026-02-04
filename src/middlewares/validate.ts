import type { RequestHandler } from "express";
import type { ZodSchema } from "zod";

export const validateBody = <T>(schema: ZodSchema<T>): RequestHandler => {
  return (req, _res, next) => {
    req.body = schema.parse(req.body);
    next();
  };
};

export const validateQuery = <T>(schema: ZodSchema<T>): RequestHandler => {
  return (req, _res, next) => {
    const parsed = schema.parse(req.query) as any;

    // Some runtimes/framework stacks expose `req.query` as a read-only getter.
    // Avoid re-assigning the property; instead, mutate the existing object.
    if (req.query && typeof req.query === "object") {
      Object.assign(req.query as any, parsed);
    } else {
      (req as any).query = parsed;
    }
    next();
  };
};
