import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cloud_settings.dart';

class CloudApi {
  CloudApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('[CloudApi] $message');
  }

  String _redactBody(String body) {
    var v = body;
    v = v.replaceAll(
      RegExp(r'"(accessToken|refreshToken)"\s*:\s*"[^"]+"'),
      r'"$1":"<redacted>"',
    );
    return v;
  }

  Future<bool> ping({required String baseUrl}) async {
    final base = _normalizeBaseUrl(baseUrl);
    final healthUrl = Uri.parse('$base/health');
    try {
      _log('GET $healthUrl');
      final resp =
          await _client.get(healthUrl).timeout(const Duration(seconds: 8));
      if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
    } catch (_) {}

    final rootUrl = Uri.parse(base);
    try {
      _log('GET $rootUrl');
      final resp =
          await _client.get(rootUrl).timeout(const Duration(seconds: 8));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> login({
    required String baseUrl,
    required String email,
    required String password,
    String? deviceId,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}/auth/login');
    final payload = <String, dynamic>{
      'email': email.trim(),
      'password': password,
    };
    final device = (deviceId ?? '').trim();
    if (device.isNotEmpty) payload['deviceId'] = device;

    _log('POST $url (email=${email.trim()})');
    final resp = await _client
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    final body = resp.body.trim();
    _log('RESP ${resp.statusCode} ${_redactBody(body)}');
    final decoded = body.isEmpty ? null : jsonDecode(body);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String? msg;
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map) {
          msg = err['message']?.toString();
        }
      }
      throw Exception(msg ?? 'Login fallo (${resp.statusCode}).');
    }

    if (decoded is! Map) throw Exception('Respuesta invalida del servidor.');
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<Map<String, dynamic>> loginEmployee({
    required String baseUrl,
    required String username,
    required String password,
    String? deviceId,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}/auth/employee/login');
    final payload = <String, dynamic>{
      'username': username.trim(),
      'password': password,
    };
    final device = (deviceId ?? '').trim();
    if (device.isNotEmpty) payload['deviceId'] = device;

    _log('POST $url (username=${username.trim()})');
    final resp = await _client
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    final body = resp.body.trim();
    _log('RESP ${resp.statusCode} ${_redactBody(body)}');
    final decoded = body.isEmpty ? null : jsonDecode(body);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String? msg;
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map) {
          msg = err['message']?.toString();
        }
      }
      throw Exception(msg ?? 'Login fallo (${resp.statusCode}).');
    }

    if (decoded is! Map) throw Exception('Respuesta invalida del servidor.');
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<void> register({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}/auth/register');
    _log('POST $url (email=${email.trim()})');
    final resp = await _client
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode >= 200 && resp.statusCode < 300) return;

    final body = resp.body.trim();
    _log('RESP ${resp.statusCode} ${_redactBody(body)}');
    final decoded = body.isEmpty ? null : jsonDecode(body);
    String? msg;
    if (decoded is Map) {
      final err = decoded['error'];
      if (err is Map) msg = err['message']?.toString();
    }
    throw Exception(msg ?? 'Registro fallo (${resp.statusCode}).');
  }

  Future<Map<String, dynamic>> refresh({
    required String baseUrl,
    required String refreshToken,
    String? deviceId,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}/auth/refresh');
    final payload = <String, dynamic>{
      'refreshToken': refreshToken.trim(),
    };
    final device = (deviceId ?? '').trim();
    if (device.isNotEmpty) payload['deviceId'] = device;

    _log('POST $url (refreshToken=<redacted>)');
    final resp = await _client
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    final body = resp.body.trim();
    _log('RESP ${resp.statusCode} ${_redactBody(body)}');
    final decoded = body.isEmpty ? null : jsonDecode(body);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String? msg;
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map) {
          msg = err['message']?.toString();
        }
      }
      throw Exception(msg ?? 'Refresh falló (${resp.statusCode}).');
    }

    if (decoded is! Map) throw Exception('Respuesta invalida del servidor.');
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }

  static String _normalizeBaseUrl(String raw) {
    var v = raw.trim();
    if (v.isNotEmpty && !v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'https://$v';
    }
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    return v;
  }
}

class CloudSession {
  CloudSession({
    required this.baseUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.deviceId,
  });

  final String baseUrl;
  final String accessToken;
  final String refreshToken;
  final String deviceId;
}

Future<CloudSession?> loadCloudSessionIfEnabled() async {
  final settings = await CloudSettings.load();
  if (!settings.enabled) return null;
  if (!settings.hasSession) return null;

  return CloudSession(
    baseUrl: settings.baseUrl,
    accessToken: settings.accessToken,
    refreshToken: settings.refreshToken,
    deviceId: settings.deviceId,
  );
}
