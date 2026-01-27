import { Router } from "express";
import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import multer from "multer";
import { z } from "zod";

import { prisma } from "../../db/prisma.js";
import { env } from "../../config/env.js";
import { uploadsDir } from "../../config/paths.js";
import { authRequired } from "../../middlewares/auth.js";

export const rrhhRouter = Router();

const roles = [
  { key: "tecnico", label: "Técnico" },
  { key: "vendedor", label: "Vendedor" },
  { key: "marketing", label: "Marketing" },
  { key: "asistente", label: "Asistente Administrativo" },
  { key: "admin", label: "Administrador" },
] as const;

const roleMap = new Map(roles.map((r) => [r.key, r.label]));

const escapeHtml = (value: string) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const resolveOwnerByEmail = async (email: string) => {
  if (!email) return null;
  return prisma.user.findUnique({ where: { email } });
};

const techAreas = [
  "Instalación de cámaras",
  "Cercos eléctricos",
  "Intercom",
  "Motores de portones",
] as const;

const formUpload = multer({
  storage: multer.diskStorage({
    destination: (req, _file, cb) => {
      try {
        const ownerId = (req as any).rrhhOwnerId as string;
        const appId = (req as any).rrhhAppId as string;
        const dest = path.join(uploadsDir, "rrhh", ownerId, appId);
        fs.mkdirSync(dest, { recursive: true });
        cb(null, dest);
      } catch (e) {
        cb(e as Error, "");
      }
    },
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || ".dat";
      cb(null, `${file.fieldname}-${Date.now()}${ext}`);
    },
  }),
  limits: { fileSize: 10 * 1024 * 1024 },
});

rrhhRouter.get("/", async (req, res) => {
  const email = (req.query.email ?? "").toString().trim().toLowerCase();
  const links = roles
    .map((r) => {
      const href = email
        ? `/rrhh/roles/${r.key}?email=${encodeURIComponent(email)}`
        : `/rrhh/roles/${r.key}`;
      return `<a class="role-card" href="${href}">
        <div class="role-title">${escapeHtml(r.label)}</div>
        <div class="role-sub">Formulario virtual para aplicar</div>
      </a>`;
    })
    .join("");

  res.status(200).send(`<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(env.COMPANY_NAME)} | RRHH</title>
    <style>
      body { margin:0; font-family: 'Segoe UI', Arial, sans-serif; background:#f6f6f6; }
      header { background:#111; color:#fff; padding:32px 16px; }
      .container { max-width: 980px; margin:0 auto; }
      h1 { margin:0; font-size:28px; }
      p { margin:6px 0 0; color:rgba(255,255,255,.8); }
      main { padding:24px 16px 48px; }
      .grid { display:grid; gap:16px; grid-template-columns: repeat(auto-fit, minmax(220px,1fr)); }
      .role-card { background:#fff; padding:18px; border-radius:16px; text-decoration:none; color:#111; box-shadow:0 12px 30px rgba(0,0,0,.08); }
      .role-title { font-weight:800; font-size:16px; }
      .role-sub { color:#666; margin-top:6px; font-size:13px; }
      footer { padding:20px 16px; color:#666; text-align:center; font-size:12px; }
    </style>
  </head>
  <body>
    <header>
      <div class="container">
        <h1>RRHH - Formularios de aplicación</h1>
        <p>${escapeHtml(env.COMPANY_TAGLINE)}</p>
      </div>
    </header>
    <main class="container">
      <div class="grid">${links}</div>
    </main>
    <footer>${escapeHtml(env.COMPANY_NAME)} · RRHH</footer>
  </body>
</html>`);
});

