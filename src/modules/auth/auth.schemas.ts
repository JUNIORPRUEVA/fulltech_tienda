import { z } from "zod";

export const registerBodySchema = z.object({
  email: z.string().email().max(320),
  password: z.string().min(8).max(200),
});

export const loginBodySchema = z.object({
  email: z.string().email().max(320),
  password: z.string().min(1),
  deviceId: z.string().min(1).max(200).optional(),
});

export const employeeLoginBodySchema = z.object({
  username: z.string().min(1).max(100),
  password: z.string().min(1).max(200),
  deviceId: z.string().min(1).max(200).optional(),
});

export const refreshBodySchema = z.object({
  refreshToken: z.string().min(1),
  deviceId: z.string().min(1).max(200).optional(),
});
