import { z } from "zod";

const moneySchema = z
  .union([z.number(), z.string()])
  .transform((v) => (typeof v === "number" ? v.toString() : v.trim()))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), {
    message: "Invalid money format",
  });

const dateSchema = z
  .union([z.string(), z.date()])
  .transform((v) => (v instanceof Date ? v : new Date(v)))
  .refine((d) => !Number.isNaN(d.getTime()), { message: "Invalid date" });

export const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

export const saleCreateSchema = z.object({
  customerId: z.string().uuid().optional().nullable(),
  total: moneySchema,
  saleAt: dateSchema.optional(),
  note: z.string().max(500).optional().nullable(),
});

export const saleUpdateSchema = saleCreateSchema.partial();
