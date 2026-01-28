import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../ui/fulltech_widgets.dart';
import 'cliente_historial_operaciones_page.dart';
import 'operaciones_types.dart';
import 'tecnicos_page.dart';

class OperacionDetailPage extends StatefulWidget {
  const OperacionDetailPage({super.key, required this.operacionId});

  final int operacionId;

  @override
  State<OperacionDetailPage> createState() => _OperacionDetailPageState();
}

class _OperacionDetailPageState extends State<OperacionDetailPage> {
  final _db = AppDatabase.instance;

  String _evidenciaTipo = 'ANTES';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de operación'),
        actions: [
          IconButton(
            tooltip: 'Técnicos',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TecnicosPage())),
            icon: const Icon(Icons.engineering_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: CenteredList(
          child: StreamBuilder<void>(
            stream: _db.changes,
            builder: (context, _) {
              return FutureBuilder<_OperacionFull?>(
                future: _load(),
                builder: (context, snapshot) {
                  final op = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (op == null) {
                    return const _EmptyBox(
                      title: 'Operación no encontrada',
                      subtitle: 'Puede que haya sido eliminada o migrada.',
                    );
                  }

                  final editable = operacionEsEditable(op.estado);

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _HeaderCard(op: op),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Información general',
                        child: _GeneralInfo(
                            op: op,
                            onEdit: editable ? () => _editGeneral(op) : null),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Materiales',
                        child: _MaterialesSection(
                          operacionId: op.operacionId,
                          enabled: editable,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Avance del trabajo (checklist)',
                        child: _Checklist(
                          op: op,
                          enabled: editable,
                          onChanged: (field, value) => _setChecklist(
                              op.operacionId,
                              field: field,
                              value: value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Evidencias',
                        child: _Evidencias(
                          tipo: _evidenciaTipo,
                          enabled: editable,
                          onTipoChanged: (t) =>
                              setState(() => _evidenciaTipo = t),
                          onAdd: () => _addEvidencias(op.operacionId,
                              tipo: _evidenciaTipo),
                          itemsFuture: _db.db.query(
                            'operacion_evidencias',
                            where: 'operacion_id = ? AND tipo = ?',
                            whereArgs: [op.operacionId, _evidenciaTipo],
                            orderBy: 'creado_en DESC',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Notas del técnico (historial)',
                        child: _NotasSection(
                          operacionId: op.operacionId,
                          enabled: true,
                          onAdd: () => _addNota(op.operacionId),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Historial de estados',
                        child: _EstadosHistorial(operacionId: op.operacionId),
                      ),
                      const SizedBox(height: 14),
                      if (op.estado == 'Pendiente de pago') ...[
                        FilledButton.tonalIcon(
                          onPressed: () => _marcarComoPagado(op),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Marcar como pagado'),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (op.clienteNombre != '—')
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final clienteId = await _db.db.rawQuery(
                              'SELECT cliente_id AS c FROM operaciones WHERE id = ? LIMIT 1',
                              [op.operacionId],
                            );
                            final id =
                                (clienteId.firstOrNull?['c'] as int?) ?? 0;
                            if (id <= 0 || !context.mounted) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ClienteHistorialOperacionesPage(
                                  clienteId: id,
                                  clienteNombre: op.clienteNombre,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.history_outlined),
                          label: const Text('Historial del cliente'),
                        ),
                      if (op.clienteNombre != '—') const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: editable ? () => _cerrarOperacion(op) : null,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Cerrar operación'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _marcarComoPagado(_OperacionFull op) async {
    if (op.estado != 'Pendiente de pago') return;
    if (!op.hasTecnico) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se puede finalizar sin técnico asignado.')),
      );
      return;
    }

    // Validación extra: si alguien llegó aquí sin cierre correcto, no permite finalizar.
    final checklistOk = op.chkLlego &&
        op.chkMaterialInstalado &&
        op.chkSistemaProbado &&
        op.chkClienteCapacitado &&
        op.chkTrabajoTerminado;
    if (!checklistOk) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Completa el checklist antes de finalizar.')),
      );
      return;
    }

    final afterCount = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM operacion_evidencias WHERE operacion_id = ? AND tipo = ?',
      [op.operacionId, 'DESPUES'],
    );
    final afterEvid = ((afterCount.firstOrNull?['c'] as int?) ?? 0);
    if (afterEvid <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Agrega evidencia “DESPUES” antes de finalizar.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar pago'),
        content:
            const Text('Esto marcará la operación como Finalizada y Pagada.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.insert('operacion_estados_historial', {
      'operacion_id': op.operacionId,
      'de_estado': op.estado,
      'a_estado': 'Finalizada',
      'usuario_id': AuthService.instance.currentUserId,
      'creado_en': now,
    });

    await _db.update(
      'operaciones',
      {
        'estado': 'Finalizada',
        'pago_estado': 'Pagado',
        'actualizado_en': now,
      },
      id: op.operacionId,
    );

    if (op.tecnicoId != null) {
      await _db.update(
          'tecnicos', {'estado': 'Disponible', 'actualizado_en': now},
          id: op.tecnicoId!);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marcada como pagada y finalizada.')));
  }

  Future<_OperacionFull?> _load() async {
    final id = widget.operacionId;
    if (id <= 0) return null;

    final rows = await _db.db.rawQuery(
      '''
SELECT o.*, c.nombre AS cliente_nombre, c.telefono AS cliente_telefono,
       COALESCE(u.nombre, t.nombre, '—') AS tecnico_nombre
FROM operaciones o
LEFT JOIN clientes c ON c.id = o.cliente_id
LEFT JOIN usuarios u ON u.id = o.tecnico_usuario_id
LEFT JOIN tecnicos t ON t.id = o.tecnico_id
WHERE o.id = ?
LIMIT 1
''',
      [id],
    );
    if (rows.isEmpty) return null;
    return _OperacionFull.fromRow(rows.first);
  }

  Future<void> _setChecklist(int operacionId,
      {required String field, required bool value}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'operaciones',
      {field: value ? 1 : 0, 'actualizado_en': now},
      id: operacionId,
    );
  }

  Future<void> _addEvidencias(int operacionId, {required String tipo}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(
        p.join(dir.path, 'fulltech', 'operaciones', '$operacionId', tipo));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      final src = File(path);
      if (!await src.exists()) continue;

      final ext = p.extension(path);
      final name = 'EV_${DateTime.now().microsecondsSinceEpoch}$ext';
      final destPath = p.join(folder.path, name);
      await src.copy(destPath);

      await _db.insert('operacion_evidencias', {
        'operacion_id': operacionId,
        'tipo': tipo,
        'file_path': destPath,
        'creado_en': now,
      });
    }
  }

  Future<void> _addNota(int operacionId) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar nota'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nota'),
          maxLines: 4,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('operacion_notas', {
      'operacion_id': operacionId,
      'usuario_id': AuthService.instance.currentUserId,
      'nota': text,
      'creado_en': now,
    });
  }

  Future<void> _editGeneral(_OperacionFull op) async {
    // Edición minimalista: estado, técnico y pago.
    String estado = op.estado;
    int? tecnicoUsuarioId = op.tecnicoUsuarioId;
    String pagoEstado = op.pagoEstado;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualizar operación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: estado,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: kOperacionEstados
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(growable: false),
              onChanged: (v) => estado = v ?? estado,
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<Map<String, Object?>>>(
              future: _db.db.query(
                'usuarios',
                where:
                    '(rol = ? COLLATE NOCASE OR rol = ? COLLATE NOCASE) AND bloqueado = 0',
                whereArgs: ['Tecnico', 'Técnico'],
                orderBy: 'nombre COLLATE NOCASE',
              ),
              builder: (context, snapshot) {
                final tecnicos =
                    snapshot.data ?? const <Map<String, Object?>>[];
                return DropdownButtonFormField<int>(
                  value: tecnicoUsuarioId,
                  decoration: const InputDecoration(labelText: 'Técnico'),
                  items: tecnicos
                      .map((t) => DropdownMenuItem(
                          value: t['id'] as int,
                          child: Text((t['nombre'] ?? '') as String)))
                      .toList(growable: false),
                  onChanged: (v) => tecnicoUsuarioId = v,
                );
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: pagoEstado,
              decoration: const InputDecoration(labelText: 'Pago'),
              items: kPagoEstados
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(growable: false),
              onChanged: (v) => pagoEstado = v ?? pagoEstado,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;

    // Regla: no permitir finalizar sin técnico asignado.
    final hasTecnico = tecnicoUsuarioId != null || op.tecnicoId != null;
    if ((estado == 'Finalizada' || estado == 'Pendiente de pago') &&
        !hasTecnico) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Asigna un técnico antes de finalizar.')));
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    if (estado != op.estado) {
      await _db.insert('operacion_estados_historial', {
        'operacion_id': op.operacionId,
        'de_estado': op.estado,
        'a_estado': estado,
        'usuario_id': AuthService.instance.currentUserId,
        'creado_en': now,
      });
    }

    final data = <String, Object?>{
      'estado': estado,
      'pago_estado': pagoEstado,
      'actualizado_en': now,
    };

    // Si se seleccionó un técnico (usuarios), se guarda en tecnico_usuario_id
    // y se limpia el tecnico_id legacy.
    if (tecnicoUsuarioId != op.tecnicoUsuarioId) {
      data['tecnico_usuario_id'] = tecnicoUsuarioId;
      if (tecnicoUsuarioId != null) data['tecnico_id'] = null;
    }

    await _db.update('operaciones', data, id: op.operacionId);
  }

  Future<void> _cerrarOperacion(_OperacionFull op) async {
    // Reglas obligatorias:
    // - No cerrar sin evidencias
    // - No finalizar sin técnico asignado
    // - Confirmar checklist completo

    if (!op.hasTecnico) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se puede cerrar sin técnico asignado.')));
      return;
    }

    final evidCount = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM operacion_evidencias WHERE operacion_id = ?',
      [op.operacionId],
    );
    final totalEvid = ((evidCount.firstOrNull?['c'] as int?) ?? 0);

    final afterCount = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM operacion_evidencias WHERE operacion_id = ? AND tipo = ?',
      [op.operacionId, 'DESPUES'],
    );
    final afterEvid = ((afterCount.firstOrNull?['c'] as int?) ?? 0);

    if (totalEvid <= 0 || afterEvid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Para cerrar, agrega evidencias (incluye al menos “Después”).')),
      );
      return;
    }

    final checklistOk = op.chkLlego &&
        op.chkMaterialInstalado &&
        op.chkSistemaProbado &&
        op.chkClienteCapacitado &&
        op.chkTrabajoTerminado;
    if (!checklistOk) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Completa el checklist antes de cerrar.')));
      return;
    }

    final obs = TextEditingController();
    String garantia =
        op.garantiaTipo.isEmpty ? 'Sin garantía' : op.garantiaTipo;
    String pagoEstado = op.pagoEstado;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar operación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: obs,
              decoration:
                  const InputDecoration(labelText: 'Observaciones finales'),
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: pagoEstado,
              decoration: const InputDecoration(labelText: 'Estado de pago'),
              items: kPagoEstados
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(growable: false),
              onChanged: (v) => pagoEstado = v ?? pagoEstado,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: garantia,
              decoration: const InputDecoration(labelText: 'Garantía'),
              items: kGarantias
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(growable: false),
              onChanged: (v) => garantia = v ?? garantia,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cerrar')),
        ],
      ),
    );

    if (ok != true) return;
    final observaciones = obs.text.trim();
    if (observaciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Las observaciones finales son obligatorias.')));
      return;
    }

    final status = pagoEstado == 'Pagado' ? 'Finalizada' : 'Pendiente de pago';
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.insert('operacion_estados_historial', {
      'operacion_id': op.operacionId,
      'de_estado': op.estado,
      'a_estado': status,
      'usuario_id': AuthService.instance.currentUserId,
      'creado_en': now,
    });

    final vence = _garantiaVenceEn(garantia);

    await _db.update(
      'operaciones',
      {
        'estado': status,
        'observaciones_finales': observaciones,
        'pago_estado': pagoEstado,
        'garantia_tipo': garantia,
        'garantia_vence_en': vence,
        'finalizado_en': now,
        'actualizado_en': now,
      },
      id: op.operacionId,
    );

    // Al finalizar, liberamos técnico.
    if (status == 'Finalizada' && op.tecnicoId != null) {
      await _db.update(
          'tecnicos', {'estado': 'Disponible', 'actualizado_en': now},
          id: op.tecnicoId!);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Operación cerrada: $status')));
  }

  int? _garantiaVenceEn(String tipo) {
    final now = DateTime.now();
    DateTime? vence;

    if (tipo == '1 mes') vence = DateTime(now.year, now.month + 1, now.day);
    if (tipo == '3 meses') vence = DateTime(now.year, now.month + 3, now.day);
    if (tipo == '6 meses') vence = DateTime(now.year, now.month + 6, now.day);

    return vence?.millisecondsSinceEpoch;
  }
}

