import { Router } from "express";

import { validateBody } from "../../middlewares/validate.js";
import {
  loginBodySchema,
  refreshBodySchema,
  registerBodySchema,
} from "./auth.schemas.js";
import { login, refresh, register } from "./auth.controller.js";

export const authRouter = Router();

authRouter.post("/register", validateBody(registerBodySchema), register);
authRouter.post("/login", validateBody(loginBodySchema), login);
authRouter.post("/refresh", validateBody(refreshBodySchema), refresh);
