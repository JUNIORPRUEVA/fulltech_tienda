import "dotenv/config";
import bcrypt from "bcrypt";

import { prisma } from "../src/db/prisma.js";

const main = async () => {
  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;

  if (!email || !password) {
    throw new Error("Missing ADMIN_EMAIL or ADMIN_PASSWORD in environment");
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

  // eslint-disable-next-line no-console
  console.log("Seeded admin user:", { email });
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
