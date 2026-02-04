import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../utils/cloud_friendly_error.dart';
import 'app_database.dart';
import 'cloud_api.dart';
import 'cloud_settings.dart';
import 'sync/sync_service.dart';

sealed class LoginResult {
  const LoginResult();

  const factory LoginResult.ok() = LoginOk;
  const factory LoginResult.invalid() = LoginInvalid;
  const factory LoginResult.blocked() = LoginBlocked;
  const factory LoginResult.weakPassword() = LoginWeakPassword;

  bool get isOk => this is LoginOk;
}

class LoginOk extends LoginResult {
  const LoginOk();
}

class LoginInvalid extends LoginResult {
  const LoginInvalid();
}

class LoginBlocked extends LoginResult {
  const LoginBlocked();
}

class LoginWeakPassword extends LoginResult {
  const LoginWeakPassword();
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _kUserIdKey = 'fulltech.session.userId';
  static const _kEmployeeServerIdKey = 'fulltech.session.employeeServerId';

  bool _hasSession = false;
  String? _userIdRaw;
  int? _userId;

  bool get hasSession => _hasSession;
  String? get currentUserIdRaw => _userIdRaw;
  int? get currentUserId => _userId;

  Future<void> loadSession() async {
    final settings = await CloudSettings.load();
    _hasSession = settings.hasSession;
    final prefs = await SharedPreferences.getInstance();
    final cachedId = prefs.getString(_kUserIdKey);
    if (cachedId != null && cachedId.trim().isNotEmpty) {
      _userIdRaw = cachedId.trim();
      _userId = int.tryParse(_userIdRaw!);
      return;
    }
    final serverId = prefs.getString(_kEmployeeServerIdKey);
    if (serverId != null && serverId.trim().isNotEmpty) {
      await AppDatabase.instance.init();
      final rows = await AppDatabase.instance.db.query(
        'usuarios',
        where: 'server_id = ?',
        whereArgs: [serverId.trim()],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final id = (rows.first['id'] as int?) ?? 0;
        if (id > 0) {
          _userId = id;
          _userIdRaw = id.toString();
          await prefs.setString(_kUserIdKey, _userIdRaw!);
          return;
        }
      }
    }

    _userIdRaw = null;
    _userId = null;
    if (!settings.hasSession) {
      await prefs.remove(_kUserIdKey);
      await prefs.remove(_kEmployeeServerIdKey);
    }
  }