class _OperacionFull {
  _OperacionFull({
    required this.operacionId,
    required this.codigo,
    required this.estado,
    required this.prioridad,
    required this.tipoServicio,
    required this.clienteNombre,
    required this.clienteTelefono,
    required this.direccionServicio,
    required this.referenciaLugar,
    required this.tecnicoId,
    required this.tecnicoUsuarioId,
    required this.tecnicoNombre,
    required this.programadoEn,
    required this.horaEstimada,
    required this.monto,
    required this.formaPago,
    required this.pagoEstado,
    required this.chkLlego,
    required this.chkMaterialInstalado,
    required this.chkSistemaProbado,
    required this.chkClienteCapacitado,
    required this.chkTrabajoTerminado,
    required this.garantiaTipo,
    required this.garantiaVenceEn,
  });

  final int operacionId;
  final String codigo;
  final String estado;
  final String prioridad;
  final String tipoServicio;

  final String clienteNombre;
  final String clienteTelefono;
  final String direccionServicio;
  final String referenciaLugar;

  final int? tecnicoId;
  final int? tecnicoUsuarioId;
  final String tecnicoNombre;

  bool get hasTecnico => tecnicoUsuarioId != null || tecnicoId != null;

  final int? programadoEn;
  final String horaEstimada;

  final double monto;
  final String formaPago;
  final String pagoEstado;

