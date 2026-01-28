import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../ui/fulltech_widgets.dart';
import 'operaciones_types.dart';

class OperacionCreatePage extends StatefulWidget {
  const OperacionCreatePage({super.key});

  @override
  State<OperacionCreatePage> createState() => _OperacionCreatePageState();
}

class _OperacionCreatePageState extends State<OperacionCreatePage> {
  final _db = AppDatabase.instance;
  final _formKey = GlobalKey<FormState>();

  // Cliente
  int? _clienteId;
  bool _nuevoCliente = false;
  final _clienteNombre = TextEditingController();
  final _clienteTelefono = TextEditingController();
  final _clienteDireccion = TextEditingController();

  // Servicio
  String _tipoServicio = kOperacionTiposServicio.first;
  final _tipoServicioOtro = TextEditingController();
  final _descripcion = TextEditingController();
  final _observacionesIniciales = TextEditingController();

  // Materiales
  final List<String> _materiales = [];

  // Técnico
  int? _tecnicoUsuarioId;
  DateTime? _programado;
  final _horaEstimada = TextEditingController();

  // Operación
  String _estado = 'Pendiente';
  String _prioridad = 'Normal';
  final _direccionServicio = TextEditingController();
  final _referenciaLugar = TextEditingController();

  // Pago
  final _monto = TextEditingController();
  String _formaPago = kPagoFormas.first;
  String _pagoEstado = kPagoEstados.first;
  final _pagoAbono = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _clienteNombre.dispose();
    _clienteTelefono.dispose();
    _clienteDireccion.dispose();
    _tipoServicioOtro.dispose();
    _descripcion.dispose();
    _observacionesIniciales.dispose();
    _horaEstimada.dispose();
    _direccionServicio.dispose();
    _referenciaLugar.dispose();
    _monto.dispose();
    _pagoAbono.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva operación'),
      ),
      body: SafeArea(
        child: CenteredList(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionTitle('Cliente'),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, Object?>>>(
                  future: _db.queryAll('clientes',
                      orderBy: 'nombre COLLATE NOCASE'),
                  builder: (context, snapshot) {
                    final clientes =
                        snapshot.data ?? const <Map<String, Object?>>[];
                    return Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Nuevo cliente'),
                          value: _nuevoCliente,
                          onChanged: (v) => setState(() {
                            _nuevoCliente = v;
                            if (v) {
                              _clienteId = null;
                            }
                          }),
                        ),
                        if (!_nuevoCliente)
                          DropdownButtonFormField<int>(
                            value: _clienteId,
                            decoration: const InputDecoration(
                              labelText: 'Cliente',
                              prefixIcon: Icon(Icons.people_alt_outlined),
                            ),
                            validator: (v) => v == null ? 'Requerido' : null,
                            items: clientes
                                .map(
                                  (c) => DropdownMenuItem<int>(
                                    value: c['id'] as int,
                                    child: Text((c['nombre'] ?? '') as String),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (v) async {
                              setState(() => _clienteId = v);
                              if (v == null) return;
                              final row = await _db.findById('clientes', v);
                              if (row == null) return;
                              _clienteTelefono.text =
                                  (row['telefono'] as String?) ?? '';
                              _clienteDireccion.text =
                                  (row['direccion'] as String?) ?? '';
                              _direccionServicio.text = _clienteDireccion.text;
                              setState(() {});
                            },
                          ),
                        if (_nuevoCliente) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _clienteNombre,
                            decoration: const InputDecoration(
                                labelText: 'Nombre',
                                prefixIcon: Icon(Icons.person_outline)),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requerido'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _clienteTelefono,
                            decoration: const InputDecoration(
                                labelText: 'Teléfono',
                                prefixIcon: Icon(Icons.phone_outlined)),
                            keyboardType: TextInputType.phone,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requerido'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _clienteDireccion,
                            decoration: const InputDecoration(
                                labelText: 'Dirección',
                                prefixIcon: Icon(Icons.location_on_outlined)),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requerido'
                                : null,
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _direccionServicio,
                  decoration: const InputDecoration(
                      labelText: 'Dirección del servicio',
                      prefixIcon: Icon(Icons.home_work_outlined)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _referenciaLugar,
                  decoration: const InputDecoration(
                      labelText: 'Referencia del lugar',
                      prefixIcon: Icon(Icons.place_outlined)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
                const _SectionTitle('Servicio'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _tipoServicio,
                  decoration: const InputDecoration(
                      labelText: 'Tipo de servicio',
                      prefixIcon: Icon(Icons.build_outlined)),
                  items: kOperacionTiposServicio
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(growable: false),
                  onChanged: (v) =>
                      setState(() => _tipoServicio = v ?? _tipoServicio),
                ),
                if (_tipoServicio == 'Otro') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tipoServicioOtro,
                    decoration: const InputDecoration(
                        labelText: 'Especificar',
                        prefixIcon: Icon(Icons.edit_outlined)),
                    validator: (v) {
                      if (_tipoServicio != 'Otro') return null;
                      return (v == null || v.trim().isEmpty)
                          ? 'Requerido'
                          : null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descripcion,
                  decoration: const InputDecoration(
                      labelText: 'Descripción del trabajo',
                      prefixIcon: Icon(Icons.description_outlined)),
                  maxLines: 3,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observacionesIniciales,
                  decoration: const InputDecoration(
                      labelText: 'Observaciones iniciales',
                      prefixIcon: Icon(Icons.notes_outlined)),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _MaterialesEditor(
                  materiales: _materiales,
                  onAdd: _addMaterial,
                  onRemove: (m) => setState(() => _materiales.remove(m)),
                ),
                const SizedBox(height: 18),
                const _SectionTitle('Asignación'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _prioridad,
                        decoration: const InputDecoration(
                            labelText: 'Prioridad',
                            prefixIcon: Icon(Icons.priority_high_outlined)),
                        items: kOperacionPrioridades
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e)))
                            .toList(growable: false),
                        onChanged: (v) =>
                            setState(() => _prioridad = v ?? _prioridad),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _estado,
                        decoration: const InputDecoration(
                            labelText: 'Estado',
                            prefixIcon: Icon(Icons.flag_outlined)),
                        items: kOperacionEstados
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e)))
                            .toList(growable: false),
                        onChanged: (v) =>
                            setState(() => _estado = v ?? _estado),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                      value: _tecnicoUsuarioId,
                      decoration: const InputDecoration(
                        labelText: 'Técnico asignado',
                        prefixIcon: Icon(Icons.engineering_outlined),
                      ),
                      validator: (v) => v == null ? 'Requerido' : null,
                      items: tecnicos
                          .map(
                            (t) => DropdownMenuItem<int>(
                              value: t['id'] as int,
                              child: Text((t['nombre'] ?? '') as String),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) => setState(() => _tecnicoUsuarioId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Fecha programada',
                        value: _programado,
                        onPick: _pickProgramado,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _horaEstimada,
                        decoration: const InputDecoration(
                            labelText: 'Hora estimada',
                            prefixIcon: Icon(Icons.schedule_outlined),
                            hintText: 'Ej: 2:30 PM'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _SectionTitle('Pago'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _monto,
                  decoration: const InputDecoration(
                      labelText: 'Monto del servicio',
                      prefixIcon: Icon(Icons.payments_outlined)),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final d = double.tryParse((v ?? '').trim()) ?? 0.0;
                    return d <= 0 ? 'Requerido' : null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _formaPago,
                        decoration:
                            const InputDecoration(labelText: 'Forma de pago'),
                        items: kPagoFormas
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e)))
                            .toList(growable: false),
                        onChanged: (v) =>
                            setState(() => _formaPago = v ?? _formaPago),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _pagoEstado,
                        decoration:
                            const InputDecoration(labelText: 'Estado de pago'),
                        items: kPagoEstados
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e)))
                            .toList(growable: false),
                        onChanged: (v) =>
                            setState(() => _pagoEstado = v ?? _pagoEstado),
                      ),
                    ),
                  ],
                ),
                if (_pagoEstado == 'Abono') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pagoAbono,
                    decoration:
                        const InputDecoration(labelText: 'Monto abonado'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar operación'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickProgramado() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _programado ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(
        () => _programado = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _addMaterial() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar material'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Material requerido'),
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
    final v = controller.text.trim();
    if (v.isEmpty) return;
    setState(() => _materiales.add(v));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_nuevoCliente && _clienteId == null) return;

    setState(() => _saving = true);

    final now = DateTime.now().millisecondsSinceEpoch;

    int? clienteId = _clienteId;
    if (_nuevoCliente) {
      clienteId = await _db.insert('clientes', {
        'nombre': _clienteNombre.text.trim(),
        'telefono': _clienteTelefono.text.trim(),
        'email': null,
        'direccion': _clienteDireccion.text.trim(),
        'creado_en': now,
      });
    }

    final codigo = _newCodigo();
    final tipoServicio =
        _tipoServicio == 'Otro' ? _tipoServicioOtro.text.trim() : _tipoServicio;

    final monto = double.tryParse(_monto.text.trim()) ?? 0.0;
    final abono = double.tryParse(_pagoAbono.text.trim()) ?? 0.0;

    final opId = await _db.insert('operaciones', {
      'cliente_id': clienteId,
      'codigo': codigo,
      'titulo': null,
      'tipo_servicio': tipoServicio,
      'prioridad': _prioridad,
      'estado': _estado,
      'tecnico_id': null,
      'tecnico_usuario_id': _tecnicoUsuarioId,
      'programado_en': _programado?.millisecondsSinceEpoch,
      'hora_estimada': _horaEstimada.text.trim(),
      'direccion_servicio': _direccionServicio.text.trim(),
      'referencia_lugar': _referenciaLugar.text.trim(),
      'descripcion': _descripcion.text.trim(),
      'observaciones_iniciales': _observacionesIniciales.text.trim(),
      'observaciones_finales': null,
      'monto': monto,
      'forma_pago': _formaPago,
      'pago_estado': _pagoEstado,
      'pago_abono': _pagoEstado == 'Abono' ? abono : null,
      'chk_llego': 0,
      'chk_material_instalado': 0,
      'chk_sistema_probado': 0,
      'chk_cliente_capacitado': 0,
      'chk_trabajo_terminado': 0,
      'garantia_tipo': null,
      'garantia_vence_en': null,
      'actualizado_en': now,
      'finalizado_en': null,
      'creado_en': now,
    });

    for (final m in _materiales) {
      await _db.insert('operacion_materiales', {
        'operacion_id': opId,
        'nombre': m,
        'creado_en': now,
      });
    }

    final userId = AuthService.instance.currentUserId;
    await _db.insert('operacion_estados_historial', {
      'operacion_id': opId,
      'de_estado': null,
      'a_estado': _estado,
      'usuario_id': userId,
      'creado_en': now,
    });

    if (!mounted) return;
    Navigator.of(context).pop(opId);
  }

  String _newCodigo() {
    final d = DateTime.now();
    final date =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';
    final rnd = Random().nextInt(9000) + 1000;
    return 'OP-$date-$time-$rnd';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14));
  }
}

class _DateField extends StatelessWidget {
  const _DateField(
      {required this.label, required this.value, required this.onPick});

  final String label;
  final DateTime? value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '—'
        : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.date_range_outlined),
        ),
        child: Text(text),
      ),
    );
  }
}

class _MaterialesEditor extends StatelessWidget {
  const _MaterialesEditor(
      {required this.materiales, required this.onAdd, required this.onRemove});

  final List<String> materiales;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Materiales requeridos',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (materiales.isEmpty)
              const Text('—', style: TextStyle(color: Colors.black54))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: materiales
                    .map(
                      (m) => InputChip(
                        label: Text(m),
                        onDeleted: () => onRemove(m),
                      ),
                    )
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }
}
