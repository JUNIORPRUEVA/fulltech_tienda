import { Router } from "express";
import fs from "node:fs";
import path from "node:path";
import multer from "multer";

import { prisma } from "../../db/prisma.js";
import { authRequired } from "../../middlewares/auth.js";
import { uploadsDir } from "../../config/paths.js";

export const filesRouter = Router();

filesRouter.use(authRequired);

const allowedMime = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "application/pdf",
]);

const resolveExt = (file: Express.Multer.File) => {
  const original = (file.originalname ?? "").toLowerCase();
  const parsed = path.extname(original);
  if ([".png", ".jpg", ".jpeg", ".webp", ".pdf"].includes(parsed)) {
    return parsed;
  }
  if (file.mimetype === "application/pdf") return ".pdf";
  if (file.mimetype === "image/png") return ".png";
  if (file.mimetype === "image/webp") return ".webp";
  return ".jpg";
};

const employeeDocUpload = multer({
  storage: multer.diskStorage({
    destination: (req, _file, cb) => {
      try {
        const ownerId = req.user!.id;
        const employeeId = String(req.params.id);
        const dest = path.join(uploadsDir, "employees", ownerId, employeeId);
        fs.mkdirSync(dest, { recursive: true });
        cb(null, dest);
      } catch (e) {
        cb(e as Error, "");
      }
    },
    filename: (req, file, cb) => {
      const kind = String(req.params.kind);
      cb(null, `${kind}-${Date.now()}${resolveExt(file)}`);
    },
  }),
  limits: { fileSize: 12 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!allowedMime.has(file.mimetype)) {
      cb(new Error("Invalid file type"));
      return;
    }
    cb(null, true);
  },
});

const evidenceUpload = multer({
  storage: multer.diskStorage({
    destination: (req, _file, cb) => {
      try {
        const ownerId = req.user!.id;
        const dest = path.join(uploadsDir, "operation-evidences", ownerId);
        fs.mkdirSync(dest, { recursive: true });
        cb(null, dest);
      } catch (e) {
        cb(e as Error, "");
      }
    },
    filename: (req, file, cb) => {
      const evidenceId = String(req.params.id);
      cb(null, `${evidenceId}-${Date.now()}${resolveExt(file)}`);
    },
  }),
  limits: { fileSize: 12 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!allowedMime.has(file.mimetype)) {
      cb(new Error("Invalid file type"));
      return;
    }
    cb(null, true);
  },
});

const employeeDocField: Record<string, string> = {
  curriculum: "curriculumUrl",
  license: "licenseUrl",
  "id-card": "idCardPhotoUrl",
  "last-job": "lastJobUrl",
};

filesRouter.post(
  "/employees/:id/:kind",
  employeeDocUpload.single("file"),
  async (req, res, next) => {
    try {
      const ownerId = req.user!.id;
      const id = String(req.params.id);
      const kind = String(req.params.kind);
      const field = employeeDocField[kind];

      if (!field) {
        res.status(400).json({
          error: { code: "BAD_REQUEST", message: "Tipo de documento inválido" },
        });
        return;
      }

      const employee = await prisma.employee.findFirst({
        where: { ownerId, id },
      });
      if (!employee) {
        res.status(404).json({
          error: { code: "NOT_FOUND", message: "Empleado no encontrado" },
        });
        return;
      }

      const file = req.file;
      if (!file) {
        res.status(400).json({
          error: { code: "BAD_REQUEST", message: "Missing file" },
        });
        return;
      }

      const relativePath = `/uploads/employees/${ownerId}/${id}/${file.filename}`;
      const baseUrl = `${req.protocol}://${req.get("host")}`;
      const url = `${baseUrl}${relativePath}`;

      await prisma.employee.update({
        where: { id: employee.id },
        data: {
          [field]: url,
          updatedAt: new Date(),
          updatedBy: ownerId,
          deviceId: req.deviceId ?? null,
        },
      });

      res.status(200).json({
        data: {
          url,
          path: relativePath,
          employeeId: employee.id,
          kind,
        },
      });
    } catch (e) {
      next(e);
    }
  },
);

filesRouter.post(
  "/operation-evidences/:id",
  evidenceUpload.single("file"),
  async (req, res, next) => {
    try {
      const ownerId = req.user!.id;
      const id = String(req.params.id);

      const evidence = await prisma.operationEvidence.findFirst({
        where: { ownerId, id },
      });
      if (!evidence) {
        res.status(404).json({
          error: { code: "NOT_FOUND", message: "Evidencia no encontrada" },
        });
        return;
      }

      const file = req.file;
      if (!file) {
        res.status(400).json({
          error: { code: "BAD_REQUEST", message: "Missing file" },
        });
        return;
      }

      const relativePath = `/uploads/operation-evidences/${ownerId}/${file.filename}`;
      const baseUrl = `${req.protocol}://${req.get("host")}`;
      const url = `${baseUrl}${relativePath}`;

      await prisma.operationEvidence.update({
        where: { id: evidence.id },
        data: {
          fileUrl: url,
          updatedAt: new Date(),
          updatedBy: ownerId,
          deviceId: req.deviceId ?? null,
        },
      });

      res.status(200).json({
        data: {
          url,
          path: relativePath,
          evidenceId: evidence.id,
        },
      });
    } catch (e) {
      next(e);
    }
  },
);
