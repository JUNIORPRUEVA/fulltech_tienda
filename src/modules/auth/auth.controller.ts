import type { RequestHandler } from "express";

import { authService } from "./auth.service.js";

export const register: RequestHandler = async (req, res, next) => {
  try {
    const { email, password } = req.body as { email: string; password: string };
    const user = await authService.register(email, password);
    res.status(201).json({ user });
  } catch (e) {
    next(e);
  }
};

export const login: RequestHandler = async (req, res, next) => {
  try {
    const { email, password, deviceId } = req.body as {
      email: string;
      password: string;
      deviceId?: string;
    };

    const tokens = await authService.login(email, password, deviceId);
    res.status(200).json(tokens);
  } catch (e) {
    next(e);
  }
};

export const refresh: RequestHandler = async (req, res, next) => {
  try {
    const { refreshToken, deviceId } = req.body as {
      refreshToken: string;
      deviceId?: string;
    };

    const tokens = await authService.refresh(refreshToken, deviceId);
    res.status(200).json(tokens);
  } catch (e) {
    next(e);
  }
};
