import { prisma } from "../../db/prisma.js";
import { AppError } from "../../utils/errors.js";
import { auditService } from "../audit/audit.service.js";

export const customersService = {
  async list(params: { ownerId: string; limit: number; offset: number }) {
    const [total, data] = await prisma.$transaction([
      prisma.customer.count({
        where: { ownerId: params.ownerId, deletedAt: null },
      }),
      prisma.customer.findMany({
        where: { ownerId: params.ownerId, deletedAt: null },
        orderBy: { updatedAt: "desc" },
        take: params.limit,
        skip: params.offset,
      }),
    ]);

    return { total, data };
  },

  async getById(params: { ownerId: string; id: string }) {
    const customer = await prisma.customer.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!customer) throw new AppError("Customer not found", 404, "NOT_FOUND");
    return customer;
  },

  async create(params: {
    ownerId: string;
    userId: string;
    deviceId?: string;
    data: { name: string; email?: string | null; phone?: string | null; address?: string | null };
  }) {
    const now = new Date();
    const customer = await prisma.customer.create({
      data: {
        ownerId: params.ownerId,
        name: params.data.name,
        email: params.data.email ?? null,
        phone: params.data.phone ?? null,
        address: params.data.address ?? null,
        createdAt: now,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "customers",
      entityId: customer.id,
      action: "CREATE",
      userId: params.userId,
      deviceId: params.deviceId,
    });

    return customer;
  },

  async update(params: {
    ownerId: string;
    userId: string;
    deviceId?: string;
    id: string;
    data: {
      name?: string;
      email?: string | null;
      phone?: string | null;
      address?: string | null;
    };
  }) {
    const existing = await prisma.customer.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!existing) throw new AppError("Customer not found", 404, "NOT_FOUND");

    const now = new Date();
    const updated = await prisma.customer.update({
      where: { id: existing.id },
      data: {
        ...params.data,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "customers",
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
    const existing = await prisma.customer.findFirst({
      where: { ownerId: params.ownerId, id: params.id, deletedAt: null },
    });
    if (!existing) throw new AppError("Customer not found", 404, "NOT_FOUND");

    const now = new Date();
    const deleted = await prisma.customer.update({
      where: { id: existing.id },
      data: {
        deletedAt: now,
        updatedAt: now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });

    await auditService.log({
      entity: "customers",
      entityId: deleted.id,
      action: "DELETE",
      userId: params.userId,
      deviceId: params.deviceId,
    });

    return deleted;
  },
};
