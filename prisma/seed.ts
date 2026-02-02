import "dotenv/config";
import * as bcrypt from "bcryptjs";

import { prisma } from "../src/db/prisma.js";

const main = async () => {
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;
  const demoEmployeeUsername = (process.env.DEMO_EMPLOYEE_USERNAME ?? "demo").trim();
  const demoEmployeePassword = (process.env.DEMO_EMPLOYEE_PASSWORD ?? "Demo12345!").trim();

  if (!email || !password) {
    throw new Error("Missing ADMIN_EMAIL or ADMIN_PASSWORD in environment");
  }
  if (!demoEmployeeUsername || !demoEmployeePassword) {
    throw new Error("Missing DEMO_EMPLOYEE_USERNAME or DEMO_EMPLOYEE_PASSWORD in environment");
  }

  const passwordHash = await bcrypt.hash(password, 12);

  const user = await prisma.user.upsert({
    where: { email: email.toLowerCase() },
    update: { role: "ADMIN" },
    create: { email: email.toLowerCase(), passwordHash, role: "ADMIN" },
  });

  await prisma.customer.createMany({
    data: [
      { ownerId: user.id, name: "Cliente Demo", email: "demo@cliente.com" },
      { ownerId: user.id, name: "Cliente 2", phone: "+51 999 999 999" },
    ],
    skipDuplicates: true,
  });

  await prisma.product.createMany({
    data: [
      {
        ownerId: user.id,
        name: "Producto Demo",
        sku: "SKU-001",
        price: "10.50",
        stock: "100.00",
      },
      {
        ownerId: user.id,
        name: "Cable USB",
        sku: "USB-001",
        price: "5.00",
        stock: "250.00",
      },
      {
        ownerId: user.id,
        name: "Cargador 20W",
        sku: "CHR-020",
        price: "25.00",
        stock: "50.00",
      },
    ],
    skipDuplicates: true,
  });

  // Note: Sales depend on your app logic; keep seed minimal.

  const existingEmployee = await prisma.employee.findFirst({
    where: {
      ownerId: user.id,
      deletedAt: null,
      username: { equals: demoEmployeeUsername, mode: "insensitive" },
    },
    select: { id: true },
  });

  if (!existingEmployee) {
    await prisma.employee.create({
      data: {
        ownerId: user.id,
        name: "Usuario Demo",
        username: demoEmployeeUsername,
        role: "admin",
        email: `employee+${demoEmployeeUsername}@fulltech.local`,
        passwordLegacy: demoEmployeePassword,
        blocked: false,
        lastLoginAt: null,
        updatedBy: user.id,
      },
    });
  } else {
    await prisma.employee.update({
      where: { id: existingEmployee.id },
      data: {
        name: "Usuario Demo",
        role: "admin",
        email: `employee+${demoEmployeeUsername}@fulltech.local`,
        passwordLegacy: demoEmployeePassword,
        passwordHash: null,
        passwordSalt: null,
        blocked: false,
        updatedBy: user.id,
      },
    });
  }

  // eslint-disable-next-line no-console
  console.log("Seeded admin user:", { email });
  // eslint-disable-next-line no-console
  console.log("Seeded demo employee:", { username: demoEmployeeUsername });
};

main()
  .catch(async (e) => {
    // eslint-disable-next-line no-console
    console.error(e);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
