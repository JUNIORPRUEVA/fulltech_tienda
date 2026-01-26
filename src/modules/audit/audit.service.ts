import { prisma } from "../../db/prisma.js";

export type AuditAction =
  | "CREATE"
  | "UPDATE"
  | "DELETE"
  | "SYNC_UPSERT"
  | "SYNC_DELETE";

export const auditService = {
  async log(params: {
    entity: string;
    entityId: string;
    action: AuditAction;
    userId: string;
    deviceId?: string;
    meta?: unknown;
  }) {
    await prisma.auditLog.create({
      data: {
        entity: params.entity,
        entityId: params.entityId,
        action: params.action,
        userId: params.userId,
        deviceId: params.deviceId,
        updatedBy: params.userId,
        meta: params.meta as any,
      },
    });
  },
};
