import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CloudSettingsData {
  CloudSettingsData({
    required this.enabled,
    required this.baseUrl,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.deviceId,
    required this.lastServerTime,
  });

  final bool enabled;
  final String baseUrl;
  final String email;
  final String accessToken;
  final String refreshToken;
  final String deviceId;

  /// ISO-8601 con zona horaria (lo devuelve el backend como `serverTime`).
  /// Se usa como `since` en `/sync/pull`.
  final String lastServerTime;

  bool get hasSession => accessToken.trim().isNotEmpty && refreshToken.trim().isNotEmpty;
}

class CloudSettings {
  static const _prefsEnabled = 'cloud_enabled';
  static const _prefsBaseUrl = 'cloud_base_url';
  static const _prefsEmail = 'cloud_email';
  static const _prefsAccess = 'cloud_access_token';
  static const _prefsRefresh = 'cloud_refresh_token';
  static const _prefsDeviceId = 'cloud_device_id';
  static const _prefsLastServerTime = 'cloud_last_server_time';

  static const _prefsLastCloudOk = 'cloud_last_ok';
  static const _prefsLastCloudMessage = 'cloud_last_message';
  static const _prefsLastCloudAtMs = 'cloud_last_at_ms';

  // Puedes sobreescribir en build/run:
  // flutter run --dart-define=CLOUD_BASE_URL=https://.../
  static const String _envBaseUrl = String.fromEnvironment(
    'CLOUD_BASE_URL',
    defaultValue: '',
  );

  static String _defaultBaseUrl() {
    // Android emulator: host machine loopback.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    // Desktop, iOS simulator, web dev server, etc.
    return 'http://localhost:3000';
  }

  // Cuenta cloud fija (para compartir catálogo/clientes en toda la empresa).
  static const String _envFixedEmail = String.fromEnvironment(
    'CLOUD_FIXED_EMAIL',
    defaultValue: '',
  );
  static const String _envFixedPassword = String.fromEnvironment(
    'CLOUD_FIXED_PASSWORD',
    defaultValue: '',
  );

  static String get envBaseUrl =>
      _normalizeBaseUrl(_envBaseUrl.trim().isEmpty ? _defaultBaseUrl() : _envBaseUrl);
  static String get fixedCloudEmail => _envFixedEmail.trim();
  static String get fixedCloudPassword => _envFixedPassword.trim();

  static String _normalizeBaseUrl(String raw) {
    var v = raw.trim();
    if (v.isNotEmpty && !v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'https://$v';
    }
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    return v;
  }

  static Future<CloudSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Cloud is always enabled (no UI toggle).
    const enabled = true;
    if (prefs.getBool(_prefsEnabled) != true) {
      await prefs.setBool(_prefsEnabled, true);
    }
    // Base URL is not user-configurable; always use the build-time configured value.
    final baseUrl = envBaseUrl;
    final storedBaseUrl = _normalizeBaseUrl(prefs.getString(_prefsBaseUrl) ?? envBaseUrl);
    if (storedBaseUrl != baseUrl) {
      await prefs.setString(_prefsBaseUrl, baseUrl);
    }
    final email = (prefs.getString(_prefsEmail) ?? '').trim();
    final access = (prefs.getString(_prefsAccess) ?? '').trim();
    final refresh = (prefs.getString(_prefsRefresh) ?? '').trim();
    final deviceId = (prefs.getString(_prefsDeviceId) ?? '').trim();
    final lastServerTime = (prefs.getString(_prefsLastServerTime) ?? '').trim();

    return CloudSettingsData(
      enabled: enabled,
      baseUrl: baseUrl,
      email: email,
      accessToken: access,
      refreshToken: refresh,
      deviceId: deviceId,
      lastServerTime: lastServerTime,
    );
  }

  static Future<void> save({
    required bool enabled,
    required String baseUrl,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Ignore caller value: always ON.
    await prefs.setBool(_prefsEnabled, true);
    // Ignore caller value: base URL is fixed by build-time config.
    await prefs.setString(_prefsBaseUrl, envBaseUrl);
    await prefs.setString(_prefsEmail, email.trim());
  }

  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAccess, accessToken.trim());
    await prefs.setString(_prefsRefresh, refreshToken.trim());
  }

  static Future<void> saveDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDeviceId, deviceId.trim());
  }

  static Future<void> saveLastServerTime(String serverTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastServerTime, serverTime.trim());
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsAccess);
    await prefs.remove(_prefsRefresh);
  }

  static Future<void> saveLastCloudStatus({
    required bool ok,
    required String message,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLastCloudOk, ok);
    await prefs.setString(_prefsLastCloudMessage, message.trim());
    await prefs.setInt(_prefsLastCloudAtMs, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<String> loadLastCloudMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_prefsLastCloudMessage) ?? '').trim();
  }

  static Future<bool?> loadLastCloudOk() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsLastCloudOk);
  }
}
