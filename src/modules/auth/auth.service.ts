import * as bcrypt from "bcryptjs";
import jwt, { type JwtPayload, type SignOptions } from "jsonwebtoken";
import { randomUUID, createHash } from "node:crypto";

import { prisma } from "../../db/prisma.js";
import { env } from "../../config/env.js";
import { AppError } from "../../utils/errors.js";

const sha256 = (value: string) =>
  createHash("sha256").update(value, "utf8").digest("hex");

export const authService = {
  async register(email: string, password: string) {
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) {
      throw new AppError("Email already in use", 409, "EMAIL_IN_USE");
    }

    const passwordHash = await bcrypt.hash(password, 12);

    const user = await prisma.user.create({
      data: { email, passwordHash },
      select: { id: true, email: true, createdAt: true },
    });

    return user;
  },

  async login(email: string, password: string, deviceId?: string) {
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) throw new AppError("Invalid credentials", 401, "UNAUTHORIZED");

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) throw new AppError("Invalid credentials", 401, "UNAUTHORIZED");

    const accessToken = jwt.sign(
      {},
      env.JWT_ACCESS_SECRET,
      {
        subject: user.id,
        expiresIn: env.JWT_ACCESS_EXPIRES_IN as SignOptions["expiresIn"],
      } satisfies SignOptions,
    );

    const refreshJti = randomUUID();
    const refreshToken = jwt.sign(
      { jti: refreshJti },
      env.JWT_REFRESH_SECRET,
      {
        subject: user.id,
        expiresIn: env.JWT_REFRESH_EXPIRES_IN as SignOptions["expiresIn"],
      } satisfies SignOptions,
    );

    await prisma.refreshToken.create({
      data: {
        id: refreshJti,
        userId: user.id,
        tokenHash: sha256(refreshToken),
        deviceId,
        updatedBy: user.id,
      },
    });

    return { accessToken, refreshToken };
  },

  async loginEmployee(username: string, password: string, deviceId?: string) {
    const input = username.trim();
    if (!input) {
      throw new AppError("Invalid credentials", 401, "UNAUTHORIZED");
    }

    const employees = await prisma.employee.findMany({
      where: {
        deletedAt: null,
        OR: [
          { username: { equals: input, mode: "insensitive" } },
          { email: { equals: input, mode: "insensitive" } },
        ],
      },
      take: 3,
      select: {
        id: true,
        ownerId: true,
        blocked: true,
        passwordHash: true,
        passwordSalt: true,
        passwordLegacy: true,
        name: true,
        username: true,
        email: true,
        role: true,
      },
    });

    if (employees.length === 0) {
      throw new AppError("Invalid credentials", 401, "UNAUTHORIZED");
    }

    const ownerIds = new Set(employees.map((e) => e.ownerId));
    if (ownerIds.size > 1) {
      throw new AppError(
        "Multiple accounts found. Contact admin.",
        409,
        "AMBIGUOUS_USER",
      );
    }

    const employee = employees[0];

    if (employee.blocked) {
      await prisma.employeeLogin.create({
        data: {
          ownerId: employee.ownerId,
          employeeId: employee.id,
          time: new Date(),
          success: false,
          deviceId,
          updatedBy: employee.ownerId,
        },
      });
      throw new AppError("User blocked", 403, "BLOCKED");
    }

    let ok = false;
    const salt = employee.passwordSalt?.trim();
    const hash = employee.passwordHash?.trim();
    if (salt && hash) {
      ok = sha256(`${salt}:${password}`) === hash;
    } else if (employee.passwordLegacy?.trim()) {
      ok = employee.passwordLegacy.trim() === password;
    }

    if (!ok) {
      await prisma.employeeLogin.create({
        data: {
          ownerId: employee.ownerId,
          employeeId: employee.id,
          time: new Date(),
          success: false,
          deviceId,
          updatedBy: employee.ownerId,
        },
      });
      throw new AppError("Invalid credentials", 401, "UNAUTHORIZED");
    }

    await prisma.employeeLogin.create({
      data: {
        ownerId: employee.ownerId,
        employeeId: employee.id,
        time: new Date(),
        success: true,
        deviceId,
        updatedBy: employee.ownerId,
      },
    });

    const accessToken = jwt.sign(
      {},
      env.JWT_ACCESS_SECRET,
      {
        subject: employee.ownerId,
        expiresIn: env.JWT_ACCESS_EXPIRES_IN as SignOptions["expiresIn"],
      } satisfies SignOptions,
    );

    const refreshJti = randomUUID();
    const refreshToken = jwt.sign(
      { jti: refreshJti },
      env.JWT_REFRESH_SECRET,
      {
        subject: employee.ownerId,
        expiresIn: env.JWT_REFRESH_EXPIRES_IN as SignOptions["expiresIn"],
      } satisfies SignOptions,
    );

    await prisma.refreshToken.create({
      data: {
        id: refreshJti,
        userId: employee.ownerId,
        tokenHash: sha256(refreshToken),
        deviceId,
        updatedBy: employee.ownerId,
      },
    });

    const owner = await prisma.user.findUnique({
      where: { id: employee.ownerId },
      select: { email: true },
    });

    return {
      accessToken,
      refreshToken,
      employeeId: employee.id,
      employee: {
        id: employee.id,
        name: employee.name,
        username: employee.username,
        email: employee.email,
        role: employee.role,
        blocked: employee.blocked,
      },
      ownerId: employee.ownerId,
      ownerEmail: owner?.email ?? "",
    };
  },

  async refresh(refreshToken: string, deviceId?: string) {
    let decoded: JwtPayload;
    try {
      decoded = jwt.verify(refreshToken, env.JWT_REFRESH_SECRET) as JwtPayload;
    } catch {
      throw new AppError("Invalid refresh token", 401, "UNAUTHORIZED");
    }

    const userId = decoded.sub;
    const jti = decoded.jti;

    if (!userId || !jti) {
      throw new AppError("Invalid refresh token", 401, "UNAUTHORIZED");
    }

    const stored = await prisma.refreshToken.findUnique({
      where: { id: String(jti) },
    });

    if (!stored || stored.deletedAt) {
      throw new AppError("Invalid refresh token", 401, "UNAUTHORIZED");
    }

    if (stored.userId !== String(userId)) {
      throw new AppError("Invalid refresh token", 401, "UNAUTHORIZED");
    }

    if (stored.deviceId && deviceId && stored.deviceId !== deviceId) {
      throw new AppError("Invalid refresh token", 401, "UNAUTHORIZED");
    }

    if (stored.tokenHash !== sha256(refreshToken)) {
      throw new AppError("Invalid refresh token", 401, "UNAUTHORIZED");
    }

    // rotate
    await prisma.refreshToken.update({
      where: { id: stored.id },
      data: { deletedAt: new Date(), updatedAt: new Date(), updatedBy: String(userId) },
    });

    const accessToken = jwt.sign(
      {},
      env.JWT_ACCESS_SECRET,
      {
        subject: String(userId),
        expiresIn: env.JWT_ACCESS_EXPIRES_IN as SignOptions["expiresIn"],
      } satisfies SignOptions,
    );

    const newRefreshJti = randomUUID();
    const newRefreshToken = jwt.sign(
      { jti: newRefreshJti },
      env.JWT_REFRESH_SECRET,
      {
        subject: String(userId),
        expiresIn: env.JWT_REFRESH_EXPIRES_IN as SignOptions["expiresIn"],
      } satisfies SignOptions,
    );

    await prisma.refreshToken.create({
      data: {
        id: newRefreshJti,
        userId: String(userId),
        tokenHash: sha256(newRefreshToken),
        deviceId,
        updatedBy: String(userId),
      },
    });

    return { accessToken, refreshToken: newRefreshToken };
  },
};
