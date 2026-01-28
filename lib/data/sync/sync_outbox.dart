import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local outbox for offline-first sync.
///
/// We store ONE pending op per entity+type (UPSERT/DELETE).
/// The record is replaced on subsequent edits, so we always push the latest.
class SyncOutbox {
  static const _uuid = Uuid();

  static const syncTables = <String, String>{
    // localTable -> backend entity
    'clientes': 'customers',
    'productos': 'products',
    'ventas': 'sales',
    'venta_items': 'sale_items',
    'presupuestos': 'quotes',
    'presupuesto_items': 'quote_items',
    'operaciones': 'operations',
    'tecnicos': 'technicians',
    'operacion_materiales': 'operation_materials',
    'operacion_evidencias': 'operation_evidences',
    'operacion_notas': 'operation_notes',
    'operacion_estados_historial': 'operation_statuses',
    'usuarios': 'employees',
    'usuarios_logins': 'employee_logins',
    'nomina_ajustes': 'payroll_adjustments',
    'beneficios_pagos': 'payroll_payments',
    'ponches': 'punches',
  };

  static bool isSyncTable(String table) => syncTables.containsKey(table);

  static String _key({required String entity, required String entityId, required String type}) {
    return '$entity:$entityId:$type';
  }

  static String _nowIsoUtc() => DateTime.now().toUtc().toIso8601String();

