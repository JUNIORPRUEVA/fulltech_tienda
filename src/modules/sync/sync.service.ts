import { Prisma } from "@prisma/client";

import { prisma } from "../../db/prisma.js";
import { auditService } from "../audit/audit.service.js";
import type { BaseOp, SyncEntity } from "./sync.schemas.js";
import {
  customerPayloadSchema,
  productPayloadSchema,
  salePayloadSchema,
} from "./sync.schemas.js";

type PushResult = {
  opId: string;
  status: "OK" | "ERROR" | "CONFLICT";
  serverEntity?: unknown;
  message?: string;
};

const maxChangedAt = (updatedAt: Date, deletedAt: Date | null) => {
  if (!deletedAt) return updatedAt;
  return deletedAt > updatedAt ? deletedAt : updatedAt;
};

const parseClientUpdatedAt = (value: string) => new Date(value);

export const syncService = {
  async pushBatch(params: { userId: string; ops: BaseOp[] }) {
    const results: PushResult[] = [];

    for (const op of params.ops) {
      try {
        const clientUpdatedAt = parseClientUpdatedAt(op.clientUpdatedAt);
        if (Number.isNaN(clientUpdatedAt.getTime())) {
          results.push({
            opId: op.opId,
            status: "ERROR",
            message: "Invalid clientUpdatedAt",
          });
          continue;
        }

        const existingOp = await prisma.syncOp.findFirst({
          where: { id: op.opId, userId: params.userId },
        });

        if (existingOp) {
          const serverEntity = await this.getEntity({
            entity: op.entity,
            ownerId: params.userId,
            id: op.entityId,
          });

          results.push({ opId: op.opId, status: "OK", serverEntity });
          continue;
        }

        const now = new Date();

        const current = await this.getEntity({
          entity: op.entity,
          ownerId: params.userId,
          id: op.entityId,
          includeDeleted: true,
        });

        if (current) {
          const serverChangedAt = maxChangedAt(current.updatedAt, current.deletedAt);
          if (serverChangedAt > clientUpdatedAt) {
            await prisma.syncOp.create({
              data: {
                id: op.opId,
                userId: params.userId,
                deviceId: op.deviceId,
                entity: op.entity,
                entityId: op.entityId,
                type: op.type,
                clientUpdatedAt,
                status: "CONFLICT",
                processedAt: now,
                updatedBy: params.userId,
              },
            });

            results.push({
              opId: op.opId,
              status: "CONFLICT",
              serverEntity: current,
              message: "Server has newer data (server wins)",
            });
            continue;
          }
        }

        if (op.type === "DELETE") {
          const deleted = await this.applyDelete({
            entity: op.entity,
            ownerId: params.userId,
            userId: params.userId,
            deviceId: op.deviceId,
            id: op.entityId,
            now,
          });

          await prisma.syncOp.create({
            data: {
              id: op.opId,
              userId: params.userId,
              deviceId: op.deviceId,
              entity: op.entity,
              entityId: op.entityId,
              type: op.type,
              clientUpdatedAt,
              status: "OK",
              processedAt: now,
              updatedBy: params.userId,
            },
          });

          if (deleted) {
            await auditService.log({
              entity: op.entity,
              entityId: op.entityId,
              action: "SYNC_DELETE",
              userId: params.userId,
              deviceId: op.deviceId,
            });
          }

          results.push({ opId: op.opId, status: "OK", serverEntity: deleted ?? null });
          continue;
        }

        // UPSERT
        const upserted = await this.applyUpsert({
          entity: op.entity,
          ownerId: params.userId,
          userId: params.userId,
          deviceId: op.deviceId,
          id: op.entityId,
          payload: op.payload,
          now,
        });

        await prisma.syncOp.create({
          data: {
            id: op.opId,
            userId: params.userId,
            deviceId: op.deviceId,
            entity: op.entity,
            entityId: op.entityId,
            type: op.type,
            clientUpdatedAt,
            status: "OK",
            processedAt: now,
            updatedBy: params.userId,
          },
        });

        await auditService.log({
          entity: op.entity,
          entityId: op.entityId,
          action: "SYNC_UPSERT",
          userId: params.userId,
          deviceId: op.deviceId,
        });

        results.push({ opId: op.opId, status: "OK", serverEntity: upserted });
      } catch (e) {
        results.push({
          opId: op.opId,
          status: "ERROR",
          message: e instanceof Error ? e.message : "Unknown error",
        });
      }
    }

    return results;
  },

  async pull(params: { userId: string; since: Date }) {
    const [customers, products, sales] = await Promise.all([
      prisma.customer.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.product.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.sale.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
    ]);

    const serverTime = new Date().toISOString();

    return {
      serverTime,
      changes: { customers, products, sales },
    };
  },

  async getEntity(params: {
    entity: SyncEntity;
    ownerId: string;
    id: string;
    includeDeleted?: boolean;
  }) {
    const baseWhere = {
      ownerId: params.ownerId,
      id: params.id,
    } as const;

    const where =
      params.includeDeleted === true
        ? baseWhere
        : ({ ...baseWhere, deletedAt: null } as const);

    if (params.entity === "customers") {
      return prisma.customer.findFirst({ where });
    }
    if (params.entity === "products") {
      return prisma.product.findFirst({ where });
    }
    return prisma.sale.findFirst({ where });
  },

  async applyDelete(params: {
    entity: SyncEntity;
    ownerId: string;
    userId: string;
    deviceId?: string;
    id: string;
    now: Date;
  }) {
    const current = await this.getEntity({
      entity: params.entity,
      ownerId: params.ownerId,
      id: params.id,
      includeDeleted: true,
    });

    if (!current) return null;

    if (params.entity === "customers") {
      return prisma.customer.update({
        where: { id: current.id },
        data: {
          deletedAt: params.now,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "products") {
      return prisma.product.update({
        where: { id: current.id },
        data: {
          deletedAt: params.now,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    return prisma.sale.update({
      where: { id: current.id },
      data: {
        deletedAt: params.now,
        updatedAt: params.now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });
  },

  async applyUpsert(params: {
    entity: SyncEntity;
    ownerId: string;
    userId: string;
    deviceId?: string;
    id: string;
    payload: unknown;
    now: Date;
  }) {
    if (params.entity === "customers") {
      const payload = customerPayloadSchema.parse(params.payload);

      const existing = await prisma.customer.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });

      if (!existing) {
        return prisma.customer.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            name: payload.name,
            email: payload.email ?? null,
            phone: payload.phone ?? null,
            createdAt: params.now,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.customer.update({
        where: { id: existing.id },
        data: {
          name: payload.name,
          email: payload.email ?? null,
          phone: payload.phone ?? null,
          address: payload.address ?? null,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "products") {
      const payload = productPayloadSchema.parse(params.payload);

      const existing = await prisma.product.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });

      if (!existing) {
        return prisma.product.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            name: payload.name,
            sku: payload.sku ?? null,
            price: new Prisma.Decimal(payload.price),
            createdAt: params.now,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.product.update({
        where: { id: existing.id },
        data: {
          name: payload.name,
          sku: payload.sku ?? null,
          price: new Prisma.Decimal(payload.price),
          stock:
            payload.stock !== undefined
              ? new Prisma.Decimal(payload.stock)
              : undefined,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    const payload = salePayloadSchema.parse(params.payload);

    const existing = await prisma.sale.findFirst({
      where: { ownerId: params.ownerId, id: params.id },
    });

    if (!existing) {
      return prisma.sale.create({
        data: {
          id: params.id,
          ownerId: params.ownerId,
          customerId: payload.customerId ?? null,
          total: new Prisma.Decimal(payload.total),
          saleAt: payload.saleAt ?? params.now,
          note: payload.note ?? null,
          createdAt: params.now,
          updatedAt: params.now,
          deletedAt: null,
          version: 1,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    return prisma.sale.update({
      where: { id: existing.id },
      data: {
        customerId: payload.customerId ?? null,
        total: new Prisma.Decimal(payload.total),
        saleAt: payload.saleAt ?? existing.saleAt,
        note: payload.note ?? null,
        deletedAt: null,
        updatedAt: params.now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });
  },
};