  final bool chkLlego;
  final bool chkMaterialInstalado;
  final bool chkSistemaProbado;
  final bool chkClienteCapacitado;
  final bool chkTrabajoTerminado;

  final String garantiaTipo;
  final int? garantiaVenceEn;

  static _OperacionFull fromRow(Map<String, Object?> r) {
    return _OperacionFull(
      operacionId: (r['id'] as int?) ?? 0,
      codigo: (r['codigo'] as String?) ?? '—',
      estado: (r['estado'] as String?) ?? 'Pendiente',
      prioridad: (r['prioridad'] as String?) ?? 'Normal',
      tipoServicio: (r['tipo_servicio'] as String?) ??
          ((r['titulo'] as String?) ?? 'Servicio'),
      clienteNombre: (r['cliente_nombre'] as String?) ?? '—',
      clienteTelefono: (r['cliente_telefono'] as String?) ?? '',
      direccionServicio: (r['direccion_servicio'] as String?) ?? '',
      referenciaLugar: (r['referencia_lugar'] as String?) ?? '',
      tecnicoId: r['tecnico_id'] as int?,
      tecnicoUsuarioId: r['tecnico_usuario_id'] as int?,
      tecnicoNombre: (r['tecnico_nombre'] as String?) ?? '—',
      programadoEn: r['programado_en'] as int?,
      horaEstimada: (r['hora_estimada'] as String?) ?? '',
      monto: (r['monto'] as num?)?.toDouble() ?? 0,
      formaPago: (r['forma_pago'] as String?) ?? '',
      pagoEstado: (r['pago_estado'] as String?) ?? 'Pendiente',
      chkLlego: ((r['chk_llego'] as int?) ?? 0) == 1,
      chkMaterialInstalado: ((r['chk_material_instalado'] as int?) ?? 0) == 1,
      chkSistemaProbado: ((r['chk_sistema_probado'] as int?) ?? 0) == 1,
      chkClienteCapacitado: ((r['chk_cliente_capacitado'] as int?) ?? 0) == 1,
      chkTrabajoTerminado: ((r['chk_trabajo_terminado'] as int?) ?? 0) == 1,
      garantiaTipo: (r['garantia_tipo'] as String?) ?? '',
      garantiaVenceEn: r['garantia_vence_en'] as int?,
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.op});

