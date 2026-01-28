import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_settings.dart';

class ReportContext {
  ReportContext({
    required this.dateKey,
    required this.userName,
    required this.role,
    required this.isWorkDay,
    required this.scheduleLabel,
    required this.hasEntrada,
    required this.hasSalida,
    required this.pendientesHoy,
    required this.instalacionesEnCurso,
    required this.isCloudy,
    this.adminActiveUsers,
    this.adminSinEntrada,
    this.adminSalidaPendiente,
    this.adminSinEntradaSample,
    this.adminSalidaPendienteSample,
  });

  final String dateKey;
  final String userName;
  final String role;
  final bool isWorkDay;
  final String scheduleLabel;
  final bool hasEntrada;
  final bool hasSalida;
  final int pendientesHoy;
  final int instalacionesEnCurso;
  final bool? isCloudy;

  // Solo para Admin (pueden venir null para otros roles)
  final int? adminActiveUsers;
  final int? adminSinEntrada;
  final int? adminSalidaPendiente;
  final List<String>? adminSinEntradaSample;
  final List<String>? adminSalidaPendienteSample;
}

class ReportIntelligence {
  static const _prefsKeyDate = 'report_ai_date';
  static const _prefsKeyText = 'report_ai_text';

  static Future<String> getDailyInsight(ReportContext ctx) async {
    final prefs = await SharedPreferences.getInstance();

    final cacheKey = _cacheKey(ctx);
    final cachedDate = prefs.getString(_prefsKeyDate);
    final cachedText = (prefs.getString(_prefsKeyText) ?? '').trim();

    if (cachedDate == cacheKey && cachedText.isNotEmpty) {
      return cachedText;
    }

    final online = await _tryGenerateOnline(ctx);
    final text = (online ?? _fallback(ctx)).trim();

    await prefs.setString(_prefsKeyDate, cacheKey);
    await prefs.setString(_prefsKeyText, text);

    return text;
  }

  static String _cacheKey(ReportContext ctx) {
    final name = ctx.userName.trim().toLowerCase();
    final role = _normRole(ctx.role);
    return '${ctx.dateKey}|$role|$name';
  }

