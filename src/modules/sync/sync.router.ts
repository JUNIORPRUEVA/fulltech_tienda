import { Router } from "express";
import { z } from "zod";

import { authRequired } from "../../middlewares/auth.js";
import { validateBody, validateQuery } from "../../middlewares/validate.js";
import { baseOpSchema, pullQuerySchema } from "./sync.schemas.js";
import { pull, push } from "./sync.controller.js";

export const syncRouter = Router();

syncRouter.use(authRequired);

syncRouter.post("/push", validateBody(z.array(baseOpSchema)), push);
syncRouter.get("/pull", validateQuery(pullQuerySchema), pull);
