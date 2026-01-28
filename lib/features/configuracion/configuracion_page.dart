import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../auth/login_page.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  final _db = AppDatabase.instance;

  final _nombreCtrl = TextEditingController();
  final _rncCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _webCtrl = TextEditingController();
  final _infoGeneralCtrl = TextEditingController();
  final _infoEspecialCtrl = TextEditingController();
  final _ubicacionLatCtrl = TextEditingController();
  final _ubicacionLonCtrl = TextEditingController();

  String? _logoPath;
  TimeOfDay? _horaEntrada;
  TimeOfDay? _horaSalida;
  Set<int> _diasLaborables = {1, 2, 3, 4, 5, 6};
  bool _detectingLocation = false;
  bool _loading = true;
  bool _saving = false;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cfg = await _db.getEmpresaConfig();
      _nombreCtrl.text = ((cfg?['nombre'] as String?) ?? '').trim();
      _rncCtrl.text = ((cfg?['rnc'] as String?) ?? '').trim();
      _telefonoCtrl.text = ((cfg?['telefono'] as String?) ?? '').trim();
      _emailCtrl.text = ((cfg?['email'] as String?) ?? '').trim();
      _direccionCtrl.text = ((cfg?['direccion'] as String?) ?? '').trim();
      _webCtrl.text = ((cfg?['web'] as String?) ?? '').trim();
      _logoPath = ((cfg?['logo_path'] as String?) ?? '').trim();
      if (_logoPath != null && _logoPath!.isEmpty) _logoPath = null;

      _infoGeneralCtrl.text = ((cfg?['info_general'] as String?) ?? '').trim();
      _infoEspecialCtrl.text =
          ((cfg?['info_especial'] as String?) ?? '').trim();

      final horarioRaw = (cfg?['horario_json'] as String?)?.trim();
      if (horarioRaw != null && horarioRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(horarioRaw);
          if (decoded is Map) {
            final start = decoded['start']?.toString();
            final end = decoded['end']?.toString();
            final days = decoded['days'];
            _horaEntrada = _parseTime(start) ?? _horaEntrada;
            _horaSalida = _parseTime(end) ?? _horaSalida;
            if (days is List) {
              _diasLaborables = days
                  .map((e) => int.tryParse(e.toString()))
                  .whereType<int>()
                  .where((d) => d >= 1 && d <= 7)
                  .toSet();
              if (_diasLaborables.isEmpty) {
                _diasLaborables = {1, 2, 3, 4, 5, 6};
              }
            }
          }
        } catch (_) {}
      }

      final lat = cfg?['ubicacion_lat'];
      final lon = cfg?['ubicacion_lon'];
      _ubicacionLatCtrl.text = (lat == null) ? '' : lat.toString();
      _ubicacionLonCtrl.text = (lon == null) ? '' : lon.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay? _parseTime(String? hhmm) {
    final s = (hhmm ?? '').trim();
    if (!s.contains(':')) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23) return null;
    if (m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String? _encodeHorarioJson() {
    final start = _horaEntrada;
    final end = _horaSalida;
    final days = _diasLaborables.toList()..sort();
    if (start == null || end == null) return null;
    if (days.isEmpty) return null;

    String fmt(TimeOfDay t) {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    return jsonEncode({
      'start': fmt(start),
      'end': fmt(end),
      'days': days,
    });
  }

  Future<void> _pickHoraEntrada() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _horaEntrada ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null) return;
    setState(() => _horaEntrada = picked);
  }

  Future<void> _pickHoraSalida() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _horaSalida ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked == null) return;
    setState(() => _horaSalida = picked);
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final srcPath = result.files.single.path;
    if (srcPath == null || srcPath.trim().isEmpty) return;

    final src = File(srcPath);
    if (!await src.exists()) return;

    final dir = await getApplicationDocumentsDirectory();
    final ext = p.extension(srcPath);
    final safeExt = ext.isEmpty ? '.png' : ext;
    final destPath = p.join(dir.path, 'empresa_logo$safeExt');
    await src.copy(destPath);

    if (!mounted) return;
    setState(() => _logoPath = destPath);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final lat = double.tryParse(_ubicacionLatCtrl.text.trim());
      final lon = double.tryParse(_ubicacionLonCtrl.text.trim());

      await _db.upsertEmpresaConfig(
        nombre: _nombreCtrl.text,
        rnc: _rncCtrl.text,
        telefono: _telefonoCtrl.text,
        email: _emailCtrl.text,
        direccion: _direccionCtrl.text,
        web: _webCtrl.text,
        logoPath: _logoPath,
        infoGeneral: _infoGeneralCtrl.text,
        infoEspecial: _infoEspecialCtrl.text,
        horarioJson: _encodeHorarioJson(),
        ubicacionLat: lat,
        ubicacionLon: lon,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración guardada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _detectLocationAuto() async {
    if (_detectingLocation) return;

    setState(() => _detectingLocation = true);
    try {
      // Ubicación aproximada por IP (sin permisos). Útil para desktop.
      final uri = Uri.parse('https://ipwho.is/');
      final resp = await http.get(uri).timeout(const Duration(seconds: 7));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Respuesta ${resp.statusCode}');
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) throw Exception('Respuesta inválida');

      final success = decoded['success'];
      if (success is bool && success == false) {
        final msg = decoded['message']?.toString();
        throw Exception(msg ?? 'No se pudo detectar');
      }

      double? toDouble(dynamic v) {
        if (v is num) return v.toDouble();
        return double.tryParse(v?.toString() ?? '');
      }

      final lat = toDouble(decoded['latitude']);
      final lon = toDouble(decoded['longitude']);

      if (lat == null || lon == null) {
        throw Exception('Lat/Lon no disponibles');
      }

      _ubicacionLatCtrl.text = lat.toStringAsFixed(6);
      _ubicacionLonCtrl.text = lon.toStringAsFixed(6);

      // Guardar inmediatamente solo la ubicación (preservando lo demás).
      Map<String, Object?>? cfg;
      try {
        cfg = await _db.getEmpresaConfig();
      } catch (_) {}

      String cfgStr(String key) => ((cfg?[key] as String?) ?? '').trim();
      String? cfgNullableStr(String key) {
        final v = (cfg?[key] as String?)?.trim();
        return (v == null || v.isEmpty) ? null : v;
      }

      await _db.upsertEmpresaConfig(
        nombre: cfgStr('nombre'),
        rnc: cfgStr('rnc'),
        telefono: cfgStr('telefono'),
        email: cfgStr('email'),
        direccion: cfgStr('direccion'),
        web: cfgStr('web'),
        logoPath: cfgNullableStr('logo_path'),
        infoGeneral: cfgStr('info_general'),
        infoEspecial: cfgStr('info_especial'),
        horarioJson: (cfg?['horario_json'] as String?)?.trim(),
        ubicacionLat: lat,
        ubicacionLon: lon,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación detectada y guardada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo detectar ubicación: $e')),
      );
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text('Deseas salir de la sesion actual?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loggingOut = true);
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _rncCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _direccionCtrl.dispose();
    _webCtrl.dispose();
    _infoGeneralCtrl.dispose();
    _infoEspecialCtrl.dispose();
    _ubicacionLatCtrl.dispose();
    _ubicacionLonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuracion'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: (_loading || _saving) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Empresa',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LogoPreview(path: _logoPath),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _pickLogo,
                                    icon:
                                        const Icon(Icons.upload_file_outlined),
                                    label: const Text('Subir logo'),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Se usará en el encabezado de los PDFs.',
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Field(label: 'Nombre', controller: _nombreCtrl),
                        const SizedBox(height: 10),
                        _Field(label: 'RNC', controller: _rncCtrl),
                        const SizedBox(height: 10),
                        _Field(label: 'Teléfono', controller: _telefonoCtrl),
                        const SizedBox(height: 10),
                        _Field(label: 'Email', controller: _emailCtrl),
                        const SizedBox(height: 10),
                        _Field(
                            label: 'Dirección',
                            controller: _direccionCtrl,
                            maxLines: 2),
                        const SizedBox(height: 10),
                        _Field(label: 'Web', controller: _webCtrl),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Mural',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Estos mensajes aparecen en el Reporte (mural) al iniciar la app. Úsalos para feriados, avisos internos, recordatorios, etc.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          label: 'Información general',
                          controller: _infoGeneralCtrl,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          label: 'Información especial (destacada)',
                          controller: _infoEspecialCtrl,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Horario y clima',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Esto alimenta el Reporte inteligente: recordatorios de ponche según horario y aviso de clima (nublado).',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.login_rounded),
                          title: const Text('Hora de entrada'),
                          subtitle: Text(
                            _horaEntrada == null
                                ? 'No configurada'
                                : _horaEntrada!.format(context),
                          ),
                          trailing: TextButton(
                            onPressed: _pickHoraEntrada,
                            child: const Text('Cambiar'),
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.logout_rounded),
                          title: const Text('Hora de salida'),
                          subtitle: Text(
                            _horaSalida == null
                                ? 'No configurada'
                                : _horaSalida!.format(context),
                          ),
                          trailing: TextButton(
                            onPressed: _pickHoraSalida,
                            child: const Text('Cambiar'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Días laborables',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final d in const [
                              (1, 'L'),
                              (2, 'M'),
                              (3, 'Mi'),
                              (4, 'J'),
                              (5, 'V'),
                              (6, 'S'),
                              (7, 'D'),
                            ])
                              FilterChip(
                                label: Text(d.$2),
                                selected: _diasLaborables.contains(d.$1),
                                onSelected: (v) {
                                  setState(() {
                                    if (v) {
                                      _diasLaborables.add(d.$1);
                                    } else {
                                      _diasLaborables.remove(d.$1);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          label: 'Ubicación (latitud) - opcional',
                          controller: _ubicacionLatCtrl,
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          label: 'Ubicación (longitud) - opcional',
                          controller: _ubicacionLonCtrl,
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed:
                                _detectingLocation ? null : _detectLocationAuto,
                            icon: _detectingLocation
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.my_location_outlined),
                            label: const Text('Detectar automáticamente'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ejemplo Santo Domingo: 18.4861 / -69.9312',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Nota: es una ubicación aproximada (por IP).',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pth = path;

    Widget child;
    if (pth == null || pth.trim().isEmpty) {
      child = Center(
        child: Text(
          'Sin logo',
          style: TextStyle(
              color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
        ),
      );
    } else {
      final file = File(pth);
      child = FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snap) {
          final ok = snap.data ?? false;
          if (!ok) {
            return Center(
              child: Text(
                'No encontrado',
                style: TextStyle(
                    color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              fit: BoxFit.contain,
            ),
          );
        },
      );
    }

    return Container(
      width: 110,
      height: 110,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
