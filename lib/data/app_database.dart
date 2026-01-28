import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'cloud_settings.dart';
import 'sync/sync_outbox.dart';

/// SQLite database (Android/iOS/Windows/macOS/Linux).
///
/// Nota: Flutter Web no soporta SQLite con `sqflite`; si necesitas web,
/// podemos agregar un backend alterno.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  sqflite.Database? _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void notifyChanged() {
    if (_changes.isClosed) return;
    _changes.add(null);
  }

  Future<void> init() async {
    if (_db != null) return;

    const isTest = bool.fromEnvironment('FLUTTER_TEST');

    if (kIsWeb) {
      throw UnsupportedError(
          'SQLite no está soportado en Flutter Web con esta configuración.');
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      ffi.sqfliteFfiInit();
      sqflite.databaseFactory = ffi.databaseFactoryFfi;
    }

    final dbPath = isTest ? sqflite.inMemoryDatabasePath : await _getDbPath();
    _db = await sqflite.openDatabase(
      dbPath,
      version: 17,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onOpen: (db) async {
        // Auto-repara esquemas faltantes aunque el user_version no cambie.
        // Esto evita crashes por DBs antiguas/copiadas/corruptas.
        await _ensureEmpresaConfigTable(db);
        await _ensureProductosColumns(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        Future<void> tryExecute(String sql) async {
          try {
            await db.execute(sql);
          } catch (_) {
            // Ignora si la columna/tabla ya existe (migraciones idempotentes).
          }
        }

        if (oldVersion < 14) {
          // Sync metadata (server UUID mapping) + outbox
          await tryExecute('ALTER TABLE clientes ADD COLUMN server_id TEXT');
          await tryExecute('ALTER TABLE clientes ADD COLUMN sync_version INTEGER');
          await tryExecute('ALTER TABLE clientes ADD COLUMN actualizado_en INTEGER');
          await tryExecute('ALTER TABLE clientes ADD COLUMN borrado_en INTEGER');
          await tryExecute(
              'CREATE UNIQUE INDEX IF NOT EXISTS uq_clientes_server_id ON clientes (server_id)');

          await tryExecute('ALTER TABLE productos ADD COLUMN server_id TEXT');
          await tryExecute('ALTER TABLE productos ADD COLUMN sync_version INTEGER');
          await tryExecute('ALTER TABLE productos ADD COLUMN borrado_en INTEGER');
            await tryExecute('ALTER TABLE productos ADD COLUMN imagen_url TEXT');
          await tryExecute(
              'CREATE UNIQUE INDEX IF NOT EXISTS uq_productos_server_id ON productos (server_id)');

          await tryExecute('ALTER TABLE ventas ADD COLUMN server_id TEXT');
          await tryExecute('ALTER TABLE ventas ADD COLUMN sync_version INTEGER');
          await tryExecute('ALTER TABLE ventas ADD COLUMN borrado_en INTEGER');
          await tryExecute(
              'CREATE UNIQUE INDEX IF NOT EXISTS uq_ventas_server_id ON ventas (server_id)');

          await tryExecute('''
CREATE TABLE IF NOT EXISTS sync_outbox (
  key TEXT PRIMARY KEY,
  op_id TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_server_id TEXT NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT,
  client_updated_at TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  try_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT
);
''');

          await tryExecute(
              'CREATE INDEX IF NOT EXISTS idx_sync_outbox_created_at ON sync_outbox (created_at)');
        }

        if (oldVersion < 15) {
          const tables = [
            'presupuestos',
            'presupuesto_items',
            'venta_items',
            'operaciones',
            'tecnicos',
            'operacion_materiales',
            'operacion_evidencias',
            'operacion_notas',
            'operacion_estados_historial',
            'usuarios',
            'usuarios_logins',
            'ponches',
            'nomina_ajustes',
            'beneficios_pagos',
          ];

          for (final table in tables) {
            await tryExecute('ALTER TABLE $table ADD COLUMN server_id TEXT');
            await tryExecute('ALTER TABLE $table ADD COLUMN sync_version INTEGER');
            await tryExecute('ALTER TABLE $table ADD COLUMN actualizado_en INTEGER');
            await tryExecute('ALTER TABLE $table ADD COLUMN borrado_en INTEGER');
            await tryExecute(
              'CREATE UNIQUE INDEX IF NOT EXISTS uq_${table}_server_id ON $table (server_id)',
            );
          }
        }

        if (oldVersion < 17) {
          await tryExecute('ALTER TABLE usuarios ADD COLUMN curriculum_url TEXT');
          await tryExecute('ALTER TABLE usuarios ADD COLUMN licencia_url TEXT');
          await tryExecute('ALTER TABLE usuarios ADD COLUMN cedula_foto_url TEXT');
          await tryExecute('ALTER TABLE usuarios ADD COLUMN carta_trabajo_url TEXT');

          await tryExecute('ALTER TABLE operacion_evidencias ADD COLUMN file_url TEXT');
        }

        if (oldVersion < 2) {
          await db.execute('ALTER TABLE usuarios ADD COLUMN password TEXT');
          await db.update('usuarios', {'password': '1234'},
              where: 'id = ?', whereArgs: [1]);
        }

        if (oldVersion < 3) {
          await db
              .execute('ALTER TABLE usuarios ADD COLUMN password_hash TEXT');

          if (oldVersion < 13) {
            await tryExecute(
                'ALTER TABLE operaciones ADD COLUMN tecnico_usuario_id INTEGER');
          }
          await db
              .execute('ALTER TABLE usuarios ADD COLUMN password_salt TEXT');

          final users = await db.query('usuarios');
          for (final u in users) {
            final id = (u['id'] as int?) ?? 0;
            final hash = (u['password_hash'] as String?)?.trim();
            if (id <= 0) continue;
            if (hash != null && hash.isNotEmpty) continue;

            final legacy = (u['password'] as String?) ?? '1234';
            final salt = _newSalt();
            final computed = _hashPassword(password: legacy, salt: salt);
            await db.update(
              'usuarios',
              {
                'password_salt': salt,
                'password_hash': computed,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          }

          // Promueve el demo a Admin para poder gestionar Usuarios.
          await db.update('usuarios', {'rol': 'Admin'},
              where: 'id = ?', whereArgs: [1]);
        }

        if (oldVersion < 4) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS categorias (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  creado_en INTEGER NOT NULL
);
''');

          await db.execute('''
CREATE TABLE IF NOT EXISTS productos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  categoria_id INTEGER,
  codigo TEXT NOT NULL,
  nombre TEXT NOT NULL,
  precio REAL NOT NULL,
  costo REAL NOT NULL,
  imagen_path TEXT,
  imagen_url TEXT,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER NOT NULL,
  FOREIGN KEY (categoria_id) REFERENCES categorias (id)
);
''');

          // Categoría por defecto si aún no existe ninguna.
          final existing = await db.query('categorias', limit: 1);
          if (existing.isEmpty) {
            await db.insert('categorias', {
              'nombre': 'General',
              'creado_en': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }

        if (oldVersion < 5) {
          // Migra ponches antiguos a los nuevos tipos para soportar filtros/resumen.
          await db.update('ponches', {'tipo': 'LABOR_ENTRADA'},
              where: 'tipo = ?', whereArgs: ['Entrada']);
          await db.update('ponches', {'tipo': 'LABOR_SALIDA'},
              where: 'tipo = ?', whereArgs: ['Salida']);
        }

        if (oldVersion < 5) {
          await tryExecute('ALTER TABLE usuarios ADD COLUMN usuario TEXT');
          await tryExecute('ALTER TABLE usuarios ADD COLUMN cedula TEXT');
          await tryExecute('ALTER TABLE usuarios ADD COLUMN direccion TEXT');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN sueldo_quincenal REAL');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN meta_quincenal REAL');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN fecha_ingreso INTEGER');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN curriculum_path TEXT');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN licencia_path TEXT');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN cedula_foto_path TEXT');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN carta_trabajo_path TEXT');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN bloqueado INTEGER NOT NULL DEFAULT 0');
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN ultimo_login INTEGER');

          await tryExecute('''
CREATE TABLE IF NOT EXISTS usuarios_logins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id INTEGER NOT NULL,
  hora INTEGER NOT NULL,
  exitoso INTEGER NOT NULL,
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

          // Asegura un usuario demo coherente con el nuevo login por "usuario".
          try {
            await db.update(
              'usuarios',
              {
                'usuario': 'demo',
                'bloqueado': 0,
              },
              where: 'id = ? AND (usuario IS NULL OR TRIM(usuario) = "")',
              whereArgs: [1],
            );
          } catch (_) {}
        }

        if (oldVersion < 5) {
          // Presupuestos (cotizaciones) configuración de totales
          await db.execute(
              'ALTER TABLE presupuestos ADD COLUMN itbis_activo INTEGER NOT NULL DEFAULT 1');
          await db.execute(
              'ALTER TABLE presupuestos ADD COLUMN itbis_tasa REAL NOT NULL DEFAULT 0.18');
          await db.execute(
              'ALTER TABLE presupuestos ADD COLUMN descuento_global REAL NOT NULL DEFAULT 0');

          // Items del presupuesto
          await db.execute('''
CREATE TABLE IF NOT EXISTS presupuesto_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  presupuesto_id INTEGER NOT NULL,
  producto_id INTEGER,
  codigo TEXT,
  nombre TEXT NOT NULL,
  precio REAL NOT NULL,
  cantidad REAL NOT NULL,
  descuento REAL NOT NULL,
  creado_en INTEGER NOT NULL,
  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos (id)
);
''');

          // Migra los ponches legacy a nuevos tipos para tener consistencia.
          await db.update('ponches', {'tipo': 'LABOR_ENTRADA'},
              where: 'tipo = ?', whereArgs: ['Entrada']);
          await db.update('ponches', {'tipo': 'LABOR_SALIDA'},
              where: 'tipo = ?', whereArgs: ['Salida']);
        }

        if (oldVersion < 6) {
          // Técnicos
          await db.execute('''
      CREATE TABLE IF NOT EXISTS tecnicos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        telefono TEXT,
        especialidad TEXT NOT NULL,
        estado TEXT NOT NULL,
        creado_en INTEGER NOT NULL,
        actualizado_en INTEGER NOT NULL
      );
      ''');

          // Evoluciona operaciones a un modelo real (agrega columnas sin romper legacy).
          await tryExecute('ALTER TABLE operaciones ADD COLUMN codigo TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN tipo_servicio TEXT');
          await tryExecute('ALTER TABLE operaciones ADD COLUMN prioridad TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN tecnico_id INTEGER');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN programado_en INTEGER');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN hora_estimada TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN direccion_servicio TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN referencia_lugar TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN descripcion TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN observaciones_iniciales TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN observaciones_finales TEXT');
          await tryExecute('ALTER TABLE operaciones ADD COLUMN monto REAL');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN forma_pago TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN pago_estado TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN pago_abono REAL');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN chk_llego INTEGER NOT NULL DEFAULT 0');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN chk_material_instalado INTEGER NOT NULL DEFAULT 0');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN chk_sistema_probado INTEGER NOT NULL DEFAULT 0');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN chk_cliente_capacitado INTEGER NOT NULL DEFAULT 0');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN chk_trabajo_terminado INTEGER NOT NULL DEFAULT 0');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN garantia_tipo TEXT');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN garantia_vence_en INTEGER');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN actualizado_en INTEGER');
          await tryExecute(
              'ALTER TABLE operaciones ADD COLUMN finalizado_en INTEGER');

          // Lista de materiales requeridos
          await db.execute('''
      CREATE TABLE IF NOT EXISTS operacion_materiales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operacion_id INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        creado_en INTEGER NOT NULL,
        FOREIGN KEY (operacion_id) REFERENCES operaciones (id)
      );
      ''');

          // Evidencias (antes/durante/después)
          await db.execute('''
      CREATE TABLE IF NOT EXISTS operacion_evidencias (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operacion_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        file_path TEXT NOT NULL,
        creado_en INTEGER NOT NULL,
        FOREIGN KEY (operacion_id) REFERENCES operaciones (id)
      );
      ''');

          // Notas del técnico (historial, nunca se borra)
          await db.execute('''
      CREATE TABLE IF NOT EXISTS operacion_notas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operacion_id INTEGER NOT NULL,
        usuario_id INTEGER,
        nota TEXT NOT NULL,
        creado_en INTEGER NOT NULL,
        FOREIGN KEY (operacion_id) REFERENCES operaciones (id),
        FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
      );
      ''');

          // Historial de estados (todo cambio queda registrado)
          await db.execute('''
      CREATE TABLE IF NOT EXISTS operacion_estados_historial (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operacion_id INTEGER NOT NULL,
        de_estado TEXT,
        a_estado TEXT NOT NULL,
        usuario_id INTEGER,
        creado_en INTEGER NOT NULL,
        FOREIGN KEY (operacion_id) REFERENCES operaciones (id),
        FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
      );
      ''');

          // Migración suave: usa campos antiguos como fallback.
          final ops = await db.query('operaciones');
          for (final o in ops) {
            final id = (o['id'] as int?) ?? 0;
            if (id <= 0) continue;

            final codigo = (o['codigo'] as String?)?.trim();
            final tipo = (o['tipo_servicio'] as String?)?.trim();
            final titulo = (o['titulo'] as String?)?.trim() ?? 'Operación';
            final detalle = (o['detalle'] as String?)?.trim() ?? '';
            final creado = (o['creado_en'] as int?) ??
                DateTime.now().millisecondsSinceEpoch;

            await db.update(
              'operaciones',
              {
                'codigo':
                    (codigo == null || codigo.isEmpty) ? 'OP-$id' : codigo,
                'tipo_servicio': (tipo == null || tipo.isEmpty) ? titulo : tipo,
                'prioridad': (o['prioridad'] as String?) ?? 'Normal',
                'descripcion': (o['descripcion'] as String?) ??
                    (detalle.isEmpty ? null : detalle),
                'observaciones_iniciales':
                    (o['observaciones_iniciales'] as String?) ?? null,
                'pago_estado': (o['pago_estado'] as String?) ?? 'Pendiente',
                'actualizado_en': (o['actualizado_en'] as int?) ?? creado,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }

        if (oldVersion < 7) {
          await tryExecute('ALTER TABLE ventas ADD COLUMN usuario_id INTEGER');
          await tryExecute(
            'ALTER TABLE ventas ADD COLUMN ganancia REAL NOT NULL DEFAULT 0',
          );
          await tryExecute(
            'ALTER TABLE ventas ADD COLUMN puntos REAL NOT NULL DEFAULT 0',
          );
          await tryExecute(
              'ALTER TABLE ventas ADD COLUMN actualizado_en INTEGER');

          await db.execute('''
CREATE TABLE IF NOT EXISTS venta_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  venta_id INTEGER NOT NULL,
  producto_id INTEGER,
  codigo TEXT,
  nombre TEXT NOT NULL,
  cantidad REAL NOT NULL,
  precio REAL NOT NULL,
  costo REAL NOT NULL,
  creado_en INTEGER NOT NULL,
  FOREIGN KEY (venta_id) REFERENCES ventas (id),
  FOREIGN KEY (producto_id) REFERENCES productos (id)
);
''');
        }

        if (oldVersion < 8) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS nomina_ajustes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id INTEGER NOT NULL,
  periodo_inicio INTEGER NOT NULL,
  periodo_fin INTEGER NOT NULL,
  tipo TEXT NOT NULL,
  monto REAL NOT NULL,
  nota TEXT,
  creado_en INTEGER NOT NULL,
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

          await db.execute('''
CREATE TABLE IF NOT EXISTS beneficios_pagos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id INTEGER NOT NULL,
  periodo_inicio INTEGER NOT NULL,
  periodo_fin INTEGER NOT NULL,
  pago_en INTEGER NOT NULL,
  sueldo_base REAL NOT NULL,
  comision REAL NOT NULL,
  ajustes REAL NOT NULL,
  neto REAL NOT NULL,
  estado TEXT NOT NULL,
  creado_en INTEGER NOT NULL,
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

          await tryExecute(
              'CREATE INDEX IF NOT EXISTS idx_nomina_ajustes_periodo_usuario ON nomina_ajustes (periodo_inicio, periodo_fin, usuario_id)');
          await tryExecute(
              'CREATE UNIQUE INDEX IF NOT EXISTS uq_beneficios_pago_usuario_periodo ON beneficios_pagos (usuario_id, periodo_inicio, periodo_fin)');
        }

        if (oldVersion < 9) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS empresa_config (
  id INTEGER PRIMARY KEY,
  nombre TEXT,
  rnc TEXT,
  telefono TEXT,
  email TEXT,
  direccion TEXT,
  web TEXT,
  logo_path TEXT,
  info_general TEXT,
  info_especial TEXT,
  actualizado_en INTEGER
);
''');
        }

        if (oldVersion < 10) {
          // Salvaguarda: algunos DBs pueden tener user_version=9 sin esta tabla.
          await _ensureEmpresaConfigTable(db);
        }

        if (oldVersion < 11) {
          await tryExecute(
              'ALTER TABLE usuarios ADD COLUMN empleado_mes INTEGER NOT NULL DEFAULT 0');
          await _ensureEmpresaConfigTable(db);
          await tryExecute(
              'ALTER TABLE empresa_config ADD COLUMN info_general TEXT');
          await tryExecute(
              'ALTER TABLE empresa_config ADD COLUMN info_especial TEXT');
        }

        if (oldVersion < 12) {
          await _ensureEmpresaConfigTable(db);
          await tryExecute(
              'ALTER TABLE empresa_config ADD COLUMN horario_json TEXT');
          await tryExecute(
              'ALTER TABLE empresa_config ADD COLUMN ubicacion_lat REAL');
          await tryExecute(
              'ALTER TABLE empresa_config ADD COLUMN ubicacion_lon REAL');
        }
      },
    );
  }

  Future<void> _ensureEmpresaConfigTable(sqflite.Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS empresa_config (
  id INTEGER PRIMARY KEY,
  nombre TEXT,
  rnc TEXT,
  telefono TEXT,
  email TEXT,
  direccion TEXT,
  web TEXT,
  logo_path TEXT,
  info_general TEXT,
  info_especial TEXT,
  horario_json TEXT,
  ubicacion_lat REAL,
  ubicacion_lon REAL,
  actualizado_en INTEGER
);
''');

    // Si la tabla ya existía sin estas columnas, las agregamos.
    try {
      await db
          .execute('ALTER TABLE empresa_config ADD COLUMN info_general TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE empresa_config ADD COLUMN info_especial TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE empresa_config ADD COLUMN horario_json TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE empresa_config ADD COLUMN ubicacion_lat REAL');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE empresa_config ADD COLUMN ubicacion_lon REAL');
    } catch (_) {}
  }

  Future<void> _ensureProductosColumns(sqflite.Database db) async {
    try {
      await db.execute('ALTER TABLE productos ADD COLUMN imagen_url TEXT');
    } catch (_) {}
  }

  /// Repara el esquema mínimo de la base de datos.
  ///
  /// Útil si el usuario copió una DB vieja o quedó en un estado inconsistente.
  /// No borra datos; sólo crea tablas/índices faltantes.
  Future<void> repairSchema() async {
    await init();

    final database = db;
    await _ensureEmpresaConfigTable(database);
    await _ensureProductosColumns(database);

    try {
      await database.execute(
          'ALTER TABLE usuarios ADD COLUMN empleado_mes INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}

    try {
      await database.execute(
          'ALTER TABLE operaciones ADD COLUMN tecnico_usuario_id INTEGER');
    } catch (_) {}

    // Índices: no deberían ser requeridos para correr, pero ayudan
    // y evitamos errores si se perdieron.
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_nomina_ajustes_periodo_usuario ON nomina_ajustes (periodo_inicio, periodo_fin, usuario_id)',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_beneficios_pago_usuario_periodo ON beneficios_pagos (usuario_id, periodo_inicio, periodo_fin)',
    );

    _changes.add(null);
  }

  sqflite.Database get db {
    final database = _db;
    if (database == null) {
      throw StateError(
          'Database not initialized. Call AppDatabase.instance.init() first.');
    }
    return database;
  }

  Future<String> _getDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'fulltech.db');
  }

  Future<void> _createSchema(sqflite.Database db) async {
    await db.execute('''
CREATE TABLE clientes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  nombre TEXT NOT NULL,
  telefono TEXT,
  email TEXT,
  direccion TEXT,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER
);
''');

    await db.execute('''