  static Future<String?> ensureServerId({
    required Database db,
    required String table,
    required int localId,
  }) async {
    if (!isSyncTable(table)) return null;

    final rows = await db.query(
      table,
      columns: const ['server_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final current = (rows.first['server_id'] as String?)?.trim();
    if (current != null && current.isNotEmpty) return current;

    final serverId = _uuid.v4();
    await db.update(
      table,
      {'server_id': serverId},
      where: 'id = ?',
      whereArgs: [localId],
    );
    return serverId;
  }

  static Future<void> enqueueUpsert({
    required Database db,
    required String table,
    required int localId,
  }) async {
    final entity = syncTables[table];
    if (entity == null) return;

    final serverId = await ensureServerId(db: db, table: table, localId: localId);
    if (serverId == null) return;

    final row = await _loadRow(db: db, table: table, localId: localId);
    if (row == null) return;

    final payload = await _toPayload(db: db, table: table, row: row);

    final nowIso = _nowIsoUtc();
    final createdAt = DateTime.now().millisecondsSinceEpoch;

    final type = 'UPSERT';
    final key = _key(entity: entity, entityId: serverId, type: type);

    await db.insert(
      'sync_outbox',
      {
        'key': key,
        'op_id': _uuid.v4(),
        'entity': entity,
        'entity_server_id': serverId,
        'type': type,
        'payload_json': jsonEncode(payload),
        'client_updated_at': nowIso,
        'created_at': createdAt,
        'try_count': 0,
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> enqueueDelete({
    required Database db,
    required String table,
    required int localId,
  }) async {
    final entity = syncTables[table];
    if (entity == null) return;

    final rows = await db.query(
      table,
      columns: const ['server_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final serverId = (rows.first['server_id'] as String?)?.trim();
    if (serverId == null || serverId.isEmpty) {
      // Never synced, so nothing to delete on the server.
      return;
    }

    final nowIso = _nowIsoUtc();
    final createdAt = DateTime.now().millisecondsSinceEpoch;

    final type = 'DELETE';
    final key = _key(entity: entity, entityId: serverId, type: type);

    await db.insert(
      'sync_outbox',
      {
        'key': key,
        'op_id': _uuid.v4(),
        'entity': entity,
        'entity_server_id': serverId,
        'type': type,
        'payload_json': null,
        'client_updated_at': nowIso,
        'created_at': createdAt,
        'try_count': 0,
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // If we're deleting, an older UPSERT for the same entity should not be sent.
    // This is naturally handled by the key uniqueness, but in case the UPSERT key
    // differs, remove it explicitly.
    final upsertKey = _key(entity: entity, entityId: serverId, type: 'UPSERT');
    if (upsertKey != key) {
      await db.delete('sync_outbox', where: 'key = ?', whereArgs: [upsertKey]);
    }
  }

  static Future<Map<String, Object?>?> _loadRow({
    required Database db,
    required String table,
    required int localId,
  }) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }


  static String? _msToIso(int? ms) {
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms).toUtc().toIso8601String();
  }

  static Future<Map<String, dynamic>> _toPayload({
    required Database db,
    required String table,
    required Map<String, Object?> row,
  }) async {
    if (table == 'clientes') {
      return {
        'name': (row['nombre'] as String? ?? '').trim(),
        'email': (row['email'] as String?)?.trim(),
        'phone': (row['telefono'] as String?)?.trim(),
        'address': (row['direccion'] as String?)?.trim(),
      };
    }

    if (table == 'productos') {
      final price = row['precio'];
      String? categoryName;
      final categoriaId = row['categoria_id'] as int?;
      if (categoriaId != null) {
        final rows = await db.query(
          'categorias',
          columns: const ['nombre'],
          where: 'id = ?',
          whereArgs: [categoriaId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          categoryName = (rows.first['nombre'] as String?)?.trim();
        }
      }
      if (categoryName == null || categoryName.isEmpty) {
        categoryName = 'General';
      }
      return {
        'name': (row['nombre'] as String? ?? '').trim(),
        'sku': (row['codigo'] as String?)?.trim(),
        'price': price,
        'imageUrl': (row['imagen_url'] as String?)?.trim(),
        'category': categoryName,
      };
    }

    if (table == 'usuarios') {
      final salary = row['sueldo_quincenal'];
      final goal = row['meta_quincenal'];
      final empleadoMes = (row['empleado_mes'] as int?) ?? 0;
      final bloqueado = (row['bloqueado'] as int?) ?? 0;
      return {
        'name': (row['nombre'] as String? ?? '').trim(),
        'username': (row['usuario'] as String?)?.trim(),
        'role': (row['rol'] as String? ?? 'Usuario').trim(),
        'email': (row['email'] as String?)?.trim(),
        'passwordLegacy': (row['password'] as String?)?.trim(),
        'passwordHash': (row['password_hash'] as String?)?.trim(),
        'passwordSalt': (row['password_salt'] as String?)?.trim(),
        'cedula': (row['cedula'] as String?)?.trim(),
        'address': (row['direccion'] as String?)?.trim(),
        'salaryBiweekly': salary,
        'goalBiweekly': goal,
        'employeeOfMonth': empleadoMes == 1,
        'hireDate': _msToIso(row['fecha_ingreso'] as int?),
        'curriculumPath': (row['curriculum_path'] as String?)?.trim(),
        'curriculumUrl': (row['curriculum_url'] as String?)?.trim(),
        'licensePath': (row['licencia_path'] as String?)?.trim(),
        'licenseUrl': (row['licencia_url'] as String?)?.trim(),
        'idCardPhotoPath': (row['cedula_foto_path'] as String?)?.trim(),
        'idCardPhotoUrl': (row['cedula_foto_url'] as String?)?.trim(),
        'lastJobPath': (row['carta_trabajo_path'] as String?)?.trim(),
        'lastJobUrl': (row['carta_trabajo_url'] as String?)?.trim(),
        'blocked': bloqueado == 1,
        'lastLoginAt': _msToIso(row['ultimo_login'] as int?),
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'usuarios_logins') {
      String? employeeServerId;
      final usuarioId = row['usuario_id'] as int?;
      if (usuarioId != null) {
        employeeServerId =
            await ensureServerId(db: db, table: 'usuarios', localId: usuarioId);
      }

      final ok = ((row['exitoso'] as int?) ?? 0) == 1;
      final timeIso =
          _msToIso(row['hora'] as int?) ?? DateTime.now().toUtc().toIso8601String();
      return {
        'employeeId': employeeServerId,
        'time': timeIso,
        'success': ok,
        'createdAt': timeIso,
      };
    }

    if (table == 'tecnicos') {
      return {
        'name': (row['nombre'] as String? ?? '').trim(),
        'phone': (row['telefono'] as String?)?.trim(),
        'specialty': (row['especialidad'] as String? ?? '').trim(),
        'status': (row['estado'] as String? ?? '').trim(),
        'createdAt': _msToIso(row['creado_en'] as int?),
        'updatedAt': _msToIso(row['actualizado_en'] as int?),
      };
    }

    if (table == 'operaciones') {
      String? customerServerId;
      final clienteId = row['cliente_id'] as int?;
      if (clienteId != null) {
        customerServerId =
            await ensureServerId(db: db, table: 'clientes', localId: clienteId);
      }

      String? technicianServerId;
      final tecnicoId = row['tecnico_id'] as int?;
      if (tecnicoId != null) {
        technicianServerId =
            await ensureServerId(db: db, table: 'tecnicos', localId: tecnicoId);
      }

      String? technicianEmployeeServerId;
      final tecnicoUsuarioId = row['tecnico_usuario_id'] as int?;
      if (tecnicoUsuarioId != null) {
        technicianEmployeeServerId = await ensureServerId(
            db: db, table: 'usuarios', localId: tecnicoUsuarioId);
      }

      return {
        'customerId': customerServerId,
        'code': (row['codigo'] as String? ?? '').trim(),
        'title': (row['titulo'] as String?)?.trim(),
        'serviceType': (row['tipo_servicio'] as String? ?? '').trim(),
        'priority': (row['prioridad'] as String? ?? '').trim(),
        'status': (row['estado'] as String? ?? '').trim(),
        'technicianId': technicianServerId,
        'technicianEmployeeId': technicianEmployeeServerId,
        'scheduledAt': _msToIso(row['programado_en'] as int?),
        'estimatedTime': (row['hora_estimada'] as String?)?.trim(),
        'serviceAddress': (row['direccion_servicio'] as String?)?.trim(),
        'locationRef': (row['referencia_lugar'] as String?)?.trim(),
        'description': (row['descripcion'] as String?)?.trim(),
        'initialObservations': (row['observaciones_iniciales'] as String?)?.trim(),
        'finalObservations': (row['observaciones_finales'] as String?)?.trim(),
        'amount': row['monto'],
        'paymentMethod': (row['forma_pago'] as String?)?.trim(),
        'paymentStatus': (row['pago_estado'] as String?)?.trim(),
        'paymentPaidAmount': row['pago_abono'],
        'chkArrived': ((row['chk_llego'] as int?) ?? 0) == 1,
        'chkMaterialInstalled':
            ((row['chk_material_instalado'] as int?) ?? 0) == 1,
        'chkSystemTested':
            ((row['chk_sistema_probado'] as int?) ?? 0) == 1,
        'chkClientTrained':
            ((row['chk_cliente_capacitado'] as int?) ?? 0) == 1,
        'chkWorkCompleted':
            ((row['chk_trabajo_terminado'] as int?) ?? 0) == 1,
        'warrantyType': (row['garantia_tipo'] as String?)?.trim(),
        'warrantyExpiresAt': _msToIso(row['garantia_vence_en'] as int?),
        'finishedAt': _msToIso(row['finalizado_en'] as int?),
        'createdAt': _msToIso(row['creado_en'] as int?),
        'updatedAt': _msToIso(row['actualizado_en'] as int?),
      };
    }

    if (table == 'operacion_materiales') {
      String? operationServerId;
      final operacionId = row['operacion_id'] as int?;
      if (operacionId != null) {
        operationServerId = await ensureServerId(
            db: db, table: 'operaciones', localId: operacionId);
      }

      return {
        'operationId': operationServerId,
        'name': (row['nombre'] as String? ?? '').trim(),
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'operacion_evidencias') {
      String? operationServerId;
      final operacionId = row['operacion_id'] as int?;
      if (operacionId != null) {
        operationServerId = await ensureServerId(
            db: db, table: 'operaciones', localId: operacionId);
      }

      final filePath = (row['file_path'] as String? ?? '').trim();
      final fileUrl = (row['file_url'] as String? ?? '').trim();
      return {
        'operationId': operationServerId,
        'type': (row['tipo'] as String? ?? '').trim(),
        'filePath': filePath.isNotEmpty ? filePath : fileUrl,
        'fileUrl': fileUrl.isEmpty ? null : fileUrl,
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'operacion_notas') {
      String? operationServerId;
      final operacionId = row['operacion_id'] as int?;
      if (operacionId != null) {
        operationServerId = await ensureServerId(
            db: db, table: 'operaciones', localId: operacionId);
      }

      String? employeeServerId;
      final usuarioId = row['usuario_id'] as int?;
      if (usuarioId != null) {
        employeeServerId =
            await ensureServerId(db: db, table: 'usuarios', localId: usuarioId);
      }

      return {
        'operationId': operationServerId,
        'employeeId': employeeServerId,
        'note': (row['nota'] as String? ?? '').trim(),
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'operacion_estados_historial') {
      String? operationServerId;
      final operacionId = row['operacion_id'] as int?;
      if (operacionId != null) {
        operationServerId = await ensureServerId(
            db: db, table: 'operaciones', localId: operacionId);
      }

      String? employeeServerId;
      final usuarioId = row['usuario_id'] as int?;
      if (usuarioId != null) {
        employeeServerId =
            await ensureServerId(db: db, table: 'usuarios', localId: usuarioId);
      }

      return {
        'operationId': operationServerId,
        'fromStatus': (row['de_estado'] as String?)?.trim(),
        'toStatus': (row['a_estado'] as String? ?? '').trim(),
        'employeeId': employeeServerId,
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'presupuestos') {
      String? customerServerId;
      final clienteId = row['cliente_id'] as int?;
      if (clienteId != null) {
        customerServerId =
            await ensureServerId(db: db, table: 'clientes', localId: clienteId);
      }

      final itbisActivo = ((row['itbis_activo'] as int?) ?? 0) == 1;
      return {
        'customerId': customerServerId,
        'code': (row['codigo'] as String?)?.trim(),
        'total': row['total'],
        'currency': (row['moneda'] as String? ?? 'DOP').trim(),
        'status': (row['estado'] as String? ?? 'Borrador').trim(),
        'notes': (row['notas'] as String?)?.trim(),
        'itbisActive': itbisActivo,
        'itbisRate': row['itbis_tasa'],
        'discountGlobal': row['descuento_global'],
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'presupuesto_items') {
      String? quoteServerId;
      final presupuestoId = row['presupuesto_id'] as int?;
      if (presupuestoId != null) {
        quoteServerId = await ensureServerId(
            db: db, table: 'presupuestos', localId: presupuestoId);
      }

      String? productServerId;
      final productoId = row['producto_id'] as int?;
      if (productoId != null) {
        productServerId = await ensureServerId(
            db: db, table: 'productos', localId: productoId);
      }

      return {
        'quoteId': quoteServerId,
        'productId': productServerId,
        'code': (row['codigo'] as String?)?.trim(),
        'name': (row['nombre'] as String? ?? '').trim(),
        'price': row['precio'],
        'qty': row['cantidad'],
        'discount': row['descuento'],
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'nomina_ajustes') {
      String? employeeServerId;
      final usuarioId = row['usuario_id'] as int?;
      if (usuarioId != null) {
        employeeServerId =
            await ensureServerId(db: db, table: 'usuarios', localId: usuarioId);
      }

      final startIso = _msToIso(row['periodo_inicio'] as int?) ??
          DateTime.now().toUtc().toIso8601String();
      final endIso = _msToIso(row['periodo_fin'] as int?) ?? startIso;
      return {
        'employeeId': employeeServerId,
        'periodStart': startIso,
        'periodEnd': endIso,
        'type': (row['tipo'] as String? ?? '').trim(),
        'amount': row['monto'],
        'note': (row['nota'] as String?)?.trim(),
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'beneficios_pagos') {
      String? employeeServerId;
      final usuarioId = row['usuario_id'] as int?;
      if (usuarioId != null) {
        employeeServerId =
            await ensureServerId(db: db, table: 'usuarios', localId: usuarioId);
      }

      final startIso = _msToIso(row['periodo_inicio'] as int?) ??
          DateTime.now().toUtc().toIso8601String();
      final endIso = _msToIso(row['periodo_fin'] as int?) ?? startIso;
      final paidIso = _msToIso(row['pago_en'] as int?) ?? endIso;
      return {
        'employeeId': employeeServerId,
        'periodStart': startIso,
        'periodEnd': endIso,
        'paidAt': paidIso,
        'baseSalary': row['sueldo_base'],
        'commission': row['comision'],
        'adjustments': row['ajustes'],
        'net': row['neto'],
        'status': (row['estado'] as String? ?? '').trim(),
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    if (table == 'ponches') {
      String? employeeServerId;
      final usuarioId = row['usuario_id'] as int?;
      if (usuarioId != null) {
        employeeServerId =
            await ensureServerId(db: db, table: 'usuarios', localId: usuarioId);
      }

      final timeIso =
          _msToIso(row['hora'] as int?) ?? DateTime.now().toUtc().toIso8601String();
      return {
        'employeeId': employeeServerId,
        'type': (row['tipo'] as String? ?? '').trim(),
        'time': timeIso,
        'location': (row['ubicacion'] as String?)?.trim(),
        'createdAt': timeIso,
      };
    }

    if (table == 'venta_items') {
      String? saleServerId;
      final ventaId = row['venta_id'] as int?;
      if (ventaId != null) {
        saleServerId =
            await ensureServerId(db: db, table: 'ventas', localId: ventaId);
      }

      String? productServerId;
      final productoId = row['producto_id'] as int?;
      if (productoId != null) {
        productServerId = await ensureServerId(
            db: db, table: 'productos', localId: productoId);
      }

      return {
        'saleId': saleServerId,
        'productId': productServerId,
        'code': (row['codigo'] as String?)?.trim(),
        'name': (row['nombre'] as String? ?? '').trim(),
        'qty': row['cantidad'],
        'price': row['precio'],
        'cost': row['costo'],
        'createdAt': _msToIso(row['creado_en'] as int?),
      };
    }

    // ventas -> sales
    final total = row['total'];
    final note = (row['notas'] as String?)?.trim();
    final createdMs =
        (row['creado_en'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    final saleAt = DateTime.fromMillisecondsSinceEpoch(createdMs)
        .toUtc()
        .toIso8601String();

    String? customerServerId;
    final clienteId = row['cliente_id'] as int?;
    if (clienteId != null) {
      customerServerId =
          await ensureServerId(db: db, table: 'clientes', localId: clienteId);
    }

    String? employeeServerId;
    final usuarioId = row['usuario_id'] as int?;
    if (usuarioId != null) {
      employeeServerId =
          await ensureServerId(db: db, table: 'usuarios', localId: usuarioId);
    }

    return {
      'customerId': customerServerId,
      'employeeId': employeeServerId,
      'code': (row['codigo'] as String?)?.trim(),
      'total': total,
      'profit': row['ganancia'],
      'points': row['puntos'],
      'currency': (row['moneda'] as String? ?? 'DOP').trim(),
      'saleAt': saleAt,
      'note': (note == null || note.isEmpty) ? null : note,
      'createdAt': _msToIso(createdMs),
    };
  }

  static Future<List<OutboxOp>> listPending({
    required Database db,
    int limit = 100,
  }) async {
    final rows = await db.query(
      'sync_outbox',
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows.map(OutboxOp.fromRow).toList();
  }

  static Future<void> remove({required Database db, required String key}) async {
    await db.delete('sync_outbox', where: 'key = ?', whereArgs: [key]);
  }

  static Future<void> markError({
    required Database db,
    required String key,
    required String error,
  }) async {
    final currentTry = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT try_count FROM sync_outbox WHERE key = ? LIMIT 1',
            [key],
          ),
        ) ??
        0;

    await db.update(
      'sync_outbox',
      {
        'try_count': currentTry + 1,
        'last_error': error,
      },
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}

class OutboxOp {
  OutboxOp({
    required this.key,
    required this.opId,
    required this.entity,
    required this.entityServerId,
    required this.type,
    required this.payloadJson,
    required this.clientUpdatedAt,
    required this.createdAt,
    required this.tryCount,
    required this.lastError,
  });

  final String key;
  final String opId;
  final String entity;
  final String entityServerId;
  final String type;
  final String? payloadJson;
  final String clientUpdatedAt;
  final int createdAt;
  final int tryCount;
  final String? lastError;

  Map<String, dynamic>? get payload {
    final raw = (payloadJson ?? '').trim();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  static OutboxOp fromRow(Map<String, Object?> row) {
    return OutboxOp(
      key: (row['key'] as String?) ?? '',
      opId: (row['op_id'] as String?) ?? '',
      entity: (row['entity'] as String?) ?? '',
      entityServerId: (row['entity_server_id'] as String?) ?? '',
      type: (row['type'] as String?) ?? '',
      payloadJson: row['payload_json'] as String?,
      clientUpdatedAt: (row['client_updated_at'] as String?) ?? '',
      createdAt: (row['created_at'] as int?) ?? 0,
      tryCount: (row['try_count'] as int?) ?? 0,
      lastError: row['last_error'] as String?,
    );
  }
}
