import "dotenv/config";

import { prisma } from "../src/db/prisma.js";

const must = (name: string, value: string | undefined) => {
  const v = (value ?? "").trim();
  if (!v) {
    throw new Error(`Missing env var ${name}`);
  }
  return v;
};

const main = async () => {
  const keepUsername = must(
    "KEEP_EMPLOYEE_USERNAME",
    process.env.KEEP_EMPLOYEE_USERNAME,
  );

  const confirm = (process.env.PURGE_CONFIRM ?? "").trim().toUpperCase();
  if (confirm !== "YES") {
    throw new Error(
      "Refusing to run. Set PURGE_CONFIRM=YES to confirm destructive purge.",
    );
  }

  const matches = await prisma.employee.findMany({
    where: {
      deletedAt: null,
      username: { equals: keepUsername, mode: "insensitive" },
    },
    select: { id: true, ownerId: true, username: true, email: true },
    take: 10,
  });

  if (matches.length === 0) {
    throw new Error(
      `No employee found with username '${keepUsername}'. Aborting.`,
    );
  }

  const ownerIds = new Set(matches.map((e) => e.ownerId));
  if (ownerIds.size !== 1) {
    throw new Error(
      `Ambiguous: username '${keepUsername}' exists under multiple owners. Aborting.`,
    );
  }

  const keepEmployee = matches[0];
  const keepOwnerId = keepEmployee.ownerId;

  const [userCount, employeeCount] = await Promise.all([
    prisma.user.count({ where: { deletedAt: null } }),
    prisma.employee.count({ where: { deletedAt: null } }),
  ]);

  // eslint-disable-next-line no-console
  console.log("Purge plan:");
  // eslint-disable-next-line no-console
  console.log("- Keep employee:", {
    id: keepEmployee.id,
    username: keepEmployee.username,
    email: keepEmployee.email,
    ownerId: keepOwnerId,
  });
  // eslint-disable-next-line no-console
  console.log("- Current counts:", { users: userCount, employees: employeeCount });

  await prisma.$transaction(async (tx) => {
    // Remove all other employees (including those under the kept owner).
    await tx.employee.deleteMany({
      where: { id: { not: keepEmployee.id } },
    });

    // Remove all other users/owners. Cascades will remove their data.
    await tx.user.deleteMany({
      where: { id: { not: keepOwnerId } },
    });

    // Ensure the kept owner is not soft-deleted.
    await tx.user.update({
      where: { id: keepOwnerId },
      data: { deletedAt: null },
    });
  });

  const [userCountAfter, employeeCountAfter] = await Promise.all([
    prisma.user.count({ where: { deletedAt: null } }),
    prisma.employee.count({ where: { deletedAt: null } }),
  ]);

  // eslint-disable-next-line no-console
  console.log("Purge complete.");
  // eslint-disable-next-line no-console
  console.log("- Remaining counts:", {
    users: userCountAfter,
    employees: employeeCountAfter,
  });
};

main()
  .catch((e) => {
    // eslint-disable-next-line no-console
    console.error(e);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