  final _OperacionFull op;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      op.tipoServicio,
      if (op.hasTecnico) 'Técnico: ${op.tecnicoNombre}',
    ].join(' • ');

    return FullTechCard(
      icon: Icons.manage_accounts_outlined,
      title: op.codigo,
      subtitle: subtitle.isEmpty ? '—' : subtitle,
      trailing: op.prioridad,
      badge: op.estado,
      onTap: null,
    );
  }
}

class _GeneralInfo extends StatelessWidget {
  const _GeneralInfo({required this.op, required this.onEdit});

  final _OperacionFull op;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final date = op.programadoEn == null
        ? '—'
        : _fmtDate(DateTime.fromMillisecondsSinceEpoch(op.programadoEn!));

    final money = op.monto <= 0 ? '—' : 'RD\$ ${op.monto.toStringAsFixed(2)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow('Cliente', op.clienteNombre),
        _InfoRow(
            'Teléfono', op.clienteTelefono.isEmpty ? '—' : op.clienteTelefono),
        _InfoRow('Dirección',
            op.direccionServicio.isEmpty ? '—' : op.direccionServicio),
        _InfoRow('Referencia',
            op.referenciaLugar.isEmpty ? '—' : op.referenciaLugar),
        _InfoRow('Fecha', date),
        _InfoRow(
            'Hora estimada', op.horaEstimada.isEmpty ? '—' : op.horaEstimada),
        _InfoRow('Pago',
            '${op.pagoEstado} • ${op.formaPago.isEmpty ? '—' : op.formaPago}'),
        _InfoRow('Monto', money),
        const SizedBox(height: 10),
        if (onEdit != null)
          FilledButton.tonalIcon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Actualizar'),
          ),
      ],
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist(
      {required this.op, required this.enabled, required this.onChanged});

  final _OperacionFull op;
  final bool enabled;
  final void Function(String field, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CheckboxListTile(
          value: op.chkLlego,
          onChanged: enabled ? (v) => onChanged('chk_llego', v ?? false) : null,
          title: const Text('Llegó al lugar'),
        ),
        CheckboxListTile(
          value: op.chkMaterialInstalado,
          onChanged: enabled
              ? (v) => onChanged('chk_material_instalado', v ?? false)
              : null,
          title: const Text('Material instalado'),
        ),
        CheckboxListTile(
          value: op.chkSistemaProbado,
          onChanged: enabled
              ? (v) => onChanged('chk_sistema_probado', v ?? false)
              : null,
          title: const Text('Sistema probado'),
        ),
        CheckboxListTile(
          value: op.chkClienteCapacitado,
          onChanged: enabled
              ? (v) => onChanged('chk_cliente_capacitado', v ?? false)
              : null,
          title: const Text('Cliente capacitado'),
        ),
        CheckboxListTile(
          value: op.chkTrabajoTerminado,
          onChanged: enabled
              ? (v) => onChanged('chk_trabajo_terminado', v ?? false)
              : null,
          title: const Text('Trabajo terminado'),
        ),
      ],
    );
  }
}

