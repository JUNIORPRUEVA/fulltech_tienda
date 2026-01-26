import { Prisma } from "@prisma/client";

import { prisma } from "../../db/prisma.js";
import { AppError } from "../../utils/errors.js";
import { auditService } from "../audit/audit.service.js";

export const productsService = {
  async list(params: { ownerId: string; limit: number; offset: number }) {
    const [total, data] = await prisma.$transaction([
      prisma.product.count({ where: { ownerId: params.ownerId, deletedAt: null } }),
      prisma.product.findMany({
        where: { ownerId: params.ownerId, deletedAt: null },
        orderBy: { updatedAt: "desc" },
        take: params.limit,
        skip: params.offset,
      }),
    ]);

    return { total, data };
  },

  async getById(params: { ownerId: string; id: string }) {
    const product = await prisma.product.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!product) throw new AppError("Product not found", 404, "NOT_FOUND");
    return product;
  },

  async create(params: {
    ownerId: string;
    userId: string;
    deviceId?: string;
    data: { name: string; sku?: string | null; price: string; stock?: string };
  }) {
    const now = new Date();
    const product = await prisma.product.create({
      data: {
        ownerId: params.ownerId,
        name: params.data.name,
        sku: params.data.sku ?? null,
        price: new Prisma.Decimal(params.data.price),
        stock:
          params.data.stock !== undefined
            ? new Prisma.Decimal(params.data.stock)
            : undefined,
        createdAt: now,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "products",
      entityId: product.id,
      action: "CREATE",
      userId: params.userId,
      deviceId: params.deviceId,
    });

    return product;
  },

  async update(params: {
    ownerId: string;
    userId: string;
    deviceId?: string;
    id: string;
    data: { name?: string; sku?: string | null; price?: string; stock?: string };
  }) {
    const existing = await prisma.product.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!existing) throw new AppError("Product not found", 404, "NOT_FOUND");

    const now = new Date();

    const updated = await prisma.product.update({
      where: { id: existing.id },
      data: {
        name: params.data.name,
        sku: params.data.sku,
        price:
          params.data.price !== undefined
            ? new Prisma.Decimal(params.data.price)
            : undefined,
        stock:
          params.data.stock !== undefined
            ? new Prisma.Decimal(params.data.stock)
            : undefined,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "products",
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
    const existing = await prisma.product.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!existing) throw new AppError("Product not found", 404, "NOT_FOUND");

    const now = new Date();
    const deleted = await prisma.product.update({
      where: { id: existing.id },
      data: {
        deletedAt: now,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "products",
      entityId: deleted.id,
      action: "DELETE",
      userId: params.userId,
      deviceId: params.deviceId,
    });

    return deleted;
  },
};
