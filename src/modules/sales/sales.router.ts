import { Router } from "express";

import { authRequired } from "../../middlewares/auth.js";
import { validateBody, validateQuery } from "../../middlewares/validate.js";
import { listQuerySchema, saleCreateSchema, saleUpdateSchema } from "./sales.schemas.js";
import {
  createSale,
  deleteSale,
  getSale,
  listSales,
  updateSale,
} from "./sales.controller.js";

export const salesRouter = Router();

salesRouter.use(authRequired);

salesRouter.get("/", validateQuery(listQuerySchema), listSales);
salesRouter.get("/:id", getSale);
salesRouter.post("/", validateBody(saleCreateSchema), createSale);
salesRouter.patch("/:id", validateBody(saleUpdateSchema), updateSale);
salesRouter.delete("/:id", deleteSale);
