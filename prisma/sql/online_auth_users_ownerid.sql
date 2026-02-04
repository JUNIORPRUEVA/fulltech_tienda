-- Reference SQL for FULLTECH cloud auth + multi-tenant (PostgreSQL).
-- Source of truth in this repo: Prisma migrations under `backend/prisma/migrations/`.

-- Tenants / owners (companies)
CREATE TABLE IF NOT EXISTS "User" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "email" TEXT NOT NULL UNIQUE,
  "passwordHash" TEXT NOT NULL,
  "role" TEXT NOT NULL DEFAULT 'USER',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deletedAt" TIMESTAMPTZ NULL
);

-- Employee accounts that log into the app (scoped to a tenant via ownerId)
CREATE TABLE IF NOT EXISTS "Employee" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
  "name" TEXT NOT NULL,
  "username" TEXT NULL,
  "email" TEXT NULL,
  "role" TEXT NOT NULL,
  "passwordLegacy" TEXT NULL,
  "passwordHash" TEXT NULL,
  "passwordSalt" TEXT NULL,
  "blocked" BOOLEAN NOT NULL DEFAULT FALSE,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deletedAt" TIMESTAMPTZ NULL
);

-- Critical multi-tenant indexes (ownerId)
CREATE INDEX IF NOT EXISTS "Employee_ownerId_idx" ON "Employee"("ownerId");
CREATE INDEX IF NOT EXISTS "Customer_ownerId_idx" ON "Customer"("ownerId");
CREATE INDEX IF NOT EXISTS "Product_ownerId_idx" ON "Product"("ownerId");
CREATE INDEX IF NOT EXISTS "Sale_ownerId_idx" ON "Sale"("ownerId");
CREATE INDEX IF NOT EXISTS "Quote_ownerId_idx" ON "Quote"("ownerId");
CREATE INDEX IF NOT EXISTS "Operation_ownerId_idx" ON "Operation"("ownerId");

