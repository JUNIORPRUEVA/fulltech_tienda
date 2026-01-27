import { z } from "zod";

export const entitySchema = z.enum([
  "customers",
  "products",
  "sales",
  "sale_items",
  "quotes",
  "quote_items",
  "operations",
  "technicians",
  "operation_materials",
  "operation_evidences",
  "operation_notes",
  "operation_statuses",
  "employees",
  "employee_logins",
  "payroll_adjustments",
  "payroll_payments",
  "punches",
]);
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

const boolSchema = z
  .union([z.boolean(), z.number(), z.string()])
  .transform((v) => {
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v !== 0;
    const s = v.trim().toLowerCase();
    return s === "1" || s === "true" || s === "si" || s === "yes";
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
  employeeId: z.string().uuid().optional().nullable(),
  code: z.string().min(1).max(100).optional().nullable(),
  total: moneySchema,
  profit: moneySchema.optional(),
  points: moneySchema.optional(),
  currency: z.string().min(1).max(10).optional().nullable(),
  saleAt: dateSchema.optional(),
  note: z.string().max(500).optional().nullable(),
  createdAt: dateSchema.optional(),
});

export const saleItemPayloadSchema = z.object({
  saleId: z.string().uuid(),
  productId: z.string().uuid().optional().nullable(),
  code: z.string().min(1).max(100).optional().nullable(),
  name: z.string().min(1).max(200),
  qty: moneySchema,
  price: moneySchema,
  cost: moneySchema,
  createdAt: dateSchema.optional(),
});

export const quotePayloadSchema = z.object({
  customerId: z.string().uuid().optional().nullable(),
  code: z.string().min(1).max(100).optional().nullable(),
  total: moneySchema,
  currency: z.string().min(1).max(10),
  status: z.string().min(1).max(100),
  notes: z.string().max(1000).optional().nullable(),
  itbisActive: boolSchema,
  itbisRate: z
    .union([z.number(), z.string()])
    .transform((v) => (typeof v === "number" ? v : Number(v)))
    .refine((v) => !Number.isNaN(v), { message: "Invalid itbisRate" }),
  discountGlobal: moneySchema,
  createdAt: dateSchema.optional(),
});

export const quoteItemPayloadSchema = z.object({
  quoteId: z.string().uuid(),
  productId: z.string().uuid().optional().nullable(),
  code: z.string().min(1).max(100).optional().nullable(),
  name: z.string().min(1).max(200),
  price: moneySchema,
  qty: moneySchema,
  discount: moneySchema,
  createdAt: dateSchema.optional(),
});

export const employeePayloadSchema = z.object({
  name: z.string().min(1).max(200),
  username: z.string().min(1).max(100).optional().nullable(),
  role: z.string().min(1).max(100),
  email: z.string().email().max(320).optional().nullable(),
  passwordLegacy: z.string().max(200).optional().nullable(),
  passwordHash: z.string().max(200).optional().nullable(),
  passwordSalt: z.string().max(200).optional().nullable(),
  cedula: z.string().max(100).optional().nullable(),
  address: z.string().max(500).optional().nullable(),
  salaryBiweekly: moneySchema.optional().nullable(),
  goalBiweekly: moneySchema.optional().nullable(),
  employeeOfMonth: boolSchema.optional(),
  hireDate: dateSchema.optional().nullable(),
  curriculumPath: z.string().max(1000).optional().nullable(),
  licensePath: z.string().max(1000).optional().nullable(),
  idCardPhotoPath: z.string().max(1000).optional().nullable(),
  lastJobPath: z.string().max(1000).optional().nullable(),
  blocked: boolSchema.optional(),
  lastLoginAt: dateSchema.optional().nullable(),
  createdAt: dateSchema.optional(),
});

export const employeeLoginPayloadSchema = z.object({
  employeeId: z.string().uuid(),
  time: dateSchema,
  success: boolSchema,
  createdAt: dateSchema.optional(),
});

