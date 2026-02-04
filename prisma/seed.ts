import "dotenv/config";
import * as bcrypt from "bcryptjs";

import { prisma } from "../src/db/prisma.js";

const main = async () => {
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;
  const demoEmployeeUsername = (process.env.DEMO_EMPLOYEE_USERNAME ?? "demo").trim();
  const demoEmployeePassword = (process.env.DEMO_EMPLOYEE_PASSWORD ?? "Demo12345!").trim();

  if (!demoEmployeeUsername || !demoEmployeePassword) {
    throw new Error("Missing DEMO_EMPLOYEE_USERNAME or DEMO_EMPLOYEE_PASSWORD in environment");
  }

  const user = email && password
    ? await prisma.user.upsert({
        where: { email: email.toLowerCase() },
        update: { role: "ADMIN", deletedAt: null },
        create: {
          email: email.toLowerCase(),
          passwordHash: await bcrypt.hash(password, 12),
          role: "ADMIN",
        },
        select: { id: true, email: true },
      })
    : await prisma.user.findFirst({
        where: { deletedAt: null },
        orderBy: [{ role: "asc" }, { createdAt: "asc" }],
        select: { id: true, email: true },
      });

  if (!user) {
    throw new Error(
      "No users exist in the database. Set ADMIN_EMAIL and ADMIN_PASSWORD and rerun seed to create the initial admin user.",
    );
  }

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

  const desiredEmail = `employee+${demoEmployeeUsername}@fulltech.local`;

  const candidates = await prisma.employee.findMany({
    where: {
      ownerId: user.id,
      deletedAt: null,
      OR: [
        { username: { equals: demoEmployeeUsername, mode: "insensitive" } },
        { email: { equals: desiredEmail, mode: "insensitive" } },
        { name: { equals: "Usuario Demo", mode: "insensitive" } },
        { email: { endsWith: "@fulltech.local", mode: "insensitive" } },
      ],
    },
    take: 10,
    select: { id: true, username: true, email: true, name: true },
  });

  const exactMatch =
    candidates.find((e) => e.username?.toLowerCase() === demoEmployeeUsername.toLowerCase()) ??
    candidates.find((e) => (e.email ?? "").toLowerCase() === desiredEmail.toLowerCase());

  const byName = candidates.filter(
    (e) => (e.name ?? "").toLowerCase() === "usuario demo".toLowerCase(),
  );
  const byLocalEmail = candidates.filter(
    (e) => (e.email ?? "").toLowerCase().endsWith("@fulltech.local"),
  );

  const existingEmployee =
    exactMatch ??
    (byName.length === 1 ? byName[0] : undefined) ??
    (byLocalEmail.length === 1 ? byLocalEmail[0] : undefined);

  if (!existingEmployee) {
    await prisma.employee.create({
      data: {
        ownerId: user.id,
        name: "Usuario Demo",
        username: demoEmployeeUsername,
        role: "admin",
        email: desiredEmail,
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
        username: demoEmployeeUsername,
        role: "admin",
        email: desiredEmail,
        passwordLegacy: demoEmployeePassword,
        passwordHash: null,
        passwordSalt: null,
        blocked: false,
        updatedBy: user.id,
      },
    });
  }

  // eslint-disable-next-line no-console
  if (email && password) {
    console.log("Seeded/updated admin user:", { email: email.toLowerCase() });
  } else {
    console.log("Using existing owner user:", { email: user.email });
  }
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
