import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_settings.dart';

class DailyMotivation {
  static const _prefsKeyDate = 'daily_motivation_date';
  static const _prefsKeyPhrase = 'daily_motivation_phrase';

  static Future<String> getTodayPhrase() async {
    final today = _yyyyMmDd(DateTime.now());
    final prefs = await SharedPreferences.getInstance();

    final cachedDate = prefs.getString(_prefsKeyDate);
    final cachedPhrase = (prefs.getString(_prefsKeyPhrase) ?? '').trim();

    if (cachedDate == today && cachedPhrase.isNotEmpty) {
      return cachedPhrase;
    }

    final generated = await _tryGenerateOnline(today: today);
    final phrase = (generated ?? _fallbackPhrase(today)).trim();

    await prefs.setString(_prefsKeyDate, today);
    await prefs.setString(_prefsKeyPhrase, phrase);

    return phrase;
  }

  static Future<String?> _tryGenerateOnline({required String today}) async {
    final settings = await AiSettings.load();
    if (!settings.enabled) return null;

    final apiKey = AiSettings.effectiveApiKey(settings);
    final model = AiSettings.effectiveModel(settings);
    if (apiKey.trim().isEmpty) return null;

    // Evita llamadas de red durante tests.
    if (const bool.fromEnvironment('FLUTTER_TEST')) return null;

    final prompt = _buildPrompt(today);

    try {
      final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      final resp = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0.7,
              'max_tokens': 80,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Eres un asistente corporativo de FULLTECH. Respondes en español dominicano neutro y con tono profesional.',
                },
                {
                  'role': 'user',
                  'content': prompt,
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 7));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(resp.body);
      final content = (decoded?['choices'] as List?)
          ?.cast<dynamic>()
          .firstOrNull?['message']?['content']
          ?.toString();

      if (content == null) return null;
      final cleaned = _clean(content);
      if (cleaned.isEmpty) return null;

      return cleaned;
    } catch (_) {
      return null;
    }
  }

  static String _buildPrompt(String today) {
    // Reglas: profesional, no cursi, sin emojis, dirigido a técnicos e instaladores.
    return '''Genera UNA sola frase motivacional diaria para FULLTECH.

Fecha: $today.
Audiencia: técnicos e instaladores (cámaras, portones, POS).
Tono: profesional, directo, corporativo. No cursi. No religioso. Sin emojis.
Formato: 1 frase, máximo 140 caracteres.
Contenido: enfoque en seguridad, calidad, diagnóstico, tiempos, cierre de instalaciones y servicio al cliente.
No incluyas comillas ni viñetas. Solo la frase.''';
  }

  static String _fallbackPhrase(String today) {
    const phrases = [
      'Diagnostica con calma, instala con precisión y entrega con evidencia: calidad FULLTECH.',
      'Hoy: seguridad primero, cableado limpio y pruebas completas antes de cerrar el servicio.',
      'Cada instalación bien documentada evita retrabajo: fotos, checklist y entrega clara.',
      'Cámaras, portones o POS: termina con pruebas, capacitación y un cliente seguro.',
      'Orden en el sitio, herramientas listas y pruebas finales: así se gana confianza.',
      'Tiempo y calidad se miden en detalles: etiqueta, organiza y valida cada conexión.',
      'Un buen técnico no adivina: mide, verifica y deja todo funcionando al 100%.',
      'Cierra cada trabajo con estándares: limpieza, checklist y confirmación del cliente.',
      'Hoy se resuelve con método: diagnóstico, ejecución y prueba final sin atajos.',
      'Instala como si fuera tu casa: seguro, limpio, alineado y bien probado.',
    ];

    final hash = _stableHash(today);
    return phrases[hash % phrases.length];
  }

  static int _stableHash(String s) {
    var h = 0;
    for (final codeUnit in s.codeUnits) {
      h = 0x1fffffff & (h + codeUnit);
      h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
      h ^= (h >> 6);
    }
    h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
    h ^= (h >> 11);
    return 0x1fffffff & (h + ((0x00003fff & h) << 15));
  }

  static String _yyyyMmDd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _clean(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[\r\n]+'), ' ');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
    s = s.replaceAll('"', '');
    s = s.replaceAll('“', '').replaceAll('”', '');

    if (s.length > 140) {
      s = s.substring(0, 140).trimRight();
      s = s.replaceAll(RegExp(r'\s+\S*$'), '').trimRight();
    }

    return s;
  }
}

extension _FirstOrNullExt on List<dynamic> {
  dynamic get firstOrNull => isEmpty ? null : first;
}
