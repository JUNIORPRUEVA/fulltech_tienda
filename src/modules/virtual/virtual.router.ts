import { Router } from "express";
import { prisma } from "../../db/prisma.js";
import { env } from "../../config/env.js";

export const virtualRouter = Router();

const escapeHtml = (value: string) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const formatPrice = (raw: unknown) => {
  const num = Number(raw);
  if (Number.isNaN(num)) return "0.00";
  return num.toFixed(2);
};

const brand = {
  name: env.COMPANY_NAME,
  tagline: env.COMPANY_TAGLINE,
  whatsapp: env.WHATSAPP_PHONE,
};

virtualRouter.get("/manifest.json", (req, res) => {
  const email = (req.query.email ?? "").toString().trim();
  const startUrl = email
    ? `/virtual?email=${encodeURIComponent(email)}`
    : "/virtual";

  res.json({
    name: `${brand.name} | Catálogo`,
    short_name: brand.name,
    start_url: startUrl,
    display: "standalone",
    background_color: "#f8f8f8",
    theme_color: "#111111",
    icons: [
      {
        src: "/virtual/icon.svg",
        sizes: "512x512",
        type: "image/svg+xml",
      },
    ],
  });
});

virtualRouter.get("/icon.svg", (_req, res) => {
  res.type("image/svg+xml").send(
    `<?xml version="1.0" encoding="UTF-8"?>
<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
  <rect width="512" height="512" fill="#111111"/>
  <text x="50%" y="52%" text-anchor="middle" font-size="200" fill="#ffffff" font-family="Arial, sans-serif" font-weight="bold">FT</text>
</svg>`,
  );
});

virtualRouter.get("/sw.js", (_req, res) => {
  res.type("application/javascript").send(
    `const CACHE = 'virtual-catalog-v1';
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(['/virtual', '/virtual/icon.svg']))
  );
});
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
});
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});`,
  );
});

virtualRouter.get("/", async (req, res, next) => {
  try {
    const email = (req.query.email ?? "").toString().trim().toLowerCase();
    if (!email) {
      res.status(200).send(renderEmpty("Falta el correo del catálogo."));
      return;
    }

    let user: { id: string } | null = null;
    try {
      user = await prisma.user.findUnique({ where: { email } });
    } catch (_) {
      res
        .status(200)
        .send(renderEmpty("Catálogo temporalmente no disponible."));
      return;
    }

    if (!user) {
      res.status(200).send(renderEmpty("Catálogo no encontrado."));
      return;
    }

    let products: any[] = [];
    try {
      products = await prisma.product.findMany({
        where: { ownerId: user.id, deletedAt: null },
        orderBy: [{ category: "asc" }, { name: "asc" }],
      });
    } catch (_) {
      res
        .status(200)
        .send(renderCatalog({ email, categories: new Map(), wa: null }));
      return;
    }

    const categories = new Map<string, typeof products>();
    for (const product of products) {
      const category = (product.category ?? "General").trim() || "General";
      const list = categories.get(category) ?? [];
      list.push(product);
      categories.set(category, list);
    }

    const wa =
      brand.whatsapp.trim() === ""
        ? null
        : `https://wa.me/${brand.whatsapp.replaceAll(/\D/g, "")}`;

    res.status(200).send(
      renderCatalog({
        email,
        categories,
        wa,
      }),
    );
  } catch (e) {
    next(e);
  }
});

const renderEmpty = (message: string) => `
<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(brand.name)} | Catálogo</title>
    <style>
      body { font-family: 'Segoe UI', Arial, sans-serif; background:#f6f6f6; margin:0; }
      .wrap { max-width: 780px; margin: 12vh auto; background:#fff; padding: 28px; border-radius: 18px; box-shadow: 0 18px 40px rgba(0,0,0,.08); }
      h1 { margin: 0 0 8px; font-size: 26px; }
      p { margin: 0; color: #555; }
    </style>
  </head>
  <body>
    <div class="wrap">
      <h1>${escapeHtml(brand.name)}</h1>
      <p>${escapeHtml(message)}</p>
    </div>
  </body>
</html>`;

