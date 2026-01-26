import { Prisma } from "@prisma/client";

import { prisma } from "../../db/prisma.js";
import { AppError } from "../../utils/errors.js";
import { auditService } from "../audit/audit.service.js";

export const salesService = {
  async list(params: { ownerId: string; limit: number; offset: number }) {
    const [total, data] = await prisma.$transaction([
      prisma.sale.count({ where: { ownerId: params.ownerId, deletedAt: null } }),
      prisma.sale.findMany({
        where: { ownerId: params.ownerId, deletedAt: null },
        orderBy: { updatedAt: "desc" },
        take: params.limit,
        skip: params.offset,
      }),
    ]);

    return { total, data };
  },

  async getById(params: { ownerId: string; id: string }) {
    const sale = await prisma.sale.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!sale) throw new AppError("Sale not found", 404, "NOT_FOUND");
    return sale;
  },

  async create(params: {
    ownerId: string;
    userId: string;
    deviceId?: string;
    data: {
      customerId?: string | null;
      total: string;
      saleAt?: Date;
      note?: string | null;
    };
  }) {
    const now = new Date();
    const sale = await prisma.sale.create({
      data: {
        ownerId: params.ownerId,
        customerId: params.data.customerId ?? null,
        total: new Prisma.Decimal(params.data.total),
        saleAt: params.data.saleAt ?? now,
        note: params.data.note ?? null,
        createdAt: now,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "sales",
      entityId: sale.id,
      action: "CREATE",
      userId: params.userId,
      deviceId: params.deviceId,
    });

    return sale;
  },

  async update(params: {
    ownerId: string;
    userId: string;
    deviceId?: string;
    id: string;
    data: {
      customerId?: string | null;
      total?: string;
      saleAt?: Date;
      note?: string | null;
    };
  }) {
    const existing = await prisma.sale.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!existing) throw new AppError("Sale not found", 404, "NOT_FOUND");

    const now = new Date();

    const updated = await prisma.sale.update({
      where: { id: existing.id },
      data: {
        customerId: params.data.customerId,
        total:
          params.data.total !== undefined
            ? new Prisma.Decimal(params.data.total)
            : undefined,
        saleAt: params.data.saleAt,
        note: params.data.note,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "sales",
      entityId: updated.id,
      action: "UPDATE",
      userId: params.userId,
      deviceId: params.deviceId,
    });

    return updated;
  },

  async softDelete(params: {
    ownerId: string;
    userId: string;
    deviceId?: string;
    id: string;
  }) {
    const existing = await prisma.sale.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!existing) throw new AppError("Sale not found", 404, "NOT_FOUND");

    const now = new Date();
    const deleted = await prisma.sale.update({
      where: { id: existing.id },
      data: {
        deletedAt: now,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "sales",
      entityId: deleted.id,
      action: "DELETE",
      userId: params.userId,
      deviceId: params.deviceId,
    });

    return deleted;
  },
};