  static Future<String?> _tryGenerateOnline(ReportContext ctx) async {
    final settings = await AiSettings.load();
    if (!settings.enabled) return null;

    final apiKey = AiSettings.effectiveApiKey(settings);
    final model = AiSettings.effectiveModel(settings);
    if (apiKey.trim().isEmpty) return null;
    if (const bool.fromEnvironment('FLUTTER_TEST')) return null;

    final prompt = _prompt(ctx);

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
              'temperature': 0.6,
              'max_tokens': 120,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Eres el asistente operativo de FULLTECH. Respondes en español, tono corporativo y directo. Sin emojis.',
                },
                {
                  'role': 'user',
                  'content': prompt,
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(resp.body);
      final choices = decoded is Map ? decoded['choices'] : null;
      if (choices is! List || choices.isEmpty) return null;
      final msg = choices.first;
      final content = (msg is Map ? msg['message'] : null);
      final text = (content is Map ? content['content'] : null)?.toString();
      if (text == null) return null;

      final cleaned = _clean(text);
      if (cleaned.isEmpty) return null;
      return cleaned;
    } catch (_) {
      return null;
    }
  }

  static String _prompt(ReportContext ctx) {
    final role = _normRole(ctx.role);
    final weather = (ctx.isCloudy == null)
        ? 'Clima: no disponible.'
        : (ctx.isCloudy! ? 'Clima: nublado.' : 'Clima: estable.');

    final punch = (!ctx.isWorkDay)
        ? 'Hoy no es día laborable según horario.'
        : (!ctx.hasEntrada)
            ? 'Ponche: sin entrada registrada hoy.'
            : (!ctx.hasSalida)
                ? 'Ponche: entrada registrada, salida pendiente.'
                : 'Ponche: entrada y salida registradas.';

    final adminBlock = (role == 'admin')
        ? '''\n\nContexto admin (equipo):\n- Usuarios activos: ${ctx.adminActiveUsers ?? 0}\n- Sin ponche de entrada: ${ctx.adminSinEntrada ?? 0}${_sampleSuffix(ctx.adminSinEntradaSample)}\n- Con salida pendiente: ${ctx.adminSalidaPendiente ?? 0}${_sampleSuffix(ctx.adminSalidaPendienteSample)}'''
        : '';

    return '''Genera un mensaje corto (2-3 líneas) para el dashboard de FULLTECH, personalizado por rol.

Reglas:
- Profesional, operativo, nada cursi. Sin emojis.
- No menciones configuración ni ajustes.
- Personaliza por rol:
  - tecnico: ruta, checklist, pruebas, evidencias, herramientas, aprendizaje técnico.
  - vendedor: seguimiento a clientes, llamadas, cierres, cotizaciones, pendientes.
  - marketing: contenido, fotos, campañas, anuncios, seguimiento leads.
  - admin: control operativo, ponches, novedades raras, riesgos, prioridades.
  - asistente: documentación, soporte interno, cobros/seguimiento, coordinación.
- Máximo 240 caracteres.

Contexto:
- Usuario: ${ctx.userName}
- Rol: ${ctx.role}
- Fecha: ${ctx.dateKey}
- Horario: ${ctx.scheduleLabel}
- $punch
- Pendientes hoy: ${ctx.pendientesHoy}
- Instalaciones en curso: ${ctx.instalacionesEnCurso}
- $weather
$adminBlock

Solo devuelve el texto.''';
  }

  static String _fallback(ReportContext ctx) {
    final name = ctx.userName.trim().isEmpty ? 'Equipo' : ctx.userName.trim();
    final role = _normRole(ctx.role);

    // Admin: prioriza estado del equipo y anomalías.
    if (role == 'admin') {
      final sinEntrada = ctx.adminSinEntrada ?? 0;
      final salidaPend = ctx.adminSalidaPendiente ?? 0;
      final activos = ctx.adminActiveUsers ?? 0;

      if (sinEntrada > 0) {
        final sample = _sampleSuffix(ctx.adminSinEntradaSample);
        return 'Admin: $sinEntrada de $activos sin ponche de entrada$sample. Verifica novedades y coordina prioridades del día.';
      }

      if (salidaPend > 0 && ctx.isWorkDay) {
        final sample = _sampleSuffix(ctx.adminSalidaPendienteSample);
        return 'Admin: $salidaPend con salida pendiente$sample. Asegura cierres, evidencias y seguimiento a pendientes críticos.';
      }

      return 'Admin: monitorea ponches, bloqueados y pendientes. Si el flujo está estable, enfoca en seguimiento a clientes y control de calidad.';
    }

    if (ctx.isWorkDay && !ctx.hasEntrada) {
      return '$name, confirma tu ponche de entrada y prioriza lo de hoy: herramientas listas, checklist y pruebas completas.';
    }

    if (ctx.isWorkDay && ctx.hasEntrada && !ctx.hasSalida) {
      return 'Buen ritmo, $name. Cierra cada servicio con pruebas y evidencias; al finalizar la jornada no olvides tu ponche de salida.';
    }

    if ((ctx.isCloudy ?? false) && ctx.instalacionesEnCurso > 0) {
      return '$name, hoy está nublado: protege equipos y conexiones, evita humedad en cajas y valida señales antes de cerrar.';
    }

    if (ctx.pendientesHoy == 0 && ctx.instalacionesEnCurso == 0) {
      switch (role) {
        case 'tecnico':
          return '$name, sin agenda cargada: revisa inventario, da mantenimiento a herramientas y refuerza capacitación (cámaras, portones, POS).';
        case 'marketing':
          return '$name, hoy toca empuje: toma fotos, crea contenido, lanza campaña y dale seguimiento a leads y mensajes.';
        case 'vendedor':
          return '$name, aprovecha para llamadas y seguimiento a clientes: cotizaciones abiertas, pendientes y cierres del día.';
        case 'asistente':
          return '$name, organiza pendientes internos: documentación, coordinación, cobros/seguimiento y soporte al equipo.';
        default:
          return '$name, agenda ligera: refuerza seguimiento a clientes, pendientes y orden operativo.';
      }
    }

    switch (role) {
      case 'tecnico':
        return '$name, enfoque técnico: diagnóstico claro, instalación limpia, pruebas completas y evidencia antes de cerrar.';
      case 'marketing':
        return '$name, enfoque en impacto: contenido diario, campañas activas y respuesta rápida a leads.';
      case 'vendedor':
        return '$name, enfoque en cierre: seguimiento, objeciones resueltas y confirmación con el cliente.';
      case 'asistente':
        return '$name, enfoque en soporte: orden, documentación y coordinación para que el equipo cierre sin fricciones.';
      default:
        return '$name, enfoque en ejecución: orden, calidad y seguimiento.';
    }
  }

  static String _normRole(String? raw) {
    final r = (raw ?? '').trim().toLowerCase();
    if (r.isEmpty) return 'desconocido';

    // Tokeniza para evitar falsos positivos como "administrativo".
    final tokens =
        r.split(RegExp(r'[^a-z0-9áéíóúüñ]+')).where((t) => t.isNotEmpty);

    if (tokens.contains('asistente')) return 'asistente';
    if (tokens.contains('marketing')) return 'marketing';
    if (tokens.contains('vendedor')) return 'vendedor';
    if (tokens.contains('tecnico') || tokens.contains('técnico')) {
      return 'tecnico';
    }

    // Solo Admin cuando el rol sea explícitamente Admin.
    if (tokens.length == 1 &&
        (tokens.first == 'admin' || tokens.first == 'administrador')) {
      return 'admin';
    }

    return r;
  }

  static String _sampleSuffix(List<String>? names) {
    final list = (names ?? [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (list.isEmpty) return '';
    final shown = list.take(3).join(', ');
    return ' ($shown)';
  }

  static String _clean(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[\r\n]+'), ' ');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
    s = s.replaceAll('"', '');
    s = s.replaceAll('“', '').replaceAll('”', '');

    if (s.length > 240) {
      s = s.substring(0, 240).trimRight();
      s = s.replaceAll(RegExp(r'\s+\S*$'), '').trimRight();
    }

    return s;
  }
}
