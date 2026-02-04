import "dotenv/config";

import { prisma } from "../src/db/prisma.js";

const main = async () => {
  const users = await prisma.user.count({ where: { deletedAt: null } });
  const employees = await prisma.employee.count({ where: { deletedAt: null } });
  const employee = await prisma.employee.findFirst({
    where: { deletedAt: null },
    select: { id: true, username: true, email: true, ownerId: true },
  });

  // eslint-disable-next-line no-console
  console.log({ users, employees, employee });
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
