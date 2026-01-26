# FULLTECH Backend (Cloud-first)

Backend “cloud-first” para una app Flutter con modo offline + sincronización por Outbox.

**Stack:** Node.js + Express + PostgreSQL + Prisma + JWT + Zod + Docker Compose.

## Requisitos

- Node.js 20+
- Docker Desktop (recomendado para PostgreSQL local)

## Arranque rápido (Docker)

Desde esta carpeta:

```bash
docker compose up --build
```

La API queda en `http://localhost:3000`.

Luego aplica migraciones (ya se ejecutan al arrancar el contenedor `api`), y opcionalmente seed:

```bash
docker compose exec api npm run seed
```

## Arranque local (sin Docker)

1) Levanta PostgreSQL localmente y crea una DB `fulltech`.
2) Configura `.env` (puedes copiar desde `.env.example`).
3) Instala deps y migra:

```bash
npm install
npm run migrate
npm run seed
npm run dev
```

## Base de datos (PostgreSQL)

Recomendado: PostgreSQL 15+ (se usa `TIMESTAMPTZ` y UUID con `pgcrypto`).

### Variables .env necesarias

- `DATABASE_URL`
- `ADMIN_EMAIL` y `ADMIN_PASSWORD` (obligatorias para `npm run seed`)
- `UPLOAD_DIR` (opcional, default `uploads`)

Archivos (fotos, etc.): se sirven en `GET /uploads/<archivo>`.
En producción, monta un volumen persistente en la ruta del contenedor ` /app/uploads `.

### Levantar solo la DB (Docker)

```bash
docker compose -f docker-compose.db.yml up -d
```

### Migraciones / Seed

- Migrar “latest” (producción/CI):

```bash
npx prisma migrate deploy
```

- Migrar en dev (crea/aplica migraciones):

```bash
npx prisma migrate dev
```

- Seed:

```bash
npm run seed
```

### Rollback

Prisma Migrate no soporta “down migrations” automáticas.

- En desarrollo (borra y recrea):

```bash
npx prisma migrate reset
```

- En producción: usar backups/restore o una migración correctiva.

## Endpoints

### Auth

- `POST /auth/register` (opcional)
- `POST /auth/login` → devuelve `accessToken` (y `refreshToken`)
- `POST /auth/refresh` → rota refresh token

Ejemplo login:

```bash
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@fulltech.local","password":"admin1234","deviceId":"android-1"}'
```

### CRUD (protegido con JWT)

- `/customers`
- `/products`
- `/sales`

List con paginación: `GET /customers?limit=20&offset=0`

### Sync

- `POST /sync/push` (JWT)
- `GET /sync/pull?since=ISO-8601` (JWT)

**Contrato push:** body es un array de operaciones

```json
[
  {
    "opId": "uuid",
    "entity": "customers|products|sales",
    "entityId": "uuid",
    "type": "UPSERT|DELETE",
    "payload": { "...": "..." },
    "clientUpdatedAt": "2026-01-26T00:00:00.000Z",
    "deviceId": "string"
  }
]
```

Ejemplo push:

```bash
curl -X POST http://localhost:3000/sync/push \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '[{
    "opId":"00000000-0000-0000-0000-000000000001",
    "entity":"customers",
    "entityId":"00000000-0000-0000-0000-000000000010",
    "type":"UPSERT",
    "payload":{ "name":"Juan Perez","email":"juan@test.com" },
    "clientUpdatedAt":"2026-01-26T00:00:00.000Z",
    "deviceId":"android-1"
  }]'
```

**Pull:**

```bash
curl -X GET "http://localhost:3000/sync/pull?since=1970-01-01T00:00:00.000Z" \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

## Notas de conflicto

Regla: **SERVER WINS**.

Si llega un `UPSERT/DELETE` con `clientUpdatedAt` más viejo que el último cambio en server, la operación responde `CONFLICT` con `serverEntity`.