export const technicianPayloadSchema = z.object({
  name: z.string().min(1).max(200),
  phone: z.string().max(50).optional().nullable(),
  specialty: z.string().min(1).max(200),
  status: z.string().min(1).max(50),
  createdAt: dateSchema.optional(),
  updatedAt: dateSchema.optional(),
});

export const operationPayloadSchema = z.object({
  customerId: z.string().uuid().optional().nullable(),
  code: z.string().min(1).max(100),
  title: z.string().max(200).optional().nullable(),
  serviceType: z.string().min(1).max(200),
  priority: z.string().min(1).max(100),
  status: z.string().min(1).max(100),
  technicianId: z.string().uuid().optional().nullable(),
  technicianEmployeeId: z.string().uuid().optional().nullable(),
  scheduledAt: dateSchema.optional().nullable(),
  estimatedTime: z.string().max(100).optional().nullable(),
  serviceAddress: z.string().max(500).optional().nullable(),
  locationRef: z.string().max(500).optional().nullable(),
  description: z.string().max(2000).optional().nullable(),
  initialObservations: z.string().max(2000).optional().nullable(),
  finalObservations: z.string().max(2000).optional().nullable(),
  amount: moneySchema.optional().nullable(),
  paymentMethod: z.string().max(100).optional().nullable(),
  paymentStatus: z.string().max(100).optional().nullable(),
  paymentPaidAmount: moneySchema.optional().nullable(),
  chkArrived: boolSchema.optional(),
  chkMaterialInstalled: boolSchema.optional(),
  chkSystemTested: boolSchema.optional(),
  chkClientTrained: boolSchema.optional(),
  chkWorkCompleted: boolSchema.optional(),
  warrantyType: z.string().max(100).optional().nullable(),
  warrantyExpiresAt: dateSchema.optional().nullable(),
  finishedAt: dateSchema.optional().nullable(),
  createdAt: dateSchema.optional(),
  updatedAt: dateSchema.optional(),
});

export const operationMaterialPayloadSchema = z.object({
  operationId: z.string().uuid(),
  name: z.string().min(1).max(200),
  createdAt: dateSchema.optional(),
});

export const operationEvidencePayloadSchema = z.object({
  operationId: z.string().uuid(),
  type: z.string().min(1).max(100),
  filePath: z.string().min(1).max(2000),
  createdAt: dateSchema.optional(),
});

export const operationNotePayloadSchema = z.object({
  operationId: z.string().uuid(),
  employeeId: z.string().uuid().optional().nullable(),
  note: z.string().min(1).max(2000),
  createdAt: dateSchema.optional(),
});

export const operationStatusPayloadSchema = z.object({
  operationId: z.string().uuid(),
  fromStatus: z.string().max(100).optional().nullable(),
  toStatus: z.string().min(1).max(100),
  employeeId: z.string().uuid().optional().nullable(),
  createdAt: dateSchema.optional(),
});

export const payrollAdjustmentPayloadSchema = z.object({
  employeeId: z.string().uuid(),
  periodStart: dateSchema,
  periodEnd: dateSchema,
  type: z.string().min(1).max(100),
  amount: moneySchema,
  note: z.string().max(1000).optional().nullable(),
  createdAt: dateSchema.optional(),
});

export const payrollPaymentPayloadSchema = z.object({
  employeeId: z.string().uuid(),
  periodStart: dateSchema,
  periodEnd: dateSchema,
  paidAt: dateSchema,
  baseSalary: moneySchema,
  commission: moneySchema,
  adjustments: moneySchema,
  net: moneySchema,
  status: z.string().min(1).max(100),
  createdAt: dateSchema.optional(),
});

export const punchPayloadSchema = z.object({
  employeeId: z.string().uuid().optional().nullable(),
  type: z.string().min(1).max(100),
  time: dateSchema,
  location: z.string().max(500).optional().nullable(),
  createdAt: dateSchema.optional(),
});

export const pullQuerySchema = z.object({
  since: z
    .string()
    .datetime({ offset: true })
    .optional()
    .default("1970-01-01T00:00:00.000Z"),
});