class _Evidencias extends StatelessWidget {
  const _Evidencias({
    required this.tipo,
    required this.enabled,
    required this.onTipoChanged,
    required this.onAdd,
    required this.itemsFuture,
  });

  final String tipo;
  final bool enabled;
  final ValueChanged<String> onTipoChanged;
  final VoidCallback onAdd;
  final Future<List<Map<String, Object?>>> itemsFuture;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: kEvidenciaTipos
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(growable: false),
                onChanged: (v) => onTipoChanged(v ?? tipo),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Subir'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, Object?>>>(
          future: itemsFuture,
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, Object?>>[];
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator()));
            }
            if (rows.isEmpty) {
              return const Text('—', style: TextStyle(color: Colors.black54));
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final cross = constraints.maxWidth >= 800
                    ? 5
                    : constraints.maxWidth >= 520
                        ? 4
                        : 3;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final path = (r['file_path'] as String?)?.trim() ?? '';
                    final url = (r['file_url'] as String?)?.trim() ?? '';
                    final source = url.isNotEmpty ? url : path;
                    return _Thumb(source: source);
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    if (source.trim().isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    }

    final isRemote = source.startsWith('http://') || source.startsWith('https://');
    final file = isRemote ? null : File(source);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: isRemote
          ? Image.network(source, fit: BoxFit.cover)
          : (file != null && file.existsSync())
              ? Image.file(file, fit: BoxFit.cover)
          : Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
    );
  }
}

