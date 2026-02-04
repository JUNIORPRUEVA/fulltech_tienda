import { beforeAll, afterAll, describe, expect, it } from "vitest";

import { api, resetDb } from "./testUtils.js";
import { prisma } from "../src/db/prisma.js";

describe("/sync/push", () => {
  beforeAll(async () => {
    await resetDb();
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it("applies UPSERT and returns OK", async () => {
    await api
      .post("/auth/register")
      .send({ email: "u2@test.com", password: "password123" })
      .expect(201);

    const loginRes = await api
      .post("/auth/login")
      .send({ email: "u2@test.com", password: "password123", deviceId: "dev1" })
      .expect(200);

    const accessToken = loginRes.body.accessToken as string;

    const pushRes = await api
      .post("/sync/push")
      .set("Authorization", `Bearer ${accessToken}`)
      .send([
        {
          opId: "00000000-0000-4000-8000-000000000101",
          entity: "customers",
          entityId: "00000000-0000-4000-8000-000000000201",
          type: "UPSERT",
          payload: { name: "Cliente Sync" },
          clientUpdatedAt: "2026-01-26T00:00:00.000Z",
          deviceId: "dev1",
        },
      ])
      .expect(200);

    expect(pushRes.body.results[0].status).toBe("OK");

    const customer = await prisma.customer.findUnique({
      where: { id: "00000000-0000-4000-8000-000000000201" },
    });

    expect(customer?.name).toBe("Cliente Sync");
  });
});
