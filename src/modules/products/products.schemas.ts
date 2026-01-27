import { z } from "zod";

const moneySchema = z
  .union([z.number(), z.string()])
  .transform((v) => (typeof v === "number" ? v.toString() : v.trim()))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), {
    message: "Invalid money format",
  });

export const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

export const productCreateSchema = z.object({
  name: z.string().min(1).max(200),
  sku: z.string().min(1).max(100).optional().nullable(),
  price: moneySchema,
  stock: moneySchema.optional(),
  imageUrl: z.string().min(1).max(2000).optional().nullable(),
});

export const productUpdateSchema = productCreateSchema.partial();