  Future<void> logout() async {
    _hasSession = false;
    _userIdRaw = null;
    _userId = null;
    await CloudSettings.clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserIdKey);
    await prefs.remove(_kEmployeeServerIdKey);
  }

  Future<Map<String, Object?>?> currentUser() async {
    if (_userId == null) return null;
    final row = await AppDatabase.instance.findById('usuarios', _userId!);
    if (row == null) return null;
    return {
      'id': _userId,
      'email': row['email'],
      'rol': row['rol'],
      'nombre': row['nombre'],
    };
  }

  Future<LoginResult> login({
    required String usuario,
    required String password,
  }) async {
    final identity = usuario.trim();
    if (identity.isEmpty) return const LoginResult.invalid();

    final pw = password.trim();
    if (pw.isEmpty) return const LoginResult.invalid();

    final settings = await CloudSettings.load();
    final baseUrl = settings.baseUrl;
    final deviceId = settings.deviceId.isNotEmpty ? settings.deviceId : null;

    final api = CloudApi();

    try {
      if (kDebugMode) {
        debugPrint('[AuthService] login start baseUrl=$baseUrl user=$identity');
      }
      final tokens = await api.loginEmployee(
        baseUrl: baseUrl,
        username: identity,
        password: pw,
        deviceId: deviceId,
      );

      final accessToken = (tokens['accessToken'] ?? '').toString();
      final refreshToken = (tokens['refreshToken'] ?? '').toString();
      if (accessToken.isEmpty || refreshToken.isEmpty) {
        throw Exception('Respuesta invalida del servidor (tokens vacios).');
      }

      final ownerEmail = (tokens['ownerEmail'] ?? '').toString().trim();
      final employee = tokens['employee'];
      final employeeId = (tokens['employeeId'] ?? '').toString().trim();
      if (employeeId.isEmpty || employee is! Map) {
        throw Exception('Respuesta invalida del servidor (empleado).');
      }

      await CloudSettings.save(
        enabled: true,
        baseUrl: baseUrl,
        email: ownerEmail.isEmpty ? identity : ownerEmail,
      );
      await CloudSettings.saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      await CloudSettings.saveLastCloudStatus(
        ok: true,
        message: 'Conectado.',
      );

      final localId =
          await _upsertLocalEmployee(employeeId: employeeId, data: employee);
      if (localId == null) {
        throw Exception('No se pudo crear el usuario local.');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUserIdKey, localId.toString());
      await prefs.setString(_kEmployeeServerIdKey, employeeId);
      _userId = localId;
      _userIdRaw = localId.toString();
      _hasSession = true;

      // Force full pull after login to keep shared data in sync.
      await CloudSettings.saveLastServerTime('');
      try {
        await SyncService().syncNow();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AuthService] sync after login failed: $e');
        }
        await CloudSettings.saveLastCloudStatus(
          ok: false,
          message:
              'SesiÃ³n iniciada, pero no se pudo sincronizar: ${cloudFriendlyReason(e)}',
        );
      }

      await loadSession();
      return const LoginResult.ok();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthService] login failed: $e');
      }
      final reason = cloudFriendlyReason(e);
      final lowered = reason.toLowerCase();
      await CloudSettings.saveLastCloudStatus(
        ok: false,
        message: reason,
      );
      if (lowered.contains('block') || lowered.contains('bloque')) {
        return const LoginResult.blocked();
      }
      return const LoginResult.invalid();
    }
  }

  Future<int?> _upsertLocalEmployee({
    required String employeeId,
    required Map<dynamic, dynamic> data,
  }) async {
    await AppDatabase.instance.init();
    final db = AppDatabase.instance.db;
    final rows = await db.query(
      'usuarios',
      where: 'server_id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );

    String str(dynamic v) => (v ?? '').toString().trim();
    final nombre = str(data['name']);
    final usuario = str(data['username']);
    final email = str(data['email']);
    final rol = str(data['role']);
    final bloqueado = data['blocked'] == true ? 1 : 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (rows.isEmpty) {
      final id = await db.insert('usuarios', {
        'server_id': employeeId,
        'nombre': nombre.isEmpty ? 'Usuario' : nombre,
        'usuario': usuario.isEmpty ? null : usuario,
        'rol': rol.isEmpty ? 'Usuario' : rol,
        'email': email.isEmpty ? null : email,
        'bloqueado': bloqueado,
        'creado_en': now,
        'actualizado_en': now,
      });
      return id;
    }

    final existingId = (rows.first['id'] as int?) ?? 0;
    if (existingId <= 0) return null;

    await db.update(
      'usuarios',
      {
        'nombre': nombre.isEmpty ? rows.first['nombre'] : nombre,
        'usuario': usuario.isEmpty ? rows.first['usuario'] : usuario,
        'rol': rol.isEmpty ? rows.first['rol'] : rol,
        'email': email.isEmpty ? rows.first['email'] : email,
        'bloqueado': bloqueado,
        'actualizado_en': now,
        'borrado_en': null,
      },
      where: 'id = ?',
      whereArgs: [existingId],
    );
    return existingId;
  }

  // --- Legacy helpers (kept to avoid breaking old UI during migration) ---

  static bool isAdminRole(String? role) {
    final s = (role ?? '').trim().toLowerCase();
    return s == 'admin' || s == 'administrador';
  }

  static String newSalt({int length = 16}) {
    final rnd = Random.secure();
    final bytes = List<int>.generate(length, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String hashPassword({required String password, required String salt}) {
    final data = utf8.encode('$salt:$password');
    return sha256.convert(data).toString();
  }

  Future<void> updateMyEmailPassword({
    required String email,
    String? newPassword,
  }) async {
    // Cloud-only build: this app doesn't support updating credentials from
    // legacy local pages.
    throw StateError('No disponible en modo nube.');
  }
}
