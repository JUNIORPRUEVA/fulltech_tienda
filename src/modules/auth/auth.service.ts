import * as bcrypt from "bcryptjs";
import * as jwt from "jsonwebtoken";
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
        expiresIn: env.JWT_ACCESS_EXPIRES_IN as jwt.SignOptions["expiresIn"],
      } satisfies jwt.SignOptions,
    );

    const refreshJti = randomUUID();
    const refreshToken = jwt.sign(
      { jti: refreshJti },
      env.JWT_REFRESH_SECRET,
      {
        subject: user.id,
        expiresIn: env.JWT_REFRESH_EXPIRES_IN as jwt.SignOptions["expiresIn"],
      } satisfies jwt.SignOptions,
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

  async refresh(refreshToken: string, deviceId?: string) {
    let decoded: jwt.JwtPayload;
    try {
      decoded = jwt.verify(refreshToken, env.JWT_REFRESH_SECRET) as jwt.JwtPayload;
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
        expiresIn: env.JWT_ACCESS_EXPIRES_IN as jwt.SignOptions["expiresIn"],
      } satisfies jwt.SignOptions,
    );

    const newRefreshJti = randomUUID();
    const newRefreshToken = jwt.sign(
      { jti: newRefreshJti },
      env.JWT_REFRESH_SECRET,
      {
        subject: String(userId),
        expiresIn: env.JWT_REFRESH_EXPIRES_IN as jwt.SignOptions["expiresIn"],
      } satisfies jwt.SignOptions,
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
