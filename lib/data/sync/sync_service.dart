import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../cloud_api.dart';
import '../cloud_settings.dart';
import 'sync_outbox.dart';

class SyncSummary {
  SyncSummary({
    required this.pushedOk,
    required this.pushedConflict,
    required this.pushedError,
    required this.pulledCustomers,
    required this.pulledProducts,
    required this.pulledSales,
    required this.serverTime,
  });

  final int pushedOk;
  final int pushedConflict;
  final int pushedError;

  final int pulledCustomers;
  final int pulledProducts;
  final int pulledSales;

  final String serverTime;
}

class SyncService {
  SyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _uuid = Uuid();

  static bool _inProgress = false;

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('[SyncService] $message');
  }

  Future<SyncSummary> syncNow() async {
    if (_inProgress) {
      throw Exception('Sincronización ya está en progreso.');
    }
    _inProgress = true;

    try {
      final settings = await CloudSettings.load();
      if (!settings.enabled) {
        throw Exception('Nube desactivada.');
      }
      if (!settings.hasSession) {
        throw Exception('No hay sesión cloud. Inicia sesión primero.');
      }

      var accessToken = settings.accessToken;
      var refreshToken = settings.refreshToken;

      final deviceId = await _ensureDeviceId(settings.deviceId);

      final db = AppDatabase.instance.db;

      // 1) PUSH pending ops (offline-first outbox)
      final pending = await SyncOutbox.listPending(db: db, limit: 100);

      int pushedOk = 0;
      int pushedConflict = 0;
      int pushedError = 0;

      if (pending.isNotEmpty) {
        final reqOps = pending
            .where((o) => o.opId.trim().isNotEmpty)
            .map(
              (o) => {
                'opId': o.opId,
                'entity': o.entity,
                'entityId': o.entityServerId,
                'type': o.type,
                if (o.payload != null) 'payload': o.payload,
                'clientUpdatedAt': o.clientUpdatedAt,
                'deviceId': deviceId,
              },
            )
            .toList();

        http.Response resp = await _postJsonWithRefresh(
          url: Uri.parse('${settings.baseUrl}/sync/push'),
          accessToken: accessToken,
          refreshToken: refreshToken,
          deviceId: deviceId,
          body: reqOps,
          onTokens: (tokens) async {
            accessToken = tokens.accessToken;
            refreshToken = tokens.refreshToken;
          },
        );

        final decoded = jsonDecode(resp.body);
        final results = (decoded is Map) ? decoded['results'] : null;

        if (results is List) {
          final byOpId = <String, OutboxOp>{
            for (final o in pending) o.opId: o,
          };

          for (final r in results) {
            if (r is! Map) continue;
            final opId = (r['opId'] ?? '').toString();
            final status = (r['status'] ?? '').toString();
            final message = (r['message'] ?? '').toString();
            final serverEntity = r['serverEntity'];

            final op = byOpId[opId];
            if (op == null) continue;

            if (status == 'OK') {
              pushedOk += 1;
              if (serverEntity is Map) {
                await _applyServerEntity(entity: op.entity, serverEntity: serverEntity);
              }
              await SyncOutbox.remove(db: db, key: op.key);
              continue;
            }

            if (status == 'CONFLICT') {
              pushedConflict += 1;
              if (serverEntity is Map) {
                // Server wins: overwrite local state with server entity.
                await _applyServerEntity(entity: op.entity, serverEntity: serverEntity);
              }
              await SyncOutbox.remove(db: db, key: op.key);
              continue;
            }

            pushedError += 1;
            await SyncOutbox.markError(
              db: db,
              key: op.key,
              error: message.isEmpty ? 'Server error' : message,
            );
          }
        }
      }

      // 2) PULL changes since last serverTime
      final since = (settings.lastServerTime.trim().isEmpty)
          ? '1970-01-01T00:00:00.000Z'
          : settings.lastServerTime.trim();

      final pullUrl = Uri.parse('${settings.baseUrl}/sync/pull')
          .replace(queryParameters: {'since': since});

      final pullResp = await _getWithRefresh(
        url: pullUrl,
        accessToken: accessToken,
        refreshToken: refreshToken,
        deviceId: deviceId,
        onTokens: (tokens) async {
          accessToken = tokens.accessToken;
          refreshToken = tokens.refreshToken;
        },
      );

      final pullDecoded = jsonDecode(pullResp.body);
      if (pullDecoded is! Map) {
        throw Exception('Respuesta inválida de /sync/pull');
      }

      final serverTime = (pullDecoded['serverTime'] ?? '').toString();
      final changes = pullDecoded['changes'];

      int pulledCustomers = 0;
      int pulledProducts = 0;
      int pulledSales = 0;

      if (changes is Map) {
        final customers = changes['customers'];
        final products = changes['products'];
        final sales = changes['sales'];
        final saleItems = changes['saleItems'];
        final quotes = changes['quotes'];
        final quoteItems = changes['quoteItems'];
        final employees = changes['employees'];
        final employeeLogins = changes['employeeLogins'];
        final technicians = changes['technicians'];
        final operations = changes['operations'];
        final operationMaterials = changes['operationMaterials'];
        final operationEvidences = changes['operationEvidences'];
        final operationNotes = changes['operationNotes'];
        final operationStatuses = changes['operationStatuses'];
        final payrollAdjustments = changes['payrollAdjustments'];
        final payrollPayments = changes['payrollPayments'];
        final punches = changes['punches'];

        if (customers is List) {
          for (final e in customers) {
            if (e is Map) {
              await _applyServerEntity(entity: 'customers', serverEntity: e);
              pulledCustomers += 1;
            }
          }
        }

        if (products is List) {
          for (final e in products) {
            if (e is Map) {
              await _applyServerEntity(entity: 'products', serverEntity: e);
              pulledProducts += 1;
            }
          }
        }

        if (sales is List) {
          for (final e in sales) {
            if (e is Map) {
              await _applyServerEntity(entity: 'sales', serverEntity: e);
              pulledSales += 1;
            }
          }
        }

        if (saleItems is List) {
          for (final e in saleItems) {
            if (e is Map) {
              await _applyServerEntity(entity: 'sale_items', serverEntity: e);
            }
          }
        }

        if (quotes is List) {
          for (final e in quotes) {
            if (e is Map) {
              await _applyServerEntity(entity: 'quotes', serverEntity: e);
            }
          }
        }

        if (quoteItems is List) {
          for (final e in quoteItems) {
            if (e is Map) {
              await _applyServerEntity(entity: 'quote_items', serverEntity: e);
            }
          }
        }

        if (employees is List) {
          for (final e in employees) {
            if (e is Map) {
              await _applyServerEntity(entity: 'employees', serverEntity: e);
            }
          }
        }

        if (employeeLogins is List) {
          for (final e in employeeLogins) {
            if (e is Map) {
              await _applyServerEntity(entity: 'employee_logins', serverEntity: e);
            }
          }
        }

        if (technicians is List) {
          for (final e in technicians) {
            if (e is Map) {
              await _applyServerEntity(entity: 'technicians', serverEntity: e);
            }
          }
        }

        if (operations is List) {
          for (final e in operations) {
            if (e is Map) {
              await _applyServerEntity(entity: 'operations', serverEntity: e);
            }
          }
        }

        if (operationMaterials is List) {
          for (final e in operationMaterials) {
            if (e is Map) {
              await _applyServerEntity(entity: 'operation_materials', serverEntity: e);
            }
          }
        }

        if (operationEvidences is List) {
          for (final e in operationEvidences) {
            if (e is Map) {
              await _applyServerEntity(entity: 'operation_evidences', serverEntity: e);
            }
          }
        }

        if (operationNotes is List) {
          for (final e in operationNotes) {
            if (e is Map) {
              await _applyServerEntity(entity: 'operation_notes', serverEntity: e);
            }
          }
        }

        if (operationStatuses is List) {
          for (final e in operationStatuses) {
            if (e is Map) {
              await _applyServerEntity(entity: 'operation_statuses', serverEntity: e);
            }
          }
        }

        if (payrollAdjustments is List) {
          for (final e in payrollAdjustments) {
            if (e is Map) {
              await _applyServerEntity(entity: 'payroll_adjustments', serverEntity: e);
            }
          }
        }

        if (payrollPayments is List) {
          for (final e in payrollPayments) {
            if (e is Map) {
              await _applyServerEntity(entity: 'payroll_payments', serverEntity: e);
            }
          }
        }

        if (punches is List) {
          for (final e in punches) {
            if (e is Map) {
              await _applyServerEntity(entity: 'punches', serverEntity: e);
            }
          }
        }
      }

      if (serverTime.trim().isNotEmpty) {
        await CloudSettings.saveLastServerTime(serverTime);
      }

      // 3) Upload pending product images (best-effort)
      await _uploadPendingProductImages(
        baseUrl: settings.baseUrl,
        accessToken: accessToken,
        refreshToken: refreshToken,
        deviceId: deviceId,
        onTokens: (tokens) async {
          accessToken = tokens.accessToken;
          refreshToken = tokens.refreshToken;
        },
      );

      // 4) Upload pending employee docs + operation evidences (best-effort)
      await _uploadPendingEmployeeDocs(
        baseUrl: settings.baseUrl,
        accessToken: accessToken,
        refreshToken: refreshToken,
        deviceId: deviceId,
        onTokens: (tokens) async {
          accessToken = tokens.accessToken;
          refreshToken = tokens.refreshToken;
        },
      );

      await _uploadPendingOperationEvidences(
        baseUrl: settings.baseUrl,
        accessToken: accessToken,
        refreshToken: refreshToken,
        deviceId: deviceId,
        onTokens: (tokens) async {
          accessToken = tokens.accessToken;
          refreshToken = tokens.refreshToken;
        },
      );

      AppDatabase.instance.notifyChanged();

      return SyncSummary(
        pushedOk: pushedOk,
        pushedConflict: pushedConflict,
        pushedError: pushedError,
        pulledCustomers: pulledCustomers,
        pulledProducts: pulledProducts,
        pulledSales: pulledSales,
        serverTime: serverTime,
      );
    } finally {
      _inProgress = false;
    }
  }

  Future<String> _ensureDeviceId(String current) async {
    final v = current.trim();
    if (v.isNotEmpty) return v;
    final created = _uuid.v4();
    await CloudSettings.saveDeviceId(created);
    return created;
  }

  Future<_Tokens> _refreshTokens({
    required String baseUrl,
    required String refreshToken,
    required String deviceId,
  }) async {
    final tokens = await CloudApi(client: _client).refresh(
      baseUrl: baseUrl,
      refreshToken: refreshToken,
      deviceId: deviceId,
    );

    final newAccess = (tokens['accessToken'] ?? '').toString().trim();
    final newRefresh = (tokens['refreshToken'] ?? '').toString().trim();
    if (newAccess.isEmpty || newRefresh.isEmpty) {
      throw Exception('Refresh devolvió tokens inválidos.');
    }

    await CloudSettings.saveSession(accessToken: newAccess, refreshToken: newRefresh);
    return _Tokens(accessToken: newAccess, refreshToken: newRefresh);
  }

  Future<http.Response> _postJsonWithRefresh({
    required Uri url,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    required Object body,
    required Future<void> Function(_Tokens tokens) onTokens,
  }) async {
    final sw = Stopwatch()..start();
    http.Response resp = await _client
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));

    _log('POST $url -> ${resp.statusCode} (${sw.elapsedMilliseconds}ms)');
    if (resp.statusCode != 401) {
      _throwIfBad(resp);
      return resp;
    }

    // Retry once with refreshed tokens
    final tokens = await _refreshTokens(
      baseUrl: _base(url),
      refreshToken: refreshToken,
      deviceId: deviceId,
    );
    await onTokens(tokens);

    sw
      ..reset()
      ..start();
    resp = await _client
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${tokens.accessToken}',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));

    _log('POST(retry) $url -> ${resp.statusCode} (${sw.elapsedMilliseconds}ms)');
    _throwIfBad(resp);
    return resp;
  }

  Future<http.Response> _getWithRefresh({
    required Uri url,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    required Future<void> Function(_Tokens tokens) onTokens,
  }) async {
    final sw = Stopwatch()..start();
    http.Response resp = await _client
        .get(
          url,
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(const Duration(seconds: 45));

    _log('GET $url -> ${resp.statusCode} (${sw.elapsedMilliseconds}ms)');
    if (resp.statusCode != 401) {
      _throwIfBad(resp);
      return resp;
    }

    final tokens = await _refreshTokens(
      baseUrl: _base(url),
      refreshToken: refreshToken,
      deviceId: deviceId,
    );
    await onTokens(tokens);

    sw
      ..reset()
      ..start();
    resp = await _client
        .get(
          url,
          headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
        )
        .timeout(const Duration(seconds: 45));

    _log('GET(retry) $url -> ${resp.statusCode} (${sw.elapsedMilliseconds}ms)');
    _throwIfBad(resp);
    return resp;
  }

  Future<void> _uploadPendingProductImages({
    required String baseUrl,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    required Future<void> Function(_Tokens tokens) onTokens,
  }) async {
    final db = AppDatabase.instance.db;

    final rows = await db.query(
      'productos',
      columns: const ['id', 'server_id', 'imagen_path', 'imagen_url'],
      where:
          'server_id IS NOT NULL AND TRIM(server_id) != "" AND imagen_path IS NOT NULL AND TRIM(imagen_path) != "" AND (imagen_url IS NULL OR TRIM(imagen_url) = "")',
      limit: 20,
    );

    for (final row in rows) {
      final localId = (row['id'] as int?) ?? 0;
      final serverId = (row['server_id'] as String?)?.trim() ?? '';
      final imagePath = (row['imagen_path'] as String?)?.trim() ?? '';
      if (localId <= 0 || serverId.isEmpty || imagePath.isEmpty) continue;

      final file = File(imagePath);
      if (!file.existsSync()) continue;

      try {
        final result = await _uploadProductImageWithRefresh(
          url: Uri.parse('$baseUrl/products/$serverId/image'),
          accessToken: accessToken,
          refreshToken: refreshToken,
          deviceId: deviceId,
          file: file,
          onTokens: onTokens,
        );

        final imageUrl = (result['imageUrl'] ?? '').toString().trim();
        if (imageUrl.isEmpty) continue;

        await db.update(
          'productos',
          {'imagen_url': imageUrl},
          where: 'id = ?',
          whereArgs: [localId],
        );
      } catch (_) {
        // Best-effort: ignore and retry next sync.
      }
    }
  }

  Future<void> _uploadPendingEmployeeDocs({
    required String baseUrl,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    required Future<void> Function(_Tokens tokens) onTokens,
  }) async {
    final db = AppDatabase.instance.db;

    final rows = await db.query(
      'usuarios',
      columns: const [
        'id',
        'server_id',
        'curriculum_path',
        'curriculum_url',
        'licencia_path',
        'licencia_url',
        'cedula_foto_path',
        'cedula_foto_url',
        'carta_trabajo_path',
        'carta_trabajo_url',
      ],
      where: 'server_id IS NOT NULL AND TRIM(server_id) != ""',
      limit: 50,
    );

    const docDefs = <Map<String, String>>[
      {'kind': 'curriculum', 'path': 'curriculum_path', 'url': 'curriculum_url'},
      {'kind': 'license', 'path': 'licencia_path', 'url': 'licencia_url'},
      {'kind': 'id-card', 'path': 'cedula_foto_path', 'url': 'cedula_foto_url'},
      {'kind': 'last-job', 'path': 'carta_trabajo_path', 'url': 'carta_trabajo_url'},
    ];

    for (final row in rows) {
      final localId = (row['id'] as int?) ?? 0;
      final serverId = (row['server_id'] as String?)?.trim() ?? '';
      if (localId <= 0 || serverId.isEmpty) continue;

      for (final def in docDefs) {
        final kind = def['kind']!;
        final pathKey = def['path']!;
        final urlKey = def['url']!;
        final path = (row[pathKey] as String?)?.trim() ?? '';
        final url = (row[urlKey] as String?)?.trim() ?? '';
        if (path.isEmpty || url.isNotEmpty) continue;
        if (path.startsWith('http://') || path.startsWith('https://')) continue;

        final file = File(path);
        if (!file.existsSync()) continue;

        try {
          final result = await _uploadFileWithRefresh(
            url: Uri.parse('$baseUrl/files/employees/$serverId/$kind'),
            accessToken: accessToken,
            refreshToken: refreshToken,
            deviceId: deviceId,
            file: file,
            fieldName: 'file',
            onTokens: onTokens,
          );

          final fileUrl = (result['url'] ?? '').toString().trim();
          if (fileUrl.isEmpty) continue;

          await db.update(
            'usuarios',
            {urlKey: fileUrl},
            where: 'id = ?',
            whereArgs: [localId],
          );
        } catch (_) {
          // Best-effort: ignore and retry next sync.
        }
      }
    }
  }

  Future<void> _uploadPendingOperationEvidences({
    required String baseUrl,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    required Future<void> Function(_Tokens tokens) onTokens,
  }) async {
    final db = AppDatabase.instance.db;

    final rows = await db.query(
      'operacion_evidencias',
      columns: const ['id', 'server_id', 'file_path', 'file_url'],
      where:
          'server_id IS NOT NULL AND TRIM(server_id) != "" AND file_path IS NOT NULL AND TRIM(file_path) != "" AND (file_url IS NULL OR TRIM(file_url) = "")',
      limit: 40,
    );

    for (final row in rows) {
      final localId = (row['id'] as int?) ?? 0;
      final serverId = (row['server_id'] as String?)?.trim() ?? '';
      final filePath = (row['file_path'] as String?)?.trim() ?? '';
      if (localId <= 0 || serverId.isEmpty || filePath.isEmpty) continue;
      if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
        continue;
      }

      final file = File(filePath);
      if (!file.existsSync()) continue;

      try {
        final result = await _uploadFileWithRefresh(
          url: Uri.parse('$baseUrl/files/operation-evidences/$serverId'),
          accessToken: accessToken,
          refreshToken: refreshToken,
          deviceId: deviceId,
          file: file,
          fieldName: 'file',
          onTokens: onTokens,
        );

        final fileUrl = (result['url'] ?? '').toString().trim();
        if (fileUrl.isEmpty) continue;

        await db.update(
          'operacion_evidencias',
          {'file_url': fileUrl},
          where: 'id = ?',
          whereArgs: [localId],
        );
      } catch (_) {
        // Best-effort: ignore and retry next sync.
      }
    }
  }

  Future<Map<String, dynamic>> _uploadFileWithRefresh({
    required Uri url,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    required File file,
    required String fieldName,
    required Future<void> Function(_Tokens tokens) onTokens,
  }) async {
    http.StreamedResponse resp = await _sendMultipart(
      url: url,
      accessToken: accessToken,
      deviceId: deviceId,
      file: file,
      fieldName: fieldName,
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 401) {
      final body = await resp.stream.bytesToString();
      return _decodeUploadData(body, resp.statusCode);
    }

    final tokens = await _refreshTokens(
      baseUrl: _base(url),
      refreshToken: refreshToken,
      deviceId: deviceId,
    );
    await onTokens(tokens);

    resp = await _sendMultipart(
      url: url,
      accessToken: tokens.accessToken,
      deviceId: deviceId,
      file: file,
      fieldName: fieldName,
    ).timeout(const Duration(seconds: 30));

    final body = await resp.stream.bytesToString();
    return _decodeUploadData(body, resp.statusCode);
  }

  Map<String, dynamic> _decodeUploadData(String body, int statusCode) {
    final decoded = body.trim().isEmpty ? null : jsonDecode(body);
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception('HTTP $statusCode');
    }
    if (decoded is! Map) throw Exception('Respuesta invÃ¡lida de upload');
    final data = decoded['data'];
    if (data is! Map) throw Exception('Respuesta invÃ¡lida de upload');
    return data.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<Map<String, dynamic>> _uploadProductImageWithRefresh({
    required Uri url,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    required File file,
    required Future<void> Function(_Tokens tokens) onTokens,
  }) async {
    http.StreamedResponse resp = await _sendMultipart(
      url: url,
      accessToken: accessToken,
      deviceId: deviceId,
      file: file,
      fieldName: 'image',
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 401) {
      final body = await resp.stream.bytesToString();
      final decoded = body.trim().isEmpty ? null : jsonDecode(body);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      if (decoded is! Map) throw Exception('Respuesta inválida de upload');
      final data = decoded['data'];
      if (data is! Map) throw Exception('Respuesta inválida de upload');
      return data.map((k, v) => MapEntry(k.toString(), v));
    }

    // Refresh once and retry
    final tokens = await _refreshTokens(
      baseUrl: _base(url),
      refreshToken: refreshToken,
      deviceId: deviceId,
    );
    await onTokens(tokens);

    resp = await _sendMultipart(
      url: url,
      accessToken: tokens.accessToken,
      deviceId: deviceId,
      file: file,
      fieldName: 'image',
    ).timeout(const Duration(seconds: 30));

    final body = await resp.stream.bytesToString();
    final decoded = body.trim().isEmpty ? null : jsonDecode(body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    if (decoded is! Map) throw Exception('Respuesta inválida de upload');
    final data = decoded['data'];
    if (data is! Map) throw Exception('Respuesta inválida de upload');
    return data.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<http.StreamedResponse> _sendMultipart({
    required Uri url,
    required String accessToken,
    required String deviceId,
    required File file,
    required String fieldName,
  }) async {
    final req = http.MultipartRequest('POST', url);
    req.headers['Authorization'] = 'Bearer $accessToken';
    req.headers['x-device-id'] = deviceId;
    req.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
    return _client.send(req);
  }

  String _base(Uri url) {
    // Converts https://host/path to https://host
    return '${url.scheme}://${url.authority}';
  }

  void _throwIfBad(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;

    final body = resp.body.trim();
    String? msg;
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final err = decoded['error'];
          if (err is Map) msg = err['message']?.toString();
        }
      } catch (_) {}
    }

    throw Exception(msg ?? 'HTTP ${resp.statusCode}');
  }

  Future<void> _applyServerEntity({
    required String entity,
    required Map serverEntity,
  }) async {
    final db = AppDatabase.instance.db;

    if (entity == 'customers') {
      await _applyCustomer(db, serverEntity);
      return;
    }

    if (entity == 'products') {
      await _applyProduct(db, serverEntity);
      return;
    }

    if (entity == 'sales') {
      await _applySale(db, serverEntity);
      return;
    }

    if (entity == 'sale_items') {
      await _applySaleItem(db, serverEntity);
      return;
    }

    if (entity == 'quotes') {
      await _applyQuote(db, serverEntity);
      return;
    }

    if (entity == 'quote_items') {
      await _applyQuoteItem(db, serverEntity);
      return;
    }

    if (entity == 'employees') {
      await _applyEmployee(db, serverEntity);
      return;
    }

    if (entity == 'employee_logins') {
      await _applyEmployeeLogin(db, serverEntity);
      return;
    }

    if (entity == 'technicians') {
      await _applyTechnician(db, serverEntity);
      return;
    }

    if (entity == 'operations') {
      await _applyOperation(db, serverEntity);
      return;
    }

    if (entity == 'operation_materials') {
      await _applyOperationMaterial(db, serverEntity);
      return;
    }

    if (entity == 'operation_evidences') {
      await _applyOperationEvidence(db, serverEntity);
      return;
    }

    if (entity == 'operation_notes') {
      await _applyOperationNote(db, serverEntity);
      return;
    }

    if (entity == 'operation_statuses') {
      await _applyOperationStatus(db, serverEntity);
      return;
    }

    if (entity == 'payroll_adjustments') {
      await _applyPayrollAdjustment(db, serverEntity);
      return;
    }

    if (entity == 'payroll_payments') {
      await _applyPayrollPayment(db, serverEntity);
      return;
    }

    if (entity == 'punches') {
      await _applyPunch(db, serverEntity);
      return;
    }
  }

  int? _parseMs(dynamic iso) {
    if (iso == null) return null;
    final s = iso.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal().millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }


  double _parseDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    return parsed ?? fallback;
  }

  Future<int?> _localIdByServerId(
    DatabaseExecutor db,
    String table,
    String? serverId,
  ) async {
    if (serverId == null || serverId.trim().isEmpty) return null;
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  Future<void> _applyCustomer(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'clientes',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        // Remove local references then delete.
        if (existing.isNotEmpty) {
          final localId = (existing.first['id'] as int?) ?? 0;
          if (localId > 0) {
            await txn.update('ventas', {'cliente_id': null},
                where: 'cliente_id = ?', whereArgs: [localId]);
          }
        }
        await txn.delete('clientes', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final name = (e['name'] ?? '').toString();
      final email = e['email']?.toString();
      final phone = e['phone']?.toString();
      final address = e['address']?.toString();

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

        final values = <String, Object?>{
          'server_id': serverId,
          'sync_version': version <= 0 ? null : version,
        'nombre': name.trim().isEmpty ? '—' : name.trim(),
        'telefono': (phone ?? '').trim().isEmpty ? null : phone?.trim(),
        'email': (email ?? '').trim().isEmpty ? null : email?.trim(),
        'direccion': (address ?? '').trim().isEmpty ? null : address?.trim(),
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('clientes', values);
      } else {
        await txn.update(
          'clientes',
          values,
          where: 'server_id = ?',
          whereArgs: [serverId],
        );
      }
    });
  }

  Future<void> _applyProduct(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'productos',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        if (existing.isNotEmpty) {
          final localId = (existing.first['id'] as int?) ?? 0;
          if (localId > 0) {
            await txn.update('venta_items', {'producto_id': null},
                where: 'producto_id = ?', whereArgs: [localId]);
          }
        }
        await txn.delete('productos', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final name = (e['name'] ?? '').toString();
      final sku = e['sku']?.toString();
      final imageUrl = e['imageUrl']?.toString();
      final normalizedImageUrl = (imageUrl ?? '').trim();

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']) ?? createdAtMs;
      final version = (e['version'] as int?) ?? 0;

      double? price;
      final priceRaw = e['price'];
      if (priceRaw is num) {
        price = priceRaw.toDouble();
      } else {
        price = double.tryParse(priceRaw?.toString() ?? '');
      }
      price ??= 0.0;

      String? existingLocalPath;
      if (existing.isNotEmpty) {
        existingLocalPath = existing.first['imagen_path'] as String?;
      }

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'categoria_id': null,
        'codigo': (sku ?? '').trim().isEmpty ? serverId.substring(0, 8) : sku?.trim(),
        'nombre': name.trim().isEmpty ? 'Producto' : name.trim(),
        'precio': price,
        'costo': 0.0,
        'imagen_path': existingLocalPath,
        'imagen_url': normalizedImageUrl.isEmpty ? null : normalizedImageUrl,
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('productos', values);
      } else {
        await txn.update(
          'productos',
          values,
          where: 'server_id = ?',
          whereArgs: [serverId],
        );
      }
    });
  }

  Future<void> _applySale(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'ventas',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        if (existing.isNotEmpty) {
          final localVentaId = (existing.first['id'] as int?) ?? 0;
          if (localVentaId > 0) {
            await txn.delete('venta_items', where: 'venta_id = ?', whereArgs: [localVentaId]);
          }
        }
        await txn.delete('ventas', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final customerId = e['customerId']?.toString();
      final employeeId = e['employeeId']?.toString();

      final localClienteId = await _localIdByServerId(txn, 'clientes', customerId);
      final localEmployeeId = await _localIdByServerId(txn, 'usuarios', employeeId);

      final total = _parseDouble(e['total']);
      final profit = _parseDouble(e['profit']);
      final points = _parseDouble(e['points']);
      final currency = (e['currency'] ?? 'DOP').toString();
      final code = (e['code'] ?? '').toString().trim();
      final note = e['note']?.toString();

      final createdAtMs = _parseMs(e['saleAt']) ?? _parseMs(e['createdAt']) ??
          DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'usuario_id': localEmployeeId,
        'cliente_id': localClienteId,
        'codigo': code.isEmpty ? null : code,
        'total': total,
        'ganancia': profit,
        'puntos': points,
        'moneda': currency.trim().isEmpty ? 'DOP' : currency.trim(),
        'notas': (note ?? '').trim().isNotEmpty ? note?.trim() : null,
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('ventas', values);
      } else {
        await txn.update(
          'ventas',
          values,
          where: 'server_id = ?',
          whereArgs: [serverId],
        );
      }
    });
  }

  Future<void> _applySaleItem(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'venta_items',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('venta_items', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final saleId = e['saleId']?.toString();
      final productId = e['productId']?.toString();

      final localVentaId = await _localIdByServerId(txn, 'ventas', saleId);
      if (localVentaId == null) return;

      final localProductoId = await _localIdByServerId(txn, 'productos', productId);

      final qty = _parseDouble(e['qty']);
      final price = _parseDouble(e['price']);
      final cost = _parseDouble(e['cost']);

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'venta_id': localVentaId,
        'producto_id': localProductoId,
        'codigo': (e['code'] ?? '').toString().trim().isEmpty
            ? null
            : (e['code'] ?? '').toString().trim(),
        'nombre': (e['name'] ?? '').toString().trim(),
        'cantidad': qty,
        'precio': price,
        'costo': cost,
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('venta_items', values);
      } else {
        await txn.update('venta_items', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyQuote(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'presupuestos',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        if (existing.isNotEmpty) {
          final localId = (existing.first['id'] as int?) ?? 0;
          if (localId > 0) {
            await txn.delete('presupuesto_items',
                where: 'presupuesto_id = ?', whereArgs: [localId]);
          }
        }
        await txn.delete('presupuestos', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final customerId = e['customerId']?.toString();
      final localClienteId = await _localIdByServerId(txn, 'clientes', customerId);

      final total = _parseDouble(e['total']);
      final itbisRate = _parseDouble(e['itbisRate'], fallback: 0.18);
      final discount = _parseDouble(e['discountGlobal']);
      final itbisActive = (e['itbisActive'] == true) ? 1 : 0;

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'cliente_id': localClienteId,
        'codigo': (e['code'] ?? '').toString().trim().isEmpty
            ? null
            : (e['code'] ?? '').toString().trim(),
        'total': total,
        'moneda': (e['currency'] ?? 'DOP').toString(),
        'estado': (e['status'] ?? 'Borrador').toString(),
        'notas': (e['notes'] ?? '').toString().trim().isEmpty
            ? null
            : (e['notes'] ?? '').toString().trim(),
        'itbis_activo': itbisActive,
        'itbis_tasa': itbisRate,
        'descuento_global': discount,
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('presupuestos', values);
      } else {
        await txn.update('presupuestos', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyQuoteItem(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'presupuesto_items',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('presupuesto_items', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final quoteId = e['quoteId']?.toString();
      final localQuoteId = await _localIdByServerId(txn, 'presupuestos', quoteId);
      if (localQuoteId == null) return;

      final productId = e['productId']?.toString();
      final localProductoId = await _localIdByServerId(txn, 'productos', productId);

      final price = _parseDouble(e['price']);
      final qty = _parseDouble(e['qty']);
      final discount = _parseDouble(e['discount']);

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'presupuesto_id': localQuoteId,
        'producto_id': localProductoId,
        'codigo': (e['code'] ?? '').toString().trim().isEmpty
            ? null
            : (e['code'] ?? '').toString().trim(),
        'nombre': (e['name'] ?? '').toString().trim(),
        'precio': price,
        'cantidad': qty,
        'descuento': discount,
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('presupuesto_items', values);
      } else {
        await txn.update('presupuesto_items', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyEmployee(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'usuarios',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        if (existing.isNotEmpty) {
          final localId = (existing.first['id'] as int?) ?? 0;
          if (localId > 0) {
            await txn.delete('usuarios_logins', where: 'usuario_id = ?', whereArgs: [localId]);
            await txn.delete('ponches', where: 'usuario_id = ?', whereArgs: [localId]);
            await txn.delete('nomina_ajustes', where: 'usuario_id = ?', whereArgs: [localId]);
            await txn.delete('beneficios_pagos', where: 'usuario_id = ?', whereArgs: [localId]);
            await txn.update('ventas', {'usuario_id': null},
                where: 'usuario_id = ?', whereArgs: [localId]);
            await txn.update('operaciones', {'tecnico_usuario_id': null},
                where: 'tecnico_usuario_id = ?', whereArgs: [localId]);
            await txn.update('operacion_notas', {'usuario_id': null},
                where: 'usuario_id = ?', whereArgs: [localId]);
            await txn.update('operacion_estados_historial', {'usuario_id': null},
                where: 'usuario_id = ?', whereArgs: [localId]);
          }
        }
        await txn.delete('usuarios', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'nombre': (e['name'] ?? '').toString().trim().isEmpty
            ? 'Usuario'
            : (e['name'] ?? '').toString().trim(),
        'usuario': (e['username'] ?? '').toString().trim(),
        'rol': (e['role'] ?? 'Usuario').toString().trim(),
        'email': (e['email'] ?? '').toString().trim().isEmpty
            ? null
            : (e['email'] ?? '').toString().trim(),
        'password': (e['passwordLegacy'] ?? '').toString().trim().isEmpty
            ? null
            : (e['passwordLegacy'] ?? '').toString().trim(),
        'password_hash': (e['passwordHash'] ?? '').toString().trim().isEmpty
            ? null
            : (e['passwordHash'] ?? '').toString().trim(),
        'password_salt': (e['passwordSalt'] ?? '').toString().trim().isEmpty
            ? null
            : (e['passwordSalt'] ?? '').toString().trim(),
        'cedula': (e['cedula'] ?? '').toString().trim().isEmpty
            ? null
            : (e['cedula'] ?? '').toString().trim(),
        'direccion': (e['address'] ?? '').toString().trim().isEmpty
            ? null
            : (e['address'] ?? '').toString().trim(),
        'sueldo_quincenal': _parseDouble(e['salaryBiweekly']),
        'meta_quincenal': _parseDouble(e['goalBiweekly']),
        'empleado_mes': (e['employeeOfMonth'] == true) ? 1 : 0,
        'fecha_ingreso': _parseMs(e['hireDate']),
          'curriculum_path': (e['curriculumPath'] ?? '').toString().trim().isEmpty
              ? null
              : (e['curriculumPath'] ?? '').toString().trim(),
          'curriculum_url': (e['curriculumUrl'] ?? '').toString().trim().isEmpty
              ? null
              : (e['curriculumUrl'] ?? '').toString().trim(),
          'licencia_path': (e['licensePath'] ?? '').toString().trim().isEmpty
              ? null
              : (e['licensePath'] ?? '').toString().trim(),
          'licencia_url': (e['licenseUrl'] ?? '').toString().trim().isEmpty
              ? null
              : (e['licenseUrl'] ?? '').toString().trim(),
          'cedula_foto_path': (e['idCardPhotoPath'] ?? '').toString().trim().isEmpty
              ? null
              : (e['idCardPhotoPath'] ?? '').toString().trim(),
          'cedula_foto_url': (e['idCardPhotoUrl'] ?? '').toString().trim().isEmpty
              ? null
              : (e['idCardPhotoUrl'] ?? '').toString().trim(),
          'carta_trabajo_path': (e['lastJobPath'] ?? '').toString().trim().isEmpty
              ? null
              : (e['lastJobPath'] ?? '').toString().trim(),
          'carta_trabajo_url': (e['lastJobUrl'] ?? '').toString().trim().isEmpty
              ? null
              : (e['lastJobUrl'] ?? '').toString().trim(),
          'bloqueado': (e['blocked'] == true) ? 1 : 0,
          'ultimo_login': _parseMs(e['lastLoginAt']),
          'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('usuarios', values);
      } else {
        await txn.update('usuarios', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyEmployeeLogin(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'usuarios_logins',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('usuarios_logins', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final employeeId = e['employeeId']?.toString();
      final localEmployeeId = await _localIdByServerId(txn, 'usuarios', employeeId);
      if (localEmployeeId == null) return;

      final timeMs = _parseMs(e['time']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'usuario_id': localEmployeeId,
        'hora': timeMs,
        'exitoso': (e['success'] == true) ? 1 : 0,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('usuarios_logins', values);
      } else {
        await txn.update('usuarios_logins', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyTechnician(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'tecnicos',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('tecnicos', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'nombre': (e['name'] ?? '').toString().trim(),
        'telefono': (e['phone'] ?? '').toString().trim().isEmpty
            ? null
            : (e['phone'] ?? '').toString().trim(),
        'especialidad': (e['specialty'] ?? '').toString().trim(),
        'estado': (e['status'] ?? '').toString().trim(),
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('tecnicos', values);
      } else {
        await txn.update('tecnicos', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyOperation(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'operaciones',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        if (existing.isNotEmpty) {
          final localId = (existing.first['id'] as int?) ?? 0;
          if (localId > 0) {
            await txn.delete('operacion_materiales',
                where: 'operacion_id = ?', whereArgs: [localId]);
            await txn.delete('operacion_evidencias',
                where: 'operacion_id = ?', whereArgs: [localId]);
            await txn.delete('operacion_notas',
                where: 'operacion_id = ?', whereArgs: [localId]);
            await txn.delete('operacion_estados_historial',
                where: 'operacion_id = ?', whereArgs: [localId]);
          }
        }
        await txn.delete('operaciones', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final customerId = e['customerId']?.toString();
      final technicianId = e['technicianId']?.toString();
      final technicianEmployeeId = e['technicianEmployeeId']?.toString();

      final localClienteId = await _localIdByServerId(txn, 'clientes', customerId);
      final localTecnicoId = await _localIdByServerId(txn, 'tecnicos', technicianId);
      final localTecnicoUsuarioId =
          await _localIdByServerId(txn, 'usuarios', technicianEmployeeId);

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']) ?? createdAtMs;
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'cliente_id': localClienteId,
        'codigo': (e['code'] ?? '').toString().trim().isEmpty
            ? serverId.substring(0, 8)
            : (e['code'] ?? '').toString().trim(),
        'titulo': (e['title'] ?? '').toString().trim().isEmpty
            ? null
            : (e['title'] ?? '').toString().trim(),
        'tipo_servicio': (e['serviceType'] ?? '').toString().trim(),
        'prioridad': (e['priority'] ?? '').toString().trim(),
        'estado': (e['status'] ?? '').toString().trim(),
        'tecnico_id': localTecnicoId,
        'tecnico_usuario_id': localTecnicoUsuarioId,
        'programado_en': _parseMs(e['scheduledAt']),
        'hora_estimada': (e['estimatedTime'] ?? '').toString().trim().isEmpty
            ? null
            : (e['estimatedTime'] ?? '').toString().trim(),
        'direccion_servicio': (e['serviceAddress'] ?? '').toString().trim().isEmpty
            ? null
            : (e['serviceAddress'] ?? '').toString().trim(),
        'referencia_lugar': (e['locationRef'] ?? '').toString().trim().isEmpty
            ? null
            : (e['locationRef'] ?? '').toString().trim(),
        'descripcion': (e['description'] ?? '').toString().trim().isEmpty
            ? null
            : (e['description'] ?? '').toString().trim(),
        'observaciones_iniciales': (e['initialObservations'] ?? '').toString().trim().isEmpty
            ? null
            : (e['initialObservations'] ?? '').toString().trim(),
        'observaciones_finales': (e['finalObservations'] ?? '').toString().trim().isEmpty
            ? null
            : (e['finalObservations'] ?? '').toString().trim(),
        'monto': _parseDouble(e['amount']),
        'forma_pago': (e['paymentMethod'] ?? '').toString().trim().isEmpty
            ? null
            : (e['paymentMethod'] ?? '').toString().trim(),
        'pago_estado': (e['paymentStatus'] ?? '').toString().trim().isEmpty
            ? null
            : (e['paymentStatus'] ?? '').toString().trim(),
        'pago_abono': _parseDouble(e['paymentPaidAmount']),
        'chk_llego': (e['chkArrived'] == true) ? 1 : 0,
        'chk_material_instalado': (e['chkMaterialInstalled'] == true) ? 1 : 0,
        'chk_sistema_probado': (e['chkSystemTested'] == true) ? 1 : 0,
        'chk_cliente_capacitado': (e['chkClientTrained'] == true) ? 1 : 0,
        'chk_trabajo_terminado': (e['chkWorkCompleted'] == true) ? 1 : 0,
        'garantia_tipo': (e['warrantyType'] ?? '').toString().trim().isEmpty
            ? null
            : (e['warrantyType'] ?? '').toString().trim(),
        'garantia_vence_en': _parseMs(e['warrantyExpiresAt']),
        'actualizado_en': updatedAtMs,
        'finalizado_en': _parseMs(e['finishedAt']),
        'creado_en': createdAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('operaciones', values);
      } else {
        await txn.update('operaciones', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyOperationMaterial(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'operacion_materiales',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('operacion_materiales', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final operationId = e['operationId']?.toString();
      final localOperacionId = await _localIdByServerId(txn, 'operaciones', operationId);
      if (localOperacionId == null) return;

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'operacion_id': localOperacionId,
        'nombre': (e['name'] ?? '').toString().trim(),
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('operacion_materiales', values);
      } else {
        await txn.update('operacion_materiales', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyOperationEvidence(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'operacion_evidencias',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('operacion_evidencias', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final operationId = e['operationId']?.toString();
      final localOperacionId = await _localIdByServerId(txn, 'operaciones', operationId);
      if (localOperacionId == null) return;

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

        final values = <String, Object?>{
          'server_id': serverId,
          'sync_version': version <= 0 ? null : version,
          'operacion_id': localOperacionId,
          'tipo': (e['type'] ?? '').toString().trim(),
          'file_path': (() {
            final filePath = (e['filePath'] ?? '').toString().trim();
            final fileUrl = (e['fileUrl'] ?? '').toString().trim();
            if (filePath.isNotEmpty) return filePath;
            if (fileUrl.isNotEmpty) return fileUrl;
            return '';
          })(),
          'file_url': (e['fileUrl'] ?? '').toString().trim().isEmpty
              ? null
              : (e['fileUrl'] ?? '').toString().trim(),
          'creado_en': createdAtMs,
          'actualizado_en': updatedAtMs,
          'borrado_en': null,
        };

      if (existing.isEmpty) {
        await txn.insert('operacion_evidencias', values);
      } else {
        await txn.update('operacion_evidencias', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyOperationNote(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'operacion_notas',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('operacion_notas', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final operationId = e['operationId']?.toString();
      final localOperacionId = await _localIdByServerId(txn, 'operaciones', operationId);
      if (localOperacionId == null) return;

      final employeeId = e['employeeId']?.toString();
      final localEmployeeId = await _localIdByServerId(txn, 'usuarios', employeeId);

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'operacion_id': localOperacionId,
        'usuario_id': localEmployeeId,
        'nota': (e['note'] ?? '').toString().trim(),
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('operacion_notas', values);
      } else {
        await txn.update('operacion_notas', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyOperationStatus(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'operacion_estados_historial',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('operacion_estados_historial',
            where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final operationId = e['operationId']?.toString();
      final localOperacionId = await _localIdByServerId(txn, 'operaciones', operationId);
      if (localOperacionId == null) return;

      final employeeId = e['employeeId']?.toString();
      final localEmployeeId = await _localIdByServerId(txn, 'usuarios', employeeId);

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'operacion_id': localOperacionId,
        'de_estado': (e['fromStatus'] ?? '').toString().trim().isEmpty
            ? null
            : (e['fromStatus'] ?? '').toString().trim(),
        'a_estado': (e['toStatus'] ?? '').toString().trim(),
        'usuario_id': localEmployeeId,
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('operacion_estados_historial', values);
      } else {
        await txn.update('operacion_estados_historial', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyPayrollAdjustment(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'nomina_ajustes',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('nomina_ajustes', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final employeeId = e['employeeId']?.toString();
      final localEmployeeId = await _localIdByServerId(txn, 'usuarios', employeeId);
      if (localEmployeeId == null) return;

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'usuario_id': localEmployeeId,
        'periodo_inicio': _parseMs(e['periodStart']) ?? createdAtMs,
        'periodo_fin': _parseMs(e['periodEnd']) ?? createdAtMs,
        'tipo': (e['type'] ?? '').toString().trim(),
        'monto': _parseDouble(e['amount']),
        'nota': (e['note'] ?? '').toString().trim().isEmpty
            ? null
            : (e['note'] ?? '').toString().trim(),
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('nomina_ajustes', values);
      } else {
        await txn.update('nomina_ajustes', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyPayrollPayment(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'beneficios_pagos',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('beneficios_pagos', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final employeeId = e['employeeId']?.toString();
      final localEmployeeId = await _localIdByServerId(txn, 'usuarios', employeeId);
      if (localEmployeeId == null) return;

      final createdAtMs = _parseMs(e['createdAt']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'usuario_id': localEmployeeId,
        'periodo_inicio': _parseMs(e['periodStart']) ?? createdAtMs,
        'periodo_fin': _parseMs(e['periodEnd']) ?? createdAtMs,
        'pago_en': _parseMs(e['paidAt']) ?? createdAtMs,
        'sueldo_base': _parseDouble(e['baseSalary']),
        'comision': _parseDouble(e['commission']),
        'ajustes': _parseDouble(e['adjustments']),
        'neto': _parseDouble(e['net']),
        'estado': (e['status'] ?? '').toString().trim(),
        'creado_en': createdAtMs,
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('beneficios_pagos', values);
      } else {
        await txn.update('beneficios_pagos', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }

  Future<void> _applyPunch(Database db, Map e) async {
    final serverId = (e['id'] ?? '').toString().trim();
    if (serverId.isEmpty) return;

    final deletedAtMs = _parseMs(e['deletedAt']);

    await db.transaction((txn) async {
      final existing = await txn.query(
        'ponches',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );

      if (deletedAtMs != null) {
        await txn.delete('ponches', where: 'server_id = ?', whereArgs: [serverId]);
        return;
      }

      final employeeId = e['employeeId']?.toString();
      final localEmployeeId = await _localIdByServerId(txn, 'usuarios', employeeId);

      final timeMs = _parseMs(e['time']) ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAtMs = _parseMs(e['updatedAt']);
      final version = (e['version'] as int?) ?? 0;

      final values = <String, Object?>{
        'server_id': serverId,
        'sync_version': version <= 0 ? null : version,
        'usuario_id': localEmployeeId,
        'tipo': (e['type'] ?? '').toString().trim(),
        'hora': timeMs,
        'ubicacion': (e['location'] ?? '').toString().trim().isEmpty
            ? null
            : (e['location'] ?? '').toString().trim(),
        'actualizado_en': updatedAtMs,
        'borrado_en': null,
      };

      if (existing.isEmpty) {
        await txn.insert('ponches', values);
      } else {
        await txn.update('ponches', values,
            where: 'server_id = ?', whereArgs: [serverId]);
      }
    });
  }
}

class _Tokens {
  _Tokens({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;
}
