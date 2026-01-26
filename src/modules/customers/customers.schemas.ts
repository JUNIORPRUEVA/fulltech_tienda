import { z } from "zod";

export const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

export const customerCreateSchema = z.object({
  name: z.string().min(1).max(200),
  email: z.string().email().max(320).optional().nullable(),
  phone: z.string().min(1).max(50).optional().nullable(),
  address: z.string().min(1).max(500).optional().nullable(),
});

export const customerUpdateSchema = customerCreateSchema.partial();
