import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../ui/fulltech_widgets.dart';
import 'operaciones_types.dart';

class TecnicosPage extends StatefulWidget {
  const TecnicosPage({super.key});

  @override
  State<TecnicosPage> createState() => _TecnicosPageState();
}

class _TecnicosPageState extends State<TecnicosPage> {
  final _db = AppDatabase.instance;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Técnicos'),
        actions: [
          IconButton(
            tooltip: 'Agregar',
            onPressed: () => _openForm(context),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: CenteredList(
        child: StreamBuilder<void>(
          stream: _db.changes,
          builder: (context, _) {
            return FutureBuilder<List<Map<String, Object?>>>(
              future:
                  _db.queryAll('tecnicos', orderBy: 'nombre COLLATE NOCASE'),
              builder: (context, snapshot) {
                final rows = snapshot.data ?? const <Map<String, Object?>>[];
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                final q = _search.text.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? rows
                    : rows.where((r) {
                        final nombre = (r['nombre'] as String?) ?? '';
                        final tel = (r['telefono'] as String?) ?? '';
                        final esp = (r['especialidad'] as String?) ?? '';
                        final estado = (r['estado'] as String?) ?? '';
                        return '$nombre $tel $esp $estado'
                            .toLowerCase()
                            .contains(q);
                      }).toList(growable: false);

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Column(
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Buscar',
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Nombre, teléfono, especialidad…',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const _EmptyState(
                                title: 'Sin técnicos',
                                subtitle:
                                    'Agrega técnicos para asignar operaciones.',
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) {
                                  final r = filtered[i];
                                  final id = (r['id'] as int?) ?? 0;
                                  final nombre =
                                      (r['nombre'] as String?) ?? 'Técnico';
                                  final tel = (r['telefono'] as String?) ?? '';
                                  final esp =
                                      (r['especialidad'] as String?) ?? '—';
                                  final estado =
                                      (r['estado'] as String?) ?? '—';

                                  return FutureBuilder<_TecnicoStats>(
                                    future: _statsForTecnico(id),
                                    builder: (context, s) {
                                      final stats = s.data;
                                      final subtitleParts = <String>[esp];
                                      if (tel.trim().isNotEmpty)
                                        subtitleParts.add(tel);
                                      if (stats != null) {
                                        subtitleParts.add(
                                            'Asignadas: ${stats.asignadas}');
                                        subtitleParts.add(
                                            'Completadas: ${stats.completadas}');
                                      }

                                      return FullTechCard(
                                        icon: Icons.engineering_outlined,
                                        title: nombre,
                                        subtitle: subtitleParts.join(' • '),
                                        trailing: '#$id',
                                        badge: estado,
                                        onTap: () =>
                                            _openForm(context, existing: r),
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<_TecnicoStats> _statsForTecnico(int tecnicoId) async {
    if (tecnicoId <= 0)
      return const _TecnicoStats(asignadas: 0, completadas: 0);

    final assigned = await _db.db.rawQuery(
      '''
SELECT COUNT(*) AS c
FROM operaciones
WHERE tecnico_id = ?
  AND estado IN ('Pendiente','Programada','En proceso','Pendiente de pago')
''',
      [tecnicoId],
    );

    final completed = await _db.db.rawQuery(
      '''
SELECT COUNT(*) AS c
FROM operaciones
WHERE tecnico_id = ?
  AND estado = 'Finalizada'
''',
      [tecnicoId],
    );

    final a = ((assigned.firstOrNull?['c'] as int?) ?? 0);
    final c = ((completed.firstOrNull?['c'] as int?) ?? 0);
    return _TecnicoStats(asignadas: a, completadas: c);
  }

  Future<void> _openForm(BuildContext context,
      {Map<String, Object?>? existing}) {
    return showFullTechFormSheet<void>(
      context: context,
      child: _TecnicoFormSheet(existing: existing),
    );
  }
}

class _TecnicoStats {
  const _TecnicoStats({required this.asignadas, required this.completadas});

  final int asignadas;
  final int completadas;
}

class _TecnicoFormSheet extends StatefulWidget {
  const _TecnicoFormSheet({this.existing});

  final Map<String, Object?>? existing;

  @override
  State<_TecnicoFormSheet> createState() => _TecnicoFormSheetState();
}

class _TecnicoFormSheetState extends State<_TecnicoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();

  String _especialidad = kTecnicoEspecialidades.first;
  String _estado = kTecnicoEstados.first;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) return;

    _nombre.text = (e['nombre'] as String?) ?? '';
    _telefono.text = (e['telefono'] as String?) ?? '';
    _especialidad = (e['especialidad'] as String?) ?? _especialidad;
    _estado = (e['estado'] as String?) ?? _estado;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FullTechSheetHeader(
            title: isEdit ? 'Editar técnico' : 'Nuevo técnico',
            subtitle: 'Control de disponibilidad y especialidad',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nombre,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telefono,
            decoration: const InputDecoration(labelText: 'Teléfono'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _especialidad,
            decoration: const InputDecoration(labelText: 'Especialidad'),
            items: kTecnicoEspecialidades
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(growable: false),
            onChanged: (v) =>
                setState(() => _especialidad = v ?? _especialidad),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _estado,
            decoration: const InputDecoration(labelText: 'Estado'),
            items: kTecnicoEstados
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(growable: false),
            onChanged: (v) => setState(() => _estado = v ?? _estado),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final now = DateTime.now().millisecondsSinceEpoch;
    final values = {
      'nombre': _nombre.text.trim(),
      'telefono': _telefono.text.trim(),
      'especialidad': _especialidad,
      'estado': _estado,
      'actualizado_en': now,
    };

    final existing = widget.existing;
    if (existing == null) {
      await AppDatabase.instance.insert('tecnicos', {
        ...values,
        'creado_en': now,
      });
    } else {
      final id = (existing['id'] as int?) ?? 0;
      if (id > 0) {
        await AppDatabase.instance.update('tecnicos', values, id: id);
      }
    }

    if (mounted) Navigator.of(context).pop();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 34),
            const SizedBox(height: 10),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