rrhhRouter.get("/roles/:role", async (req, res) => {
  const roleKey = (req.params.role ?? "").toString();
  const roleLabel = roleMap.get(roleKey);
  if (!roleLabel) {
    res.status(404).send("Rol no encontrado.");
    return;
  }
  const email = (req.query.email ?? "").toString().trim().toLowerCase();
  const action = email
    ? `/rrhh/roles/${roleKey}/apply?email=${encodeURIComponent(email)}`
    : `/rrhh/roles/${roleKey}/apply`;

  const techFields =
    roleKey === "tecnico"
      ? `
      <label>Tipo de técnico</label>
      <select name="techType" required>
        <option value="">Selecciona</option>
        <option value="Instalador">Instalador</option>
        <option value="Soporte">Soporte</option>
        <option value="Ambas">Ambas</option>
      </select>
      <label>Áreas</label>
      <div class="checks">
        ${techAreas
          .map(
            (a) =>
              `<label class="check"><input type="checkbox" name="techAreas" value="${escapeHtml(
                a,
              )}"> ${escapeHtml(a)}</label>`,
          )
          .join("")}
      </div>
    `
      : "";

  res.status(200).send(`<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(env.COMPANY_NAME)} | ${escapeHtml(roleLabel)}</title>
    <style>
      body { margin:0; font-family:'Segoe UI', Arial, sans-serif; background:#f6f6f6; }
      header { background:#111; color:#fff; padding:28px 16px; }
      .container { max-width: 900px; margin:0 auto; }
      h1 { margin:0; font-size:26px; }
      p { margin:6px 0 0; color:rgba(255,255,255,.8); }
      main { padding:24px 16px 48px; }
      form { background:#fff; padding:22px; border-radius:18px; box-shadow:0 12px 30px rgba(0,0,0,.08); display:grid; gap:12px; }
      label { font-weight:700; font-size:13px; }
      input, select { padding:10px 12px; border-radius:10px; border:1px solid #ddd; font-size:14px; }
      .row { display:grid; grid-template-columns: repeat(auto-fit, minmax(180px,1fr)); gap:12px; }
      .checks { display:grid; gap:8px; grid-template-columns: repeat(auto-fit, minmax(180px,1fr)); }
      .check { font-weight:500; }
      button { background:#111; color:#fff; border:none; padding:12px 16px; border-radius:12px; font-weight:800; cursor:pointer; }
      footer { padding:20px 16px; color:#666; text-align:center; font-size:12px; }
    </style>
  </head>
  <body>
    <header>
      <div class="container">
        <h1>Formulario para ${escapeHtml(roleLabel)}</h1>
        <p>Completa los datos y adjunta tus documentos.</p>
      </div>
    </header>
    <main class="container">
      <form method="post" action="${action}" enctype="multipart/form-data">
        <div class="row">
          <div>
            <label>Nombre completo</label>
            <input name="name" required />
          </div>
          <div>
            <label>Teléfono</label>
            <input name="phone" required />
          </div>
          <div>
            <label>WhatsApp</label>
            <input name="whatsapp" required />
          </div>
        </div>
        ${techFields}
        <label>Currículum (PDF o imagen)</label>
        <input type="file" name="resume" required />
        <label>Copia de cédula</label>
        <input type="file" name="idCard" required />
        <label>Foto personal</label>
        <input type="file" name="photo" required />
        <button type="submit">Enviar solicitud</button>
      </form>
    </main>
    <footer>${escapeHtml(env.COMPANY_NAME)} · RRHH</footer>
  </body>
</html>`);
});

rrhhRouter.post(
  "/roles/:role/apply",
  async (req, res, next) => {
    const email = (req.query.email ?? "").toString().trim().toLowerCase();
    const owner = await resolveOwnerByEmail(email);
    if (!owner) {
      res.status(200).send("Empresa no encontrada.");
      return;
    }
    (req as any).rrhhOwnerId = owner.id;
    (req as any).rrhhEmail = email;
    (req as any).rrhhAppId = randomUUID();
    next();
  },
  formUpload.fields([
    { name: "resume", maxCount: 1 },
    { name: "idCard", maxCount: 1 },
    { name: "photo", maxCount: 1 },
  ]),
  async (req, res, next) => {
    try {
      const roleKey = (req.params.role ?? "").toString();
      const roleLabel = roleMap.get(roleKey);
      if (!roleLabel) {
        res.status(404).send("Rol no encontrado.");
        return;
      }

      const ownerId = (req as any).rrhhOwnerId as string;

      const name = (req.body.name ?? "").toString().trim();
      const phone = (req.body.phone ?? "").toString().trim();
      const whatsapp = (req.body.whatsapp ?? "").toString().trim();
      if (!name || !phone || !whatsapp) {
        res.status(400).send("Datos incompletos.");
        return;
      }

      const files = req.files as Record<string, Express.Multer.File[]>;
      const resume = files?.resume?.[0];
      const idCard = files?.idCard?.[0];
      const photo = files?.photo?.[0];
      if (!resume || !idCard || !photo) {
        res.status(400).send("Debes adjuntar todos los documentos.");
        return;
      }

      const baseUrl = `${req.protocol}://${req.get("host")}`;
      const appId = (req as any).rrhhAppId as string;
      const makeUrl = (file: Express.Multer.File) => {
        const rel = `/uploads/rrhh/${ownerId}/${appId}/${file.filename}`;
        return `${baseUrl}${rel}`;
      };

      let techType: string | undefined;
      let techAreasSelected: string[] | undefined;
      if (roleKey === "tecnico") {
        techType = (req.body.techType ?? "").toString().trim();
        const raw = req.body.techAreas;
        if (Array.isArray(raw)) {
          techAreasSelected = raw.map((v) => v.toString());
        } else if (typeof raw === "string" && raw.trim().length > 0) {
          techAreasSelected = [raw.trim()];
        }
        if (!techType || !techAreasSelected || techAreasSelected.length == 0) {
          res.status(400).send("Selecciona el tipo y las áreas del técnico.");
          return;
        }
      }

      await prisma.hrApplication.create({
        data: {
          id: appId,
          ownerId: ownerId,
          role: roleLabel,
          name,
          phone,
          whatsapp,
          techType: techType || null,
          techAreas: techAreasSelected ?? null,
          resumeUrl: makeUrl(resume),
          idCardUrl: makeUrl(idCard),
          photoUrl: makeUrl(photo),
          status: "PENDING",
          createdAt: new Date(),
          updatedAt: new Date(),
          updatedBy: ownerId,
        },
      });

      res.status(200).send(
        `Solicitud enviada. Gracias por aplicar a ${escapeHtml(roleLabel)}.`,
      );
    } catch (e) {
      next(e);
    }
  },
);

// Admin endpoints
const statusSchema = z.enum(["PENDING", "APPROVED", "REJECTED"]);

rrhhRouter.get("/applications", authRequired, async (req, res, next) => {
  try {
    const status = statusSchema.optional().parse(req.query.status);
    const data = await prisma.hrApplication.findMany({
      where: {
        ownerId: req.user!.id,
        deletedAt: null,
        status: status ?? undefined,
      },
      orderBy: { createdAt: "desc" },
    });
    res.json({ data });
  } catch (e) {
    next(e);
  }
});

rrhhRouter.patch("/applications/:id", authRequired, async (req, res, next) => {
  try {
    const status = statusSchema.parse(req.body?.status);
    const id = String(req.params.id);
    const updated = await prisma.hrApplication.update({
      where: { id },
      data: {
        status,
        updatedAt: new Date(),
        updatedBy: req.user!.id,
        deviceId: req.deviceId ?? null,
      },
    });
    res.json({ data: updated });
  } catch (e) {
    next(e);
  }
});

rrhhRouter.delete("/applications/:id", authRequired, async (req, res, next) => {
  try {
    const id = String(req.params.id);
    const updated = await prisma.hrApplication.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        updatedAt: new Date(),
        updatedBy: req.user!.id,
        deviceId: req.deviceId ?? null,
      },
    });
    res.json({ data: updated });
  } catch (e) {
    next(e);
  }
});
