-- CreateEnum
CREATE TYPE "HrApplicationStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- AlterTable
ALTER TABLE "Employee" ADD COLUMN     "curriculumUrl" TEXT,
ADD COLUMN     "idCardPhotoUrl" TEXT,
ADD COLUMN     "lastJobUrl" TEXT,
ADD COLUMN     "licenseUrl" TEXT;

-- AlterTable
ALTER TABLE "OperationEvidence" ADD COLUMN     "fileUrl" TEXT;

-- AlterTable
ALTER TABLE "Product" ADD COLUMN     "category" TEXT;

-- CreateTable
CREATE TABLE "HrApplication" (
    "id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "role" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "whatsapp" TEXT,
    "techType" TEXT,
    "techAreas" JSONB,
    "resumeUrl" TEXT,
    "idCardUrl" TEXT,
    "photoUrl" TEXT,
    "status" "HrApplicationStatus" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deletedAt" TIMESTAMPTZ(6),
    "version" INTEGER NOT NULL DEFAULT 1,
    "updatedBy" UUID,
    "deviceId" TEXT,

    CONSTRAINT "HrApplication_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "HrApplication_ownerId_idx" ON "HrApplication"("ownerId");

-- CreateIndex
CREATE INDEX "HrApplication_status_idx" ON "HrApplication"("status");

-- CreateIndex
CREATE INDEX "HrApplication_updatedAt_idx" ON "HrApplication"("updatedAt");

-- CreateIndex
CREATE INDEX "HrApplication_deletedAt_idx" ON "HrApplication"("deletedAt");

-- CreateIndex
CREATE INDEX "HrApplication_updatedAt_deletedAt_idx" ON "HrApplication"("updatedAt", "deletedAt");

-- CreateIndex
CREATE INDEX "Product_category_idx" ON "Product"("category");

-- AddForeignKey
ALTER TABLE "HrApplication" ADD CONSTRAINT "HrApplication_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
