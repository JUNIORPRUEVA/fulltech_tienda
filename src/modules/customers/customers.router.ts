import { Router } from "express";

import { authRequired } from "../../middlewares/auth.js";
import { validateBody, validateQuery } from "../../middlewares/validate.js";
import {
  customerCreateSchema,
  customerUpdateSchema,
  listQuerySchema,
} from "./customers.schemas.js";
import {
  createCustomer,
  deleteCustomer,
  getCustomer,
  listCustomers,
  updateCustomer,
} from "./customers.controller.js";

export const customersRouter = Router();

customersRouter.use(authRequired);

customersRouter.get("/", validateQuery(listQuerySchema), listCustomers);
customersRouter.get("/:id", getCustomer);
customersRouter.post("/", validateBody(customerCreateSchema), createCustomer);
customersRouter.patch(
  "/:id",
  validateBody(customerUpdateSchema),
  updateCustomer,
);
customersRouter.delete("/:id", deleteCustomer);
