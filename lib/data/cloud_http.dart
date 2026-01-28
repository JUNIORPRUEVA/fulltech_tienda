import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_api.dart';
import 'cloud_settings.dart';

class CloudHttp {
  CloudHttp({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = await _buildUri(path, query: query);
    final resp = await _sendWithRefresh((headers) {
      return _client.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    });
    return _decodeMap(resp);
  }

  Future<Map<String, dynamic>> postJson(String path, Object? body) async {
    final uri = await _buildUri(path);
    final resp = await _sendWithRefresh((headers) {
      final h = {...headers, 'Content-Type': 'application/json'};
      return _client
          .post(uri, headers: h, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    });
    return _decodeMap(resp);
  }

  Future<Map<String, dynamic>> patchJson(String path, Object? body) async {
    final uri = await _buildUri(path);
    final resp = await _sendWithRefresh((headers) {
      final h = {...headers, 'Content-Type': 'application/json'};
      return _client
          .patch(uri, headers: h, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    });
    return _decodeMap(resp);
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    final uri = await _buildUri(path);
    final resp = await _sendWithRefresh((headers) {
      return _client.delete(uri, headers: headers).timeout(const Duration(seconds: 20));
    });
    return _decodeMap(resp);
  }

  Future<Uri> _buildUri(String path, {Map<String, String>? query}) async {
    final settings = await CloudSettings.load();
    if (!settings.enabled) throw Exception('Nube desactivada.');

    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('${settings.baseUrl}$p');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Map<String, String> _headers({required CloudSettingsData settings}) {
    final h = <String, String>{
      'Authorization': 'Bearer ${settings.accessToken}',
    };

    final deviceId = settings.deviceId.trim();
    if (deviceId.isNotEmpty) {
      h['X-Device-Id'] = deviceId;
    }

    return h;
  }

  Future<http.Response> _sendWithRefresh(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var settings = await CloudSettings.load();
    if (!settings.hasSession) {
      throw Exception('No hay sesión cloud. Inicia sesión primero.');
    }

    http.Response resp = await send(_headers(settings: settings));
    if (resp.statusCode != 401) {
      _throwIfNotOk(resp);
      return resp;
    }

    // Try refresh once
    final api = CloudApi(client: _client);
    final deviceId = settings.deviceId.trim();

    final refreshed = await api.refresh(
      baseUrl: settings.baseUrl,
      refreshToken: settings.refreshToken,
      deviceId: deviceId.isEmpty ? null : deviceId,
    );

    final newAccess = (refreshed['accessToken'] ?? '').toString();
    final newRefresh = (refreshed['refreshToken'] ?? '').toString();
    if (newAccess.trim().isEmpty || newRefresh.trim().isEmpty) {
      throw Exception('Sesión expirada. Inicia sesión nuevamente.');
    }

    await CloudSettings.saveSession(accessToken: newAccess, refreshToken: newRefresh);

    settings = await CloudSettings.load();
    resp = await send(_headers(settings: settings));
    _throwIfNotOk(resp);
    return resp;
  }

  static Map<String, dynamic> _decodeMap(http.Response resp) {
    final body = resp.body.trim();
    if (body.isEmpty) return <String, dynamic>{};

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
    throw Exception('Respuesta inválida del servidor.');
  }

  static void _throwIfNotOk(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;

    try {
      final decoded = _decodeMap(resp);
      final err = decoded['error'];
      if (err is Map) {
        final msg = err['message']?.toString().trim();
        if (msg != null && msg.isNotEmpty) throw Exception(msg);
      }
    } catch (_) {
      // ignore parse errors; fall back
    }

    throw Exception('Error del servidor (${resp.statusCode}).');
  }
}
