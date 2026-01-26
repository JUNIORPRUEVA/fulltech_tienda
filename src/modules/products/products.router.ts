import { Router } from "express";

import { authRequired } from "../../middlewares/auth.js";
import { validateBody, validateQuery } from "../../middlewares/validate.js";
import {
  listQuerySchema,
  productCreateSchema,
  productUpdateSchema,
} from "./products.schemas.js";
import {
  createProduct,
  deleteProduct,
  getProduct,
  listProducts,
  updateProduct,
} from "./products.controller.js";

export const productsRouter = Router();

productsRouter.use(authRequired);

productsRouter.get("/", validateQuery(listQuerySchema), listProducts);
productsRouter.get("/:id", getProduct);
productsRouter.post("/", validateBody(productCreateSchema), createProduct);
productsRouter.patch("/:id", validateBody(productUpdateSchema), updateProduct);
productsRouter.delete("/:id", deleteProduct);
