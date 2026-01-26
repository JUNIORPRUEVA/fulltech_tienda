import request from "supertest";

import { createApp } from "../src/app.js";
import { prisma } from "../src/db/prisma.js";

export const app = createApp();

export const resetDb = async () => {
  // Order matters due to FK constraints.
  await prisma.syncOp.deleteMany();
  await prisma.auditLog.deleteMany();
  await prisma.refreshToken.deleteMany();
  await prisma.sale.deleteMany();
  await prisma.product.deleteMany();
  await prisma.customer.deleteMany();
  await prisma.user.deleteMany();
};

export const api = request(app);