const renderCatalog = (params: {
  email: string;
  categories: Map<string, any[]>;
  wa: string | null;
}) => {
  const categorySections = [...params.categories.entries()]
    .map(([category, items]) => {
      const cards = items
        .map(
          (p) => `
        <article class="card">
          <div class="thumb">
            ${
              p.imageUrl
                ? `<img src="${escapeHtml(p.imageUrl)}" alt="${escapeHtml(
                    p.name,
                  )}" loading="lazy" />`
                : `<div class="placeholder">Sin imagen</div>`
            }
          </div>
          <div class="card-body">
            <div class="card-title">${escapeHtml(p.name)}</div>
            <div class="card-meta">${escapeHtml(category)}</div>
            <div class="card-price">RD$ ${formatPrice(p.price)}</div>
          </div>
        </article>
      `,
        )
        .join("");

      return `
      <section class="category">
        <h2>${escapeHtml(category)}</h2>
        <div class="grid">
          ${cards}
        </div>
      </section>
    `;
    })
    .join("");

  return `<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#111111" />
    <title>${escapeHtml(brand.name)} | Catálogo</title>
    <link rel="manifest" href="/virtual/manifest.json?email=${encodeURIComponent(
      params.email,
    )}" />
    <style>
      :root {
        --bg: #f6f6f6;
        --card: #ffffff;
        --text: #151515;
        --muted: #6c6c6c;
        --accent: #111111;
        --radius: 18px;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        font-family: 'Segoe UI', Arial, sans-serif;
        color: var(--text);
        background: var(--bg);
      }
      header {
        background: radial-gradient(circle at top, #2b2b2b 0%, #111 55%);
        color: #fff;
        padding: 42px 16px 36px;
      }
      .container { max-width: 1100px; margin: 0 auto; }
      .brand {
        display: flex; align-items: center; gap: 12px; font-weight: 800;
        font-size: 22px; letter-spacing: .5px;
      }
      .brand-badge {
        width: 44px; height: 44px; border-radius: 14px; background: #fff;
        color: #111; display: grid; place-items: center; font-weight: 900;
      }
      .hero {
        margin-top: 24px;
        display: flex; flex-direction: column; gap: 12px;
      }
      .hero h1 { margin: 0; font-size: 32px; }
      .hero p { margin: 0; color: rgba(255,255,255,.8); }
      .hero-actions { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 6px; }
      .btn {
        background: #fff; color: #111; padding: 10px 16px; border-radius: 12px;
        text-decoration: none; font-weight: 700; font-size: 14px;
      }
      .btn-outline {
        background: transparent; border: 1px solid rgba(255,255,255,.4); color: #fff;
      }
      main { padding: 24px 16px 48px; }
      .category { margin-top: 24px; }
      .category h2 { margin: 0 0 12px; font-size: 20px; }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 16px;
      }
      .card {
        background: var(--card);
        border-radius: var(--radius);
        overflow: hidden;
        box-shadow: 0 12px 30px rgba(0,0,0,.08);
        display: flex; flex-direction: column;
      }
      .thumb {
        background: #f0f0f0;
        aspect-ratio: 4 / 3;
        display: grid;
        place-items: center;
      }
      .thumb img { width: 100%; height: 100%; object-fit: cover; }
      .placeholder { color: var(--muted); font-size: 13px; }
      .card-body { padding: 14px 14px 18px; display: grid; gap: 6px; }
      .card-title { font-weight: 800; font-size: 15px; }
      .card-meta { color: var(--muted); font-size: 12px; }
      .card-price { font-weight: 800; font-size: 16px; }
      footer {
        background: #0f0f0f;
        color: #f1f1f1;
        padding: 24px 16px;
      }
      .footer-grid {
        display: grid;
        gap: 12px;
        grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      }
      .footer-title { font-weight: 800; margin-bottom: 6px; }
      .footer-note { color: rgba(255,255,255,.7); font-size: 13px; }
      @media (max-width: 600px) {
        header { padding: 32px 16px; }
        .hero h1 { font-size: 26px; }
      }
    </style>
  </head>
  <body>
    <header>
      <div class="container">
        <div class="brand">
          <div class="brand-badge">FT</div>
          ${escapeHtml(brand.name)}
        </div>
        <div class="hero">
          <h1>Catálogo de productos</h1>
          <p>${escapeHtml(brand.tagline)}</p>
          <div class="hero-actions">
            ${params.wa ? `<a class="btn" href="${params.wa}" target="_blank" rel="noreferrer">WhatsApp</a>` : ""}
            <a class="btn btn-outline" href="#catalogo">Ver catálogo</a>
          </div>
        </div>
      </div>
    </header>
    <main id="catalogo" class="container">
      ${categorySections || "<p>No hay productos disponibles.</p>"}
    </main>
    <footer>
      <div class="container footer-grid">
        <div>
          <div class="footer-title">${escapeHtml(brand.name)}</div>
          <div class="footer-note">Catálogo actualizado desde la app.</div>
        </div>
        <div>
          <div class="footer-title">Contacto</div>
          <div class="footer-note">${
            params.wa ? "WhatsApp disponible" : "WhatsApp no configurado"
          }</div>
        </div>
        <div>
          <div class="footer-title">PWA</div>
          <div class="footer-note">Agrega este catálogo a tu pantalla de inicio.</div>
        </div>
      </div>
    </footer>
    <script>
      if ('serviceWorker' in navigator) {
        window.addEventListener('load', () => {
          navigator.serviceWorker.register('/virtual/sw.js');
        });
      }
    </script>
  </body>
</html>`;
};