class _NotasSection extends StatelessWidget {
  const _NotasSection(
      {required this.operacionId, required this.enabled, required this.onAdd});

  final int operacionId;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: enabled ? onAdd : null,
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('Agregar nota'),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, Object?>>>(
          future: AppDatabase.instance.db.query(
            'operacion_notas',
            where: 'operacion_id = ?',
            whereArgs: [operacionId],
            orderBy: 'creado_en DESC',
          ),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, Object?>>[];
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (rows.isEmpty) {
              return const Text('—', style: TextStyle(color: Colors.black54));
            }
            return Column(
              children: rows
                  .map(
                    (r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.note_outlined),
                      title: Text((r['nota'] as String?) ?? ''),
                      subtitle: Text(_fmtDateTime(
                          DateTime.fromMillisecondsSinceEpoch(
                              (r['creado_en'] as int?) ?? 0))),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _MaterialesSection extends StatelessWidget {
  const _MaterialesSection({required this.operacionId, required this.enabled});

  final int operacionId;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: enabled
              ? () async {
                  final controller = TextEditingController();
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Agregar material'),
                      content: TextField(
                        controller: controller,
                        decoration:
                            const InputDecoration(labelText: 'Material'),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Agregar')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  final now = DateTime.now().millisecondsSinceEpoch;
                  await AppDatabase.instance.insert('operacion_materiales', {
                    'operacion_id': operacionId,
                    'nombre': name,
                    'creado_en': now,
                  });
                }
              : null,
          icon: const Icon(Icons.add),
          label: const Text('Agregar material'),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, Object?>>>(
          future: AppDatabase.instance.db.query(
            'operacion_materiales',
            where: 'operacion_id = ?',
            whereArgs: [operacionId],
            orderBy: 'creado_en DESC',
          ),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, Object?>>[];
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (rows.isEmpty) {
              return const Text('—', style: TextStyle(color: Colors.black54));
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: rows.map((r) {
                final id = (r['id'] as int?) ?? 0;
                final nombre = (r['nombre'] as String?) ?? '';
                return InputChip(
                  label: Text(nombre),
                  onDeleted: enabled && id > 0
                      ? () => AppDatabase.instance
                          .delete('operacion_materiales', id: id)
                      : null,
                );
              }).toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _EstadosHistorial extends StatelessWidget {
  const _EstadosHistorial({required this.operacionId});

  final int operacionId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AppDatabase.instance.db.query(
        'operacion_estados_historial',
        where: 'operacion_id = ?',
        whereArgs: [operacionId],
        orderBy: 'creado_en DESC',
      ),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, Object?>>[];
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows.isEmpty) {
          return const Text('—', style: TextStyle(color: Colors.black54));
        }

        return Column(
          children: rows.map(
            (r) {
              final de = (r['de_estado'] as String?) ?? '—';
              final a = (r['a_estado'] as String?) ?? '—';
              final when = (r['creado_en'] as int?) ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timeline_outlined),
                title: Text('$de → $a'),
                subtitle: Text(
                    _fmtDateTime(DateTime.fromMillisecondsSinceEpoch(when))),
              );
            },
          ).toList(growable: false),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child:
                  Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 34),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _fmtDateTime(DateTime d) {
  return '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
