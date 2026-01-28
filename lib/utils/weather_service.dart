import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WeatherSnapshot {
  WeatherSnapshot({required this.cloudCover, required this.fetchedAt});

  /// 0..100
  final int cloudCover;
  final DateTime fetchedAt;

  bool get isCloudy => cloudCover >= 65;
}

class WeatherService {
  static const _prefsKeyCacheJson = 'weather_cache_json';
  static const _prefsKeyCacheAtMs = 'weather_cache_at_ms';

  /// Devuelve null si no hay ubicación o falla (sin bloquear el UI).
  static Future<WeatherSnapshot?> getCurrent({
    required double? lat,
    required double? lon,
  }) async {
    if (lat == null || lon == null) return null;

    // Cache básico para no martillar la red.
    final prefs = await SharedPreferences.getInstance();
    final cachedAtMs = prefs.getInt(_prefsKeyCacheAtMs);
    final cachedJson = prefs.getString(_prefsKeyCacheJson);

    if (cachedAtMs != null && cachedJson != null && cachedJson.isNotEmpty) {
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(cachedAtMs));
      if (age.inMinutes <= 30) {
        final parsed = _parseSnapshot(cachedJson);
        if (parsed != null) return parsed;
      }
    }

    final fetched = await _fetchFromOpenMeteo(lat: lat, lon: lon);
    if (fetched == null) return null;

    await prefs.setInt(
        _prefsKeyCacheAtMs, fetched.fetchedAt.millisecondsSinceEpoch);
    await prefs.setString(
        _prefsKeyCacheJson,
        jsonEncode({
          'cloudCover': fetched.cloudCover,
          'fetchedAt': fetched.fetchedAt.toIso8601String(),
        }));

    return fetched;
  }

  static WeatherSnapshot? _parseSnapshot(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return null;
      final cc = int.tryParse(decoded['cloudCover']?.toString() ?? '');
      final atRaw = decoded['fetchedAt']?.toString();
      if (cc == null || atRaw == null) return null;
      final at = DateTime.tryParse(atRaw);
      if (at == null) return null;
      return WeatherSnapshot(cloudCover: cc.clamp(0, 100), fetchedAt: at);
    } catch (_) {
      return null;
    }
  }

  static Future<WeatherSnapshot?> _fetchFromOpenMeteo({
    required double lat,
    required double lon,
  }) async {
    // Evita llamadas de red durante tests.
    if (const bool.fromEnvironment('FLUTTER_TEST')) return null;

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon&current=cloud_cover&timezone=auto',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

      final decoded = jsonDecode(resp.body);
      final current = decoded is Map ? decoded['current'] : null;
      if (current is! Map) return null;

      final ccRaw = current['cloud_cover'];
      final cc = (ccRaw is num) ? ccRaw.round() : int.tryParse('$ccRaw');
      if (cc == null) return null;

      return WeatherSnapshot(
        cloudCover: cc.clamp(0, 100),
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
