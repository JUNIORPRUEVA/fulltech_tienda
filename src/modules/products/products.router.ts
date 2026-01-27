import { Router } from "express";
import fs from "node:fs";
import path from "node:path";
import multer from "multer";

import { authRequired } from "../../middlewares/auth.js";
import { validateBody, validateQuery } from "../../middlewares/validate.js";
import { uploadsDir } from "../../config/paths.js";
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
import { productsService } from "./products.service.js";

export const productsRouter = Router();

productsRouter.use(authRequired);

productsRouter.get("/", validateQuery(listQuerySchema), listProducts);
productsRouter.get("/:id", getProduct);
productsRouter.post("/", validateBody(productCreateSchema), createProduct);
productsRouter.patch("/:id", validateBody(productUpdateSchema), updateProduct);

const productImageUpload = multer({
  storage: multer.diskStorage({
    destination: (req, _file, cb) => {
      try {
        const ownerId = req.user!.id;
        const dest = path.join(uploadsDir, "products", ownerId);
        fs.mkdirSync(dest, { recursive: true });
        cb(null, dest);
      } catch (e) {
        cb(e as Error, "");
      }
    },
    filename: (req, file, cb) => {
      const productId = String(req.params.id);
      const ext = (() => {
        const original = (file.originalname ?? "").toLowerCase();
        const parsed = path.extname(original);
        if (parsed === ".png" || parsed === ".jpg" || parsed === ".jpeg" || parsed === ".webp") {
          return parsed;
        }
        if (file.mimetype === "image/png") return ".png";
        if (file.mimetype === "image/webp") return ".webp";
        return ".jpg";
      })();

      cb(null, `${productId}-${Date.now()}${ext}`);
    },
  }),
  limits: {
    fileSize: 8 * 1024 * 1024,
  },
  fileFilter: (_req, file, cb) => {
    const ok =
      file.mimetype === "image/jpeg" ||
      file.mimetype === "image/jpg" ||
      file.mimetype === "image/png" ||
      file.mimetype === "image/webp";
    if (!ok) {
      cb(new Error("Only image files are allowed"));
      return;
    }
    cb(null, true);
  },
});

productsRouter.post(
  "/:id/image",
  productImageUpload.single("image"),
  async (req, res, next) => {
    try {
      const ownerId = req.user!.id;
      const userId = req.user!.id;
      const id = String(req.params.id);

      const file = req.file;
      if (!file) {
        res.status(400).json({
          error: { code: "BAD_REQUEST", message: "Missing image file" },
        });
        return;
      }

      // Ensure product exists and belongs to owner.
      await productsService.getById({ ownerId, id });

      const relativePath = `/uploads/products/${ownerId}/${file.filename}`;
      const baseUrl = `${req.protocol}://${req.get("host")}`;
      const imageUrl = `${baseUrl}${relativePath}`;

      const updated = await productsService.update({
        ownerId,
        userId,
        deviceId: req.deviceId,
        id,
        data: { imageUrl },
      });

      res.status(200).json({
        data: {
          product: updated,
          imageUrl,
          path: relativePath,
        },
      });
    } catch (e) {
      next(e);
    }
  },
);

productsRouter.delete("/:id", deleteProduct);
