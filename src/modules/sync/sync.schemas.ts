import { z } from "zod";

export const entitySchema = z.enum(["customers", "products", "sales"]);
export type SyncEntity = z.infer<typeof entitySchema>;

export const opTypeSchema = z.enum(["UPSERT", "DELETE"]);
export type SyncOpType = z.infer<typeof opTypeSchema>;

export const baseOpSchema = z.object({
  opId: z.string().uuid(),
  entity: entitySchema,
  entityId: z.string().uuid(),
  type: opTypeSchema,
  payload: z.unknown().optional(),
  clientUpdatedAt: z.string().datetime({ offset: true }),
  deviceId: z.string().min(1).max(200),
});

export type BaseOp = z.infer<typeof baseOpSchema>;

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

export const customerPayloadSchema = z.object({
  name: z.string().min(1).max(200),
  email: z.string().email().max(320).optional().nullable(),
  phone: z.string().min(1).max(50).optional().nullable(),
  address: z.string().min(1).max(500).optional().nullable(),
});

export const productPayloadSchema = z.object({
  name: z.string().min(1).max(200),
  sku: z.string().min(1).max(100).optional().nullable(),
  price: moneySchema,
  stock: moneySchema.optional(),
  imageUrl: z.string().min(1).max(2000).optional().nullable(),
});

export const salePayloadSchema = z.object({
  customerId: z.string().uuid().optional().nullable(),
  total: moneySchema,
  saleAt: dateSchema.optional(),
  note: z.string().max(500).optional().nullable(),
});

export const pullQuerySchema = z.object({
  since: z
    .string()
    .datetime({ offset: true })
    .optional()
    .default("1970-01-01T00:00:00.000Z"),
});
