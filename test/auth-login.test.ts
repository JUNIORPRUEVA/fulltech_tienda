import { beforeAll, afterAll, describe, expect, it } from "vitest";

import { api, resetDb } from "./testUtils.js";
import { prisma } from "../src/db/prisma.js";

describe("/auth/login", () => {
  beforeAll(async () => {
    await resetDb();
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it("logs in and returns accessToken", async () => {
    await api
      .post("/auth/register")
      .send({ email: "u1@test.com", password: "password123" })
      .expect(201);

    const res = await api
      .post("/auth/login")
      .send({ email: "u1@test.com", password: "password123", deviceId: "test" })
      .expect(200);

    expect(res.body.accessToken).toBeTypeOf("string");
    expect(res.body.accessToken.length).toBeGreaterThan(10);
    expect(res.body.refreshToken).toBeTypeOf("string");
  });
});
