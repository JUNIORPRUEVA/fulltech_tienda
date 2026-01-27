import { Prisma } from "@prisma/client";

import { prisma } from "../../db/prisma.js";
import { auditService } from "../audit/audit.service.js";
import type { BaseOp, SyncEntity } from "./sync.schemas.js";
import {
  customerPayloadSchema,
  productPayloadSchema,
  salePayloadSchema,
  saleItemPayloadSchema,
  quotePayloadSchema,
  quoteItemPayloadSchema,
  employeePayloadSchema,
  employeeLoginPayloadSchema,
  technicianPayloadSchema,
  operationPayloadSchema,
  operationMaterialPayloadSchema,
  operationEvidencePayloadSchema,
  operationNotePayloadSchema,
  operationStatusPayloadSchema,
  payrollAdjustmentPayloadSchema,
  payrollPaymentPayloadSchema,
  punchPayloadSchema,
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
    const [
      customers,
      products,
      sales,
      saleItems,
      quotes,
      quoteItems,
      employees,
      employeeLogins,
      technicians,
      operations,
      operationMaterials,
      operationEvidences,
      operationNotes,
      operationStatuses,
      payrollAdjustments,
      payrollPayments,
      punches,
    ] = await Promise.all([
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
      prisma.saleItem.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.quote.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.quoteItem.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.employee.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.employeeLogin.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.technician.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.operation.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.operationMaterial.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.operationEvidence.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.operationNote.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.operationStatusHistory.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.payrollAdjustment.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.payrollPayment.findMany({
        where: {
          ownerId: params.userId,
          OR: [{ updatedAt: { gt: params.since } }, { deletedAt: { gt: params.since } }],
        },
        orderBy: { updatedAt: "asc" },
      }),
      prisma.punch.findMany({
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
      changes: {
        customers,
        products,
        sales,
        saleItems,
        quotes,
        quoteItems,
        employees,
        employeeLogins,
        technicians,
        operations,
        operationMaterials,
        operationEvidences,
        operationNotes,
        operationStatuses,
        payrollAdjustments,
        payrollPayments,
        punches,
      },
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

    if (params.entity === "customers") return prisma.customer.findFirst({ where });
    if (params.entity === "products") return prisma.product.findFirst({ where });
    if (params.entity === "sales") return prisma.sale.findFirst({ where });
    if (params.entity === "sale_items") return prisma.saleItem.findFirst({ where });
    if (params.entity === "quotes") return prisma.quote.findFirst({ where });
    if (params.entity === "quote_items") return prisma.quoteItem.findFirst({ where });
    if (params.entity === "employees") return prisma.employee.findFirst({ where });
    if (params.entity === "employee_logins")
      return prisma.employeeLogin.findFirst({ where });
    if (params.entity === "technicians") return prisma.technician.findFirst({ where });
    if (params.entity === "operations") return prisma.operation.findFirst({ where });
    if (params.entity === "operation_materials")
      return prisma.operationMaterial.findFirst({ where });
    if (params.entity === "operation_evidences")
      return prisma.operationEvidence.findFirst({ where });
    if (params.entity === "operation_notes") return prisma.operationNote.findFirst({ where });
    if (params.entity === "operation_statuses")
      return prisma.operationStatusHistory.findFirst({ where });
    if (params.entity === "payroll_adjustments")
      return prisma.payrollAdjustment.findFirst({ where });
    if (params.entity === "payroll_payments")
      return prisma.payrollPayment.findFirst({ where });
    return prisma.punch.findFirst({ where });
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

    const data = {
      deletedAt: params.now,
      updatedAt: params.now,
      updatedBy: params.userId,
      deviceId: params.deviceId,
    };

    if (params.entity === "customers") return prisma.customer.update({ where: { id: current.id }, data });
    if (params.entity === "products") return prisma.product.update({ where: { id: current.id }, data });
    if (params.entity === "sales") return prisma.sale.update({ where: { id: current.id }, data });
    if (params.entity === "sale_items") return prisma.saleItem.update({ where: { id: current.id }, data });
    if (params.entity === "quotes") return prisma.quote.update({ where: { id: current.id }, data });
    if (params.entity === "quote_items") return prisma.quoteItem.update({ where: { id: current.id }, data });
    if (params.entity === "employees") return prisma.employee.update({ where: { id: current.id }, data });
    if (params.entity === "employee_logins")
      return prisma.employeeLogin.update({ where: { id: current.id }, data });
    if (params.entity === "technicians")
      return prisma.technician.update({ where: { id: current.id }, data });
    if (params.entity === "operations")
      return prisma.operation.update({ where: { id: current.id }, data });
    if (params.entity === "operation_materials")
      return prisma.operationMaterial.update({ where: { id: current.id }, data });
    if (params.entity === "operation_evidences")
      return prisma.operationEvidence.update({ where: { id: current.id }, data });
    if (params.entity === "operation_notes")
      return prisma.operationNote.update({ where: { id: current.id }, data });
    if (params.entity === "operation_statuses")
      return prisma.operationStatusHistory.update({ where: { id: current.id }, data });
    if (params.entity === "payroll_adjustments")
      return prisma.payrollAdjustment.update({ where: { id: current.id }, data });
    if (params.entity === "payroll_payments")
      return prisma.payrollPayment.update({ where: { id: current.id }, data });
    return prisma.punch.update({ where: { id: current.id }, data });
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
            address: payload.address ?? null,
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
            stock:
              payload.stock !== undefined
                ? new Prisma.Decimal(payload.stock)
                : new Prisma.Decimal(0),
            imageUrl: payload.imageUrl ?? null,
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
          imageUrl: payload.imageUrl !== undefined ? payload.imageUrl : undefined,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "employees") {
      const payload = employeePayloadSchema.parse(params.payload);
      const existing = await prisma.employee.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });

      const createdAt = payload.createdAt ?? params.now;
      const salary =
        payload.salaryBiweekly == null
          ? null
          : new Prisma.Decimal(payload.salaryBiweekly);
      const goal =
        payload.goalBiweekly == null ? null : new Prisma.Decimal(payload.goalBiweekly);

      if (!existing) {
        return prisma.employee.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            name: payload.name,
            username: payload.username ?? null,
            role: payload.role,
            email: payload.email ?? null,
            passwordLegacy: payload.passwordLegacy ?? null,
            passwordHash: payload.passwordHash ?? null,
            passwordSalt: payload.passwordSalt ?? null,
            cedula: payload.cedula ?? null,
            address: payload.address ?? null,
            salaryBiweekly: salary,
            goalBiweekly: goal,
            employeeOfMonth: payload.employeeOfMonth ?? false,
            hireDate: payload.hireDate ?? null,
            curriculumPath: payload.curriculumPath ?? null,
            licensePath: payload.licensePath ?? null,
            idCardPhotoPath: payload.idCardPhotoPath ?? null,
            lastJobPath: payload.lastJobPath ?? null,
            blocked: payload.blocked ?? false,
            lastLoginAt: payload.lastLoginAt ?? null,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.employee.update({
        where: { id: existing.id },
        data: {
          name: payload.name,
          username: payload.username ?? null,
          role: payload.role,
          email: payload.email ?? null,
          passwordLegacy: payload.passwordLegacy ?? null,
          passwordHash: payload.passwordHash ?? null,
          passwordSalt: payload.passwordSalt ?? null,
          cedula: payload.cedula ?? null,
          address: payload.address ?? null,
          salaryBiweekly: salary,
          goalBiweekly: goal,
          employeeOfMonth: payload.employeeOfMonth ?? existing.employeeOfMonth,
          hireDate: payload.hireDate ?? null,
          curriculumPath: payload.curriculumPath ?? null,
          licensePath: payload.licensePath ?? null,
          idCardPhotoPath: payload.idCardPhotoPath ?? null,
          lastJobPath: payload.lastJobPath ?? null,
          blocked: payload.blocked ?? existing.blocked,
          lastLoginAt: payload.lastLoginAt ?? null,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "employee_logins") {
      const payload = employeeLoginPayloadSchema.parse(params.payload);
      const existing = await prisma.employeeLogin.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.employeeLogin.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            employeeId: payload.employeeId,
            time: payload.time,
            success: payload.success,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.employeeLogin.update({
        where: { id: existing.id },
        data: {
          employeeId: payload.employeeId,
          time: payload.time,
          success: payload.success,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "technicians") {
      const payload = technicianPayloadSchema.parse(params.payload);
      const existing = await prisma.technician.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;
      const updatedAt = payload.updatedAt ?? params.now;

      if (!existing) {
        return prisma.technician.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            name: payload.name,
            phone: payload.phone ?? null,
            specialty: payload.specialty,
            status: payload.status,
            createdAt,
            updatedAt,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.technician.update({
        where: { id: existing.id },
        data: {
          name: payload.name,
          phone: payload.phone ?? null,
          specialty: payload.specialty,
          status: payload.status,
          deletedAt: null,
          updatedAt,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "operations") {
      const payload = operationPayloadSchema.parse(params.payload);
      const existing = await prisma.operation.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });

      const createdAt = payload.createdAt ?? params.now;
      const updatedAt = payload.updatedAt ?? params.now;
      const amount =
        payload.amount == null ? null : new Prisma.Decimal(payload.amount);
      const paid =
        payload.paymentPaidAmount == null
          ? null
          : new Prisma.Decimal(payload.paymentPaidAmount);

      if (!existing) {
        return prisma.operation.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            customerId: payload.customerId ?? null,
            code: payload.code,
            title: payload.title ?? null,
            serviceType: payload.serviceType,
            priority: payload.priority,
            status: payload.status,
            technicianId: payload.technicianId ?? null,
            technicianEmployeeId: payload.technicianEmployeeId ?? null,
            scheduledAt: payload.scheduledAt ?? null,
            estimatedTime: payload.estimatedTime ?? null,
            serviceAddress: payload.serviceAddress ?? null,
            locationRef: payload.locationRef ?? null,
            description: payload.description ?? null,
            initialObservations: payload.initialObservations ?? null,
            finalObservations: payload.finalObservations ?? null,
            amount,
            paymentMethod: payload.paymentMethod ?? null,
            paymentStatus: payload.paymentStatus ?? null,
            paymentPaidAmount: paid,
            chkArrived: payload.chkArrived ?? false,
            chkMaterialInstalled: payload.chkMaterialInstalled ?? false,
            chkSystemTested: payload.chkSystemTested ?? false,
            chkClientTrained: payload.chkClientTrained ?? false,
            chkWorkCompleted: payload.chkWorkCompleted ?? false,
            warrantyType: payload.warrantyType ?? null,
            warrantyExpiresAt: payload.warrantyExpiresAt ?? null,
            finishedAt: payload.finishedAt ?? null,
            createdAt,
            updatedAt,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.operation.update({
        where: { id: existing.id },
        data: {
          customerId: payload.customerId ?? null,
          code: payload.code,
          title: payload.title ?? null,
          serviceType: payload.serviceType,
          priority: payload.priority,
          status: payload.status,
          technicianId: payload.technicianId ?? null,
          technicianEmployeeId: payload.technicianEmployeeId ?? null,
          scheduledAt: payload.scheduledAt ?? null,
          estimatedTime: payload.estimatedTime ?? null,
          serviceAddress: payload.serviceAddress ?? null,
          locationRef: payload.locationRef ?? null,
          description: payload.description ?? null,
          initialObservations: payload.initialObservations ?? null,
          finalObservations: payload.finalObservations ?? null,
          amount,
          paymentMethod: payload.paymentMethod ?? null,
          paymentStatus: payload.paymentStatus ?? null,
          paymentPaidAmount: paid,
          chkArrived: payload.chkArrived ?? existing.chkArrived,
          chkMaterialInstalled:
            payload.chkMaterialInstalled ?? existing.chkMaterialInstalled,
          chkSystemTested: payload.chkSystemTested ?? existing.chkSystemTested,
          chkClientTrained: payload.chkClientTrained ?? existing.chkClientTrained,
          chkWorkCompleted: payload.chkWorkCompleted ?? existing.chkWorkCompleted,
          warrantyType: payload.warrantyType ?? null,
          warrantyExpiresAt: payload.warrantyExpiresAt ?? null,
          finishedAt: payload.finishedAt ?? null,
          deletedAt: null,
          updatedAt,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "operation_materials") {
      const payload = operationMaterialPayloadSchema.parse(params.payload);
      const existing = await prisma.operationMaterial.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.operationMaterial.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            operationId: payload.operationId,
            name: payload.name,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.operationMaterial.update({
        where: { id: existing.id },
        data: {
          operationId: payload.operationId,
          name: payload.name,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "operation_evidences") {
      const payload = operationEvidencePayloadSchema.parse(params.payload);
      const existing = await prisma.operationEvidence.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.operationEvidence.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            operationId: payload.operationId,
            type: payload.type,
            filePath: payload.filePath,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.operationEvidence.update({
        where: { id: existing.id },
        data: {
          operationId: payload.operationId,
          type: payload.type,
          filePath: payload.filePath,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "operation_notes") {
      const payload = operationNotePayloadSchema.parse(params.payload);
      const existing = await prisma.operationNote.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.operationNote.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            operationId: payload.operationId,
            employeeId: payload.employeeId ?? null,
            note: payload.note,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.operationNote.update({
        where: { id: existing.id },
        data: {
          operationId: payload.operationId,
          employeeId: payload.employeeId ?? null,
          note: payload.note,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "operation_statuses") {
      const payload = operationStatusPayloadSchema.parse(params.payload);
      const existing = await prisma.operationStatusHistory.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.operationStatusHistory.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            operationId: payload.operationId,
            fromStatus: payload.fromStatus ?? null,
            toStatus: payload.toStatus,
            employeeId: payload.employeeId ?? null,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.operationStatusHistory.update({
        where: { id: existing.id },
        data: {
          operationId: payload.operationId,
          fromStatus: payload.fromStatus ?? null,
          toStatus: payload.toStatus,
          employeeId: payload.employeeId ?? null,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "quotes") {
      const payload = quotePayloadSchema.parse(params.payload);
      const existing = await prisma.quote.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.quote.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            customerId: payload.customerId ?? null,
            code: payload.code ?? null,
            total: new Prisma.Decimal(payload.total),
            currency: payload.currency,
            status: payload.status,
            notes: payload.notes ?? null,
            itbisActive: payload.itbisActive,
            itbisRate: new Prisma.Decimal(payload.itbisRate),
            discountGlobal: new Prisma.Decimal(payload.discountGlobal),
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.quote.update({
        where: { id: existing.id },
        data: {
          customerId: payload.customerId ?? null,
          code: payload.code ?? null,
          total: new Prisma.Decimal(payload.total),
          currency: payload.currency,
          status: payload.status,
          notes: payload.notes ?? null,
          itbisActive: payload.itbisActive,
          itbisRate: new Prisma.Decimal(payload.itbisRate),
          discountGlobal: new Prisma.Decimal(payload.discountGlobal),
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "quote_items") {
      const payload = quoteItemPayloadSchema.parse(params.payload);
      const existing = await prisma.quoteItem.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.quoteItem.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            quoteId: payload.quoteId,
            productId: payload.productId ?? null,
            code: payload.code ?? null,
            name: payload.name,
            price: new Prisma.Decimal(payload.price),
            qty: new Prisma.Decimal(payload.qty),
            discount: new Prisma.Decimal(payload.discount),
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.quoteItem.update({
        where: { id: existing.id },
        data: {
          quoteId: payload.quoteId,
          productId: payload.productId ?? null,
          code: payload.code ?? null,
          name: payload.name,
          price: new Prisma.Decimal(payload.price),
          qty: new Prisma.Decimal(payload.qty),
          discount: new Prisma.Decimal(payload.discount),
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "sale_items") {
      const payload = saleItemPayloadSchema.parse(params.payload);
      const existing = await prisma.saleItem.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.saleItem.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            saleId: payload.saleId,
            productId: payload.productId ?? null,
            code: payload.code ?? null,
            name: payload.name,
            qty: new Prisma.Decimal(payload.qty),
            price: new Prisma.Decimal(payload.price),
            cost: new Prisma.Decimal(payload.cost),
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.saleItem.update({
        where: { id: existing.id },
        data: {
          saleId: payload.saleId,
          productId: payload.productId ?? null,
          code: payload.code ?? null,
          name: payload.name,
          qty: new Prisma.Decimal(payload.qty),
          price: new Prisma.Decimal(payload.price),
          cost: new Prisma.Decimal(payload.cost),
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "payroll_adjustments") {
      const payload = payrollAdjustmentPayloadSchema.parse(params.payload);
      const existing = await prisma.payrollAdjustment.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.payrollAdjustment.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            employeeId: payload.employeeId,
            periodStart: payload.periodStart,
            periodEnd: payload.periodEnd,
            type: payload.type,
            amount: new Prisma.Decimal(payload.amount),
            note: payload.note ?? null,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.payrollAdjustment.update({
        where: { id: existing.id },
        data: {
          employeeId: payload.employeeId,
          periodStart: payload.periodStart,
          periodEnd: payload.periodEnd,
          type: payload.type,
          amount: new Prisma.Decimal(payload.amount),
          note: payload.note ?? null,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "payroll_payments") {
      const payload = payrollPaymentPayloadSchema.parse(params.payload);
      const existing = await prisma.payrollPayment.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.payrollPayment.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            employeeId: payload.employeeId,
            periodStart: payload.periodStart,
            periodEnd: payload.periodEnd,
            paidAt: payload.paidAt,
            baseSalary: new Prisma.Decimal(payload.baseSalary),
            commission: new Prisma.Decimal(payload.commission),
            adjustments: new Prisma.Decimal(payload.adjustments),
            net: new Prisma.Decimal(payload.net),
            status: payload.status,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.payrollPayment.update({
        where: { id: existing.id },
        data: {
          employeeId: payload.employeeId,
          periodStart: payload.periodStart,
          periodEnd: payload.periodEnd,
          paidAt: payload.paidAt,
          baseSalary: new Prisma.Decimal(payload.baseSalary),
          commission: new Prisma.Decimal(payload.commission),
          adjustments: new Prisma.Decimal(payload.adjustments),
          net: new Prisma.Decimal(payload.net),
          status: payload.status,
          deletedAt: null,
          updatedAt: params.now,
          updatedBy: params.userId,
          deviceId: params.deviceId,
        },
      });
    }

    if (params.entity === "punches") {
      const payload = punchPayloadSchema.parse(params.payload);
      const existing = await prisma.punch.findFirst({
        where: { ownerId: params.ownerId, id: params.id },
      });
      const createdAt = payload.createdAt ?? params.now;

      if (!existing) {
        return prisma.punch.create({
          data: {
            id: params.id,
            ownerId: params.ownerId,
            employeeId: payload.employeeId ?? null,
            type: payload.type,
            time: payload.time,
            location: payload.location ?? null,
            createdAt,
            updatedAt: params.now,
            deletedAt: null,
            version: 1,
            updatedBy: params.userId,
            deviceId: params.deviceId,
          },
        });
      }

      return prisma.punch.update({
        where: { id: existing.id },
        data: {
          employeeId: payload.employeeId ?? null,
          type: payload.type,
          time: payload.time,
          location: payload.location ?? null,
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
    const createdAt = payload.createdAt ?? params.now;
    const saleAt = payload.saleAt ?? createdAt;
    const profit =
      payload.profit === undefined ? undefined : new Prisma.Decimal(payload.profit);
    const points =
      payload.points === undefined ? undefined : new Prisma.Decimal(payload.points);

    if (!existing) {
      return prisma.sale.create({
        data: {
          id: params.id,
          ownerId: params.ownerId,
          customerId: payload.customerId ?? null,
          employeeId: payload.employeeId ?? null,
          code: payload.code ?? null,
          total: new Prisma.Decimal(payload.total),
          profit: profit ?? new Prisma.Decimal(0),
          points: points ?? new Prisma.Decimal(0),
          currency: payload.currency ?? "DOP",
          saleAt,
          note: payload.note ?? null,
          createdAt,
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
        employeeId: payload.employeeId ?? null,
        code: payload.code ?? null,
        total: new Prisma.Decimal(payload.total),
        profit,
        points,
        currency: payload.currency ?? existing.currency,
        saleAt,
        note: payload.note ?? null,
        deletedAt: null,
        updatedAt: params.now,
        updatedBy: params.userId,
        deviceId: params.deviceId,
      },
    });
  },

};