CREATE TABLE ventas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  usuario_id INTEGER,
  cliente_id INTEGER,
  codigo TEXT,
  total REAL NOT NULL,
  ganancia REAL NOT NULL DEFAULT 0,
  puntos REAL NOT NULL DEFAULT 0,
  moneda TEXT NOT NULL,
  notas TEXT,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (cliente_id) REFERENCES clientes (id),
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

    await db.execute('''
CREATE TABLE venta_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  venta_id INTEGER NOT NULL,
  producto_id INTEGER,
  codigo TEXT,
  nombre TEXT NOT NULL,
  cantidad REAL NOT NULL,
  precio REAL NOT NULL,
  costo REAL NOT NULL,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (venta_id) REFERENCES ventas (id),
  FOREIGN KEY (producto_id) REFERENCES productos (id)
);
''');

    await db.execute('''
CREATE TABLE presupuestos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  cliente_id INTEGER,
  codigo TEXT,
  total REAL NOT NULL,
  moneda TEXT NOT NULL,
  estado TEXT NOT NULL,
  notas TEXT,
  itbis_activo INTEGER NOT NULL,
  itbis_tasa REAL NOT NULL,
  descuento_global REAL NOT NULL,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (cliente_id) REFERENCES clientes (id)
);
''');

    await db.execute('''
CREATE TABLE presupuesto_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  presupuesto_id INTEGER NOT NULL,
  producto_id INTEGER,
  codigo TEXT,
  nombre TEXT NOT NULL,
  precio REAL NOT NULL,
  cantidad REAL NOT NULL,
  descuento REAL NOT NULL,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (presupuesto_id) REFERENCES presupuestos (id)
);
''');

    await db.execute('''
CREATE TABLE operaciones (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  cliente_id INTEGER,
  codigo TEXT NOT NULL,
  titulo TEXT,
  tipo_servicio TEXT NOT NULL,
  prioridad TEXT NOT NULL,
  estado TEXT NOT NULL,
  tecnico_id INTEGER,
  tecnico_usuario_id INTEGER,
  programado_en INTEGER,
  hora_estimada TEXT,
  direccion_servicio TEXT,
  referencia_lugar TEXT,
  descripcion TEXT,
  observaciones_iniciales TEXT,
  observaciones_finales TEXT,
  monto REAL,
  forma_pago TEXT,
  pago_estado TEXT,
  pago_abono REAL,
  chk_llego INTEGER NOT NULL,
  chk_material_instalado INTEGER NOT NULL,
  chk_sistema_probado INTEGER NOT NULL,
  chk_cliente_capacitado INTEGER NOT NULL,
  chk_trabajo_terminado INTEGER NOT NULL,
  garantia_tipo TEXT,
  garantia_vence_en INTEGER,
  actualizado_en INTEGER NOT NULL,
  finalizado_en INTEGER,
  creado_en INTEGER NOT NULL,
  borrado_en INTEGER,
  FOREIGN KEY (cliente_id) REFERENCES clientes (id)
);
''');

    await db.execute('''
CREATE TABLE tecnicos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  nombre TEXT NOT NULL,
  telefono TEXT,
  especialidad TEXT NOT NULL,
  estado TEXT NOT NULL,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER NOT NULL,
  borrado_en INTEGER
);
''');

    await db.execute('''
CREATE TABLE operacion_materiales (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  operacion_id INTEGER NOT NULL,
  nombre TEXT NOT NULL,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (operacion_id) REFERENCES operaciones (id)
);
''');

    await db.execute('''
CREATE TABLE operacion_evidencias (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  operacion_id INTEGER NOT NULL,
  tipo TEXT NOT NULL,
  file_path TEXT NOT NULL,
  file_url TEXT,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (operacion_id) REFERENCES operaciones (id)
);
''');

    await db.execute('''
CREATE TABLE operacion_notas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  operacion_id INTEGER NOT NULL,
  usuario_id INTEGER,
  nota TEXT NOT NULL,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (operacion_id) REFERENCES operaciones (id),
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

    await db.execute('''
CREATE TABLE operacion_estados_historial (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  operacion_id INTEGER NOT NULL,
  de_estado TEXT,
  a_estado TEXT NOT NULL,
  usuario_id INTEGER,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (operacion_id) REFERENCES operaciones (id),
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

    await db.execute('''
CREATE TABLE usuarios (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  nombre TEXT NOT NULL,
  usuario TEXT,
  rol TEXT NOT NULL,
  email TEXT,
  password TEXT,
  password_hash TEXT,
  password_salt TEXT,
  cedula TEXT,
  direccion TEXT,
  sueldo_quincenal REAL,
  meta_quincenal REAL,
  empleado_mes INTEGER NOT NULL DEFAULT 0,
  fecha_ingreso INTEGER,
  curriculum_path TEXT,
  licencia_path TEXT,
  cedula_foto_path TEXT,
  carta_trabajo_path TEXT,
  curriculum_url TEXT,
  licencia_url TEXT,
  cedula_foto_url TEXT,
  carta_trabajo_url TEXT,
  bloqueado INTEGER NOT NULL DEFAULT 0,
  ultimo_login INTEGER,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER
);
''');

    await db.execute('''
CREATE TABLE usuarios_logins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  usuario_id INTEGER NOT NULL,
  hora INTEGER NOT NULL,
  exitoso INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

    await db.execute('''
CREATE TABLE ponches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  usuario_id INTEGER,
  tipo TEXT NOT NULL,
  hora INTEGER NOT NULL,
  ubicacion TEXT,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

    await db.execute('''
CREATE TABLE categorias (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  creado_en INTEGER NOT NULL
);
''');

    await db.execute('''
CREATE TABLE productos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  categoria_id INTEGER,
  codigo TEXT NOT NULL,
  nombre TEXT NOT NULL,
  precio REAL NOT NULL,
  costo REAL NOT NULL,
  imagen_path TEXT,
  imagen_url TEXT,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER NOT NULL,
  borrado_en INTEGER,
  FOREIGN KEY (categoria_id) REFERENCES categorias (id)
);
''');

    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_clientes_server_id ON clientes (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_productos_server_id ON productos (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_ventas_server_id ON ventas (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_venta_items_server_id ON venta_items (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_presupuestos_server_id ON presupuestos (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_presupuesto_items_server_id ON presupuesto_items (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_operaciones_server_id ON operaciones (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_tecnicos_server_id ON tecnicos (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_operacion_materiales_server_id ON operacion_materiales (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_operacion_evidencias_server_id ON operacion_evidencias (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_operacion_notas_server_id ON operacion_notas (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_operacion_estados_server_id ON operacion_estados_historial (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_server_id ON usuarios (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_logins_server_id ON usuarios_logins (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_ponches_server_id ON ponches (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_nomina_ajustes_server_id ON nomina_ajustes (server_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_beneficios_pagos_server_id ON beneficios_pagos (server_id)');

    await db.execute('''
CREATE TABLE IF NOT EXISTS sync_outbox (
  key TEXT PRIMARY KEY,
  op_id TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_server_id TEXT NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT,
  client_updated_at TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  try_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT
);
''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_outbox_created_at ON sync_outbox (created_at)');

    await db.execute('''
CREATE TABLE nomina_ajustes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  usuario_id INTEGER NOT NULL,
  periodo_inicio INTEGER NOT NULL,
  periodo_fin INTEGER NOT NULL,
  tipo TEXT NOT NULL,
  monto REAL NOT NULL,
  nota TEXT,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

    await db.execute('''
CREATE TABLE beneficios_pagos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id TEXT,
  sync_version INTEGER,
  usuario_id INTEGER NOT NULL,
  periodo_inicio INTEGER NOT NULL,
  periodo_fin INTEGER NOT NULL,
  pago_en INTEGER NOT NULL,
  sueldo_base REAL NOT NULL,
  comision REAL NOT NULL,
  ajustes REAL NOT NULL,
  neto REAL NOT NULL,
  estado TEXT NOT NULL,
  creado_en INTEGER NOT NULL,
  actualizado_en INTEGER,
  borrado_en INTEGER,
  FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
);
''');

    await db.execute('''
CREATE TABLE empresa_config (
  id INTEGER PRIMARY KEY,
  nombre TEXT,
  rnc TEXT,
  telefono TEXT,
  email TEXT,
  direccion TEXT,
  web TEXT,
  logo_path TEXT,
  info_general TEXT,
  info_especial TEXT,
  horario_json TEXT,
  ubicacion_lat REAL,
  ubicacion_lon REAL,
  actualizado_en INTEGER
);
''');

    await db.execute(
        'CREATE INDEX idx_nomina_ajustes_periodo_usuario ON nomina_ajustes (periodo_inicio, periodo_fin, usuario_id)');
    await db.execute(
        'CREATE UNIQUE INDEX uq_beneficios_pago_usuario_periodo ON beneficios_pagos (usuario_id, periodo_inicio, periodo_fin)');

    await db.insert('usuarios', {
      'nombre': 'Usuario Demo',
      'usuario': 'demo',
      'rol': 'Admin',
      'email': 'demo@fulltech.com',
      'password': '1234',
      'password_salt': 'demo',
      'password_hash': _hashPassword(password: '1234', salt: 'demo'),
      'cedula': '0000000000',
      'direccion': '—',
      'sueldo_quincenal': 0,
      'meta_quincenal': 0,
      'fecha_ingreso': DateTime.now().millisecondsSinceEpoch,
      'bloqueado': 0,
      'creado_en': DateTime.now().millisecondsSinceEpoch,
    });

    await db.insert('categorias', {
      'nombre': 'General',
      'creado_en': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static String _newSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hashPassword(
      {required String password, required String salt}) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  Future<List<Map<String, Object?>>> queryAll(String table,
      {String? orderBy}) async {
    return db.query(table, orderBy: orderBy);
  }

  Future<int> insert(String table, Map<String, Object?> values) async {
    final id = await db.insert(table, values);
    _changes.add(null);

    if (SyncOutbox.isSyncTable(table)) {
      try {
        final cloud = await CloudSettings.load();
        if (cloud.enabled) {
          await SyncOutbox.enqueueUpsert(db: db, table: table, localId: id);
        }
      } catch (_) {
        // Never crash on sync bookkeeping.
      }
    }

    return id;
  }

  Future<int> update(String table, Map<String, Object?> values,
      {required int id}) async {
    if (SyncOutbox.isSyncTable(table)) {
      if (!values.containsKey('actualizado_en')) {
        values = Map<String, Object?>.from(values);
        values['actualizado_en'] = DateTime.now().millisecondsSinceEpoch;
      }
    }

    final count =
        await db.update(table, values, where: 'id = ?', whereArgs: [id]);
    _changes.add(null);

    if (count > 0 && SyncOutbox.isSyncTable(table)) {
      try {
        final cloud = await CloudSettings.load();
        if (cloud.enabled) {
          await SyncOutbox.enqueueUpsert(db: db, table: table, localId: id);
        }
      } catch (_) {}
    }
    return count;
  }

  Future<int> delete(String table, {required int id}) async {
    if (SyncOutbox.isSyncTable(table)) {
      try {
        final cloud = await CloudSettings.load();
        if (cloud.enabled) {
          await SyncOutbox.enqueueDelete(db: db, table: table, localId: id);
        }
      } catch (_) {}
    }
    final count = await db.delete(table, where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
    return count;
  }

  Future<int> deleteWhere(
    String table, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final count = await db.delete(table, where: where, whereArgs: whereArgs);
    _changes.add(null);
    return count;
  }

  Future<Map<String, Object?>?> findById(String table, int id) async {
    final rows =
        await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, Object?>?> getEmpresaConfig() async {
    try {
      final rows = await db.query(
        'empresa_config',
        where: 'id = ?',
        whereArgs: const [1],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('no such table') &&
          message.contains('empresa_config')) {
        await _ensureEmpresaConfigTable(db);
        final rows = await db.query(
          'empresa_config',
          where: 'id = ?',
          whereArgs: const [1],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return rows.first;
      }
      rethrow;
    }
  }

  Future<void> upsertEmpresaConfig({
    String? nombre,
    String? rnc,
    String? telefono,
    String? email,
    String? direccion,
    String? web,
    String? logoPath,
    String? infoGeneral,
    String? infoEspecial,
    String? horarioJson,
    double? ubicacionLat,
    double? ubicacionLon,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await db.insert(
        'empresa_config',
        {
          'id': 1,
          'nombre': (nombre ?? '').trim().isEmpty ? null : nombre!.trim(),
          'rnc': (rnc ?? '').trim().isEmpty ? null : rnc!.trim(),
          'telefono': (telefono ?? '').trim().isEmpty ? null : telefono!.trim(),
          'email': (email ?? '').trim().isEmpty ? null : email!.trim(),
          'direccion':
              (direccion ?? '').trim().isEmpty ? null : direccion!.trim(),
          'web': (web ?? '').trim().isEmpty ? null : web!.trim(),
          'logo_path':
              (logoPath ?? '').trim().isEmpty ? null : logoPath!.trim(),
          'info_general':
              (infoGeneral ?? '').trim().isEmpty ? null : infoGeneral!.trim(),
          'info_especial':
              (infoEspecial ?? '').trim().isEmpty ? null : infoEspecial!.trim(),
          'horario_json':
              (horarioJson ?? '').trim().isEmpty ? null : horarioJson!.trim(),
          'ubicacion_lat': ubicacionLat,
          'ubicacion_lon': ubicacionLon,
          'actualizado_en': now,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
      _changes.add(null);
    } catch (e) {
      final message = e.toString().toLowerCase();
      if ((message.contains('no such table') &&
              message.contains('empresa_config')) ||
          (message.contains('no such column') &&
              message.contains('empresa_config')) ||
          message.contains('has no column named')) {
        await _ensureEmpresaConfigTable(db);
        await db.insert(
          'empresa_config',
          {
            'id': 1,
            'nombre': (nombre ?? '').trim().isEmpty ? null : nombre!.trim(),
            'rnc': (rnc ?? '').trim().isEmpty ? null : rnc!.trim(),
            'telefono':
                (telefono ?? '').trim().isEmpty ? null : telefono!.trim(),
            'email': (email ?? '').trim().isEmpty ? null : email!.trim(),
            'direccion':
                (direccion ?? '').trim().isEmpty ? null : direccion!.trim(),
            'web': (web ?? '').trim().isEmpty ? null : web!.trim(),
            'logo_path':
                (logoPath ?? '').trim().isEmpty ? null : logoPath!.trim(),
            'info_general':
                (infoGeneral ?? '').trim().isEmpty ? null : infoGeneral!.trim(),
            'info_especial': (infoEspecial ?? '').trim().isEmpty
                ? null
                : infoEspecial!.trim(),
            'horario_json':
                (horarioJson ?? '').trim().isEmpty ? null : horarioJson!.trim(),
            'ubicacion_lat': ubicacionLat,
            'ubicacion_lon': ubicacionLon,
            'actualizado_en': now,
          },
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
        _changes.add(null);
        return;
      }
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _changes.close();
    await _db?.close();
    _db = null;
  }
}
