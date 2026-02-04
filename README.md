# FULLTECH (Flutter + Backend)

Este repo incluye:
- App Flutter (carpeta `lib/`)
- Backend Node/Express + PostgreSQL (carpeta `backend/`)

## Login virtual (no local)

El login de la app es **contra el backend** (`/auth/employee/login`) y luego sincroniza (`/sync/pull` / `/sync/push`).

### 1) Levantar el backend (Docker recomendado)

Desde `backend/`:

```bash
docker compose up --build
docker compose exec api npm run seed
```

### 2) Ejecutar la app Flutter apuntando al backend local

La app apunta por defecto al backend de producción configurado en `CloudSettings.productionBaseUrl`.

Si necesitas apuntar a otro servidor:

```bash
flutter run --dart-define=CLOUD_BASE_URL=http://TU_IP:3000
```

Ejemplos comunes:
- Android emulador: `http://10.0.2.2:3000`
- Desktop/iOS simulator: `http://localhost:3000`

## Credenciales demo

Al ejecutar `npm run seed` se crea (o actualiza) un usuario empleado demo:
- Usuario: `demo`
- Contraseña: `Demo12345!`
