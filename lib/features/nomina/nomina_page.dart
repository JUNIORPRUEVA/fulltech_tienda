import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../ui/fulltech_widgets.dart';
import '../../utils/quincena.dart';

class NominaPage extends StatefulWidget {
  const NominaPage({super.key});

  @override
  State<NominaPage> createState() => _NominaPageState();
}

class _NominaPageState extends State<NominaPage> {
  late int _year;
  late int _month;
  int _index = 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _index = quincenaFor(now).index;
  }

  QuincenaInfo get _q =>
      quincenaForMonth(year: _year, month: _month, index: _index);

  Future<_NominaData> _load() async {
    final me = await AuthService.instance.currentUser();
    final isAdmin = AuthService.isAdminRole(me?['rol'] as String?);
    if (!isAdmin) {
      return const _NominaData.notAllowed();
    }

    final q = _q;
    final startMs = q.start.millisecondsSinceEpoch;
    final endMs = q.endExclusive.millisecondsSinceEpoch;

    final users = await AppDatabase.instance.db.query(
      'usuarios',
      where: 'COALESCE(bloqueado, 0) = 0',
      orderBy: 'nombre COLLATE NOCASE',
    );

    final ventasSums = await AppDatabase.instance.db.rawQuery(
      '''
SELECT
  usuario_id,
  COALESCE(SUM(ganancia), 0) AS ganancia_sum,
  COALESCE(SUM(puntos), 0) AS puntos_sum
FROM ventas
WHERE usuario_id IS NOT NULL
  AND creado_en >= ?
  AND creado_en < ?
GROUP BY usuario_id
''',
      [startMs, endMs],
    );

    final ventasByUser = <int, ({double ganancia, double puntos})>{};
    for (final r in ventasSums) {
      final uid = (r['usuario_id'] as int?) ?? 0;
      if (uid <= 0) continue;
      ventasByUser[uid] = (
        ganancia: (r['ganancia_sum'] as num?)?.toDouble() ?? 0.0,
        puntos: (r['puntos_sum'] as num?)?.toDouble() ?? 0.0,
      );
    }

    final ajustesSums = await AppDatabase.instance.db.rawQuery(
      '''
SELECT
  usuario_id,
  COALESCE(SUM(monto), 0) AS ajustes_sum
FROM nomina_ajustes
WHERE periodo_inicio = ? AND periodo_fin = ?
GROUP BY usuario_id
''',
      [startMs, endMs],
    );

    final ajustesByUser = <int, double>{};
    for (final r in ajustesSums) {
      final uid = (r['usuario_id'] as int?) ?? 0;
      if (uid <= 0) continue;
      ajustesByUser[uid] = (r['ajustes_sum'] as num?)?.toDouble() ?? 0.0;
    }

    final pagosRows = await AppDatabase.instance.db.query(
      'beneficios_pagos',
      where: 'periodo_inicio = ? AND periodo_fin = ?',
      whereArgs: [startMs, endMs],
    );

    final pagosByUser = <int, Map<String, Object?>>{};
    for (final p in pagosRows) {
      final uid = (p['usuario_id'] as int?) ?? 0;
      if (uid <= 0) continue;
      pagosByUser[uid] = p;
    }

    final items = <_NominaItem>[];

    double totalSueldos = 0;
    double totalComisiones = 0;
    double totalAjustes = 0;
    double totalNeto = 0;

    for (final u in users) {
      final id = (u['id'] as int?) ?? 0;
      if (id <= 0) continue;

      final nombre = (u['nombre'] as String?)?.trim() ?? 'Usuario';
      final rol = (u['rol'] as String?)?.trim() ?? '—';
      final sueldo = (u['sueldo_quincenal'] as num?)?.toDouble() ?? 0.0;
      final meta = (u['meta_quincenal'] as num?)?.toDouble() ?? 0.0;

      final v = ventasByUser[id];
      final puntos = v?.puntos ?? 0.0;
      final ganancia = v?.ganancia ?? 0.0;

      final eligible = meta > 0 && puntos >= meta;
      final comision =
          eligible ? (puntos * 0.10).clamp(0.0, double.infinity) : 0.0;

      final ajustes = ajustesByUser[id] ?? 0.0;
      final neto = sueldo + comision + ajustes;

      final pago = pagosByUser[id];
      final pagado = pago != null;

      items.add(
        _NominaItem(
          usuarioId: id,
          nombre: nombre,
          rol: rol,
          sueldo: sueldo,
          meta: meta,
          puntos: puntos,
          ganancia: ganancia,
          comision: comision,
          eligible: eligible,
          ajustes: ajustes,
          neto: neto,
          pagado: pagado,
        ),
      );

      totalSueldos += sueldo;
      totalComisiones += comision;
      totalAjustes += ajustes;
      totalNeto += neto;
    }

    return _NominaData.allowed(
      quincena: q,
      items: items,
      totalSueldos: totalSueldos,
      totalComisiones: totalComisiones,
      totalAjustes: totalAjustes,
      totalNeto: totalNeto,
    );
  }

  Future<void> _marcarPagado(_NominaData data, _NominaItem item) async {
    final q = data.quincena!;
    final startMs = q.start.millisecondsSinceEpoch;
    final endMs = q.endExclusive.millisecondsSinceEpoch;

    await AppDatabase.instance.insert('beneficios_pagos', {
      'usuario_id': item.usuarioId,
      'periodo_inicio': startMs,
      'periodo_fin': endMs,
      'pago_en': q.payDate.millisecondsSinceEpoch,
      'sueldo_base': item.sueldo,
      'comision': item.comision,
      'ajustes': item.ajustes,
      'neto': item.neto,
      'estado': 'Pagado',
      'creado_en': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _reabrirPago(_NominaData data, _NominaItem item) async {
    final q = data.quincena!;
    final startMs = q.start.millisecondsSinceEpoch;
    final endMs = q.endExclusive.millisecondsSinceEpoch;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reabrir pago'),
        content: Text(
          'Se eliminará el registro de pago de ${item.nombre} para este período. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await AppDatabase.instance.deleteWhere(
      'beneficios_pagos',
      where: 'usuario_id = ? AND periodo_inicio = ? AND periodo_fin = ?',
      whereArgs: [item.usuarioId, startMs, endMs],
    );
  }

  Future<void> _reabrirPeriodo(_NominaData data) async {
    final q = data.quincena!;
    final startMs = q.start.millisecondsSinceEpoch;
    final endMs = q.endExclusive.millisecondsSinceEpoch;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reabrir período'),
        content: const Text(
          'Se eliminarán TODOS los pagos marcados en este período. ¿Continuar?\n\nLos ajustes y las ventas no se eliminan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await AppDatabase.instance.deleteWhere(
      'beneficios_pagos',
      where: 'periodo_inicio = ? AND periodo_fin = ?',
      whereArgs: [startMs, endMs],
    );
  }

  Future<void> _openDetalleSheet(_NominaData data, _NominaItem item) async {
    final q = data.quincena!;
    final startMs = q.start.millisecondsSinceEpoch;
    final endMs = q.endExclusive.millisecondsSinceEpoch;

    await showFullTechFormSheet<void>(
      context: context,
      child: _DetalleVentasSheet(
        usuarioId: item.usuarioId,
        usuarioNombre: item.nombre,
        sueldo: item.sueldo,
        meta: item.meta,
        periodoInicio: startMs,
        periodoFinExclusive: endMs,
      ),
    );
  }

  Future<void> _pagarTodo(_NominaData data) async {
    final unpaid = data.items.where((i) => !i.pagado).toList(growable: false);
    if (unpaid.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pagar nómina'),
        content: Text(
            'Se marcarán como pagados ${unpaid.length} usuarios. ¿Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pagar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    for (final u in unpaid) {
      try {
        await _marcarPagado(data, u);
      } catch (_) {
        // Evita que una fila bloquee el resto.
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nómina marcada como pagada.')),
    );
  }

  Future<void> _openAjustesSheet(_NominaData data, _NominaItem item) async {
    final q = data.quincena!;
    final startMs = q.start.millisecondsSinceEpoch;
    final endMs = q.endExclusive.millisecondsSinceEpoch;

    final yaPagado = item.pagado;

    await showFullTechFormSheet<void>(
      context: context,
      child: _AjustesSheet(
        usuarioId: item.usuarioId,
        usuarioNombre: item.nombre,
        periodoInicio: startMs,
        periodoFin: endMs,
        disabled: yaPagado,
      ),
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      final d = DateTime(_year, _month + delta, 1);
      _year = d.year;
      _month = d.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: StreamBuilder<void>(
        stream: AppDatabase.instance.changes,
        builder: (context, _) {
          return FutureBuilder<_NominaData>(
            future: _load(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data;
              if (data == null || !data.allowed) {
                return const _EmptyState(
                  title: 'Acceso restringido',
                  subtitle:
                      'La nómina solo puede ser vista por Administradores.',
                );
              }

              final q = data.quincena!;
              final pagadosCount = data.items.where((e) => e.pagado).length;
              final unpaidCount = data.items.length - pagadosCount;

              return ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Nómina',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Mes anterior',
                                onPressed: () => _changeMonth(-1),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text(
                                  '${_month.toString().padLeft(2, '0')}/$_year'),
                              IconButton(
                                tooltip: 'Mes siguiente',
                                onPressed: () => _changeMonth(1),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(
                                  value: 1, label: Text('1ra (pago 15)')),
                              ButtonSegment(
                                  value: 2, label: Text('2da (pago 30)')),
                            ],
                            selected: {_index},
                            onSelectionChanged: (s) =>
                                setState(() => _index = s.first),
                          ),
                          const SizedBox(height: 12),
                          _InfoLine(
                              label: 'Período',
                              value:
                                  '${q.label} • ${fmtDate(q.start)} → ${fmtDate(q.endExclusive.subtract(const Duration(days: 1)))}'),
                          _InfoLine(
                              label: 'Fecha de pago',
                              value: fmtDate(q.payDate)),
                          const Divider(height: 20),
                          _InfoLine(
                              label: 'Total sueldos',
                              value: _money(data.totalSueldos)),
                          _InfoLine(
                              label: 'Total comisiones',
                              value: _money(data.totalComisiones)),
                          _InfoLine(
                              label: 'Total ajustes',
                              value: _money(data.totalAjustes)),
                          const Divider(height: 20),
                          _InfoLine(
                              label: 'Total nómina',
                              value: _money(data.totalNeto),
                              bold: true),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: unpaidCount <= 0
                                ? null
                                : () => _pagarTodo(data),
                            icon: const Icon(Icons.payments_outlined),
                            label:
                                const Text('Marcar toda la nómina como pagada'),
                          ),
                          if (pagadosCount > 0) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => _reabrirPeriodo(data),
                              icon: const Icon(Icons.lock_open_outlined),
                              label: Text(
                                  'Reabrir período ($pagadosCount pagado)'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (data.items.isEmpty)
                    const _EmptyState(
                      title: 'Sin usuarios',
                      subtitle: 'Crea usuarios para poder generar nómina.',
                    )
                  else
                    ...data.items.map(
                      (u) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        u.nombre,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: u.pagado
                                            ? Colors.green.withAlpha(25)
                                            : Colors.orange.withAlpha(25),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        u.pagado ? 'PAGADO' : 'PENDIENTE',
                                        style: TextStyle(
                                          color: u.pagado
                                              ? Colors.green[800]
                                              : Colors.orange[800],
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(u.rol,
                                    style:
                                        const TextStyle(color: Colors.black54)),
                                const Divider(height: 20),
                                _InfoLine(
                                    label: 'Sueldo', value: _money(u.sueldo)),
                                _InfoLine(
                                  label: 'Comisión',
                                  value: u.meta <= 0
                                      ? '—'
                                      : u.eligible
                                          ? _money(u.comision)
                                          : 'Pendiente (meta)',
                                ),
                                _InfoLine(
                                    label: 'Ajustes', value: _money(u.ajustes)),
                                const Divider(height: 20),
                                _InfoLine(
                                    label: 'Neto',
                                    value: _money(u.neto),
                                    bold: true),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _openDetalleSheet(data, u),
                                      icon: const Icon(
                                          Icons.receipt_long_outlined),
                                      label: const Text('Detalle'),
                                    ),
                                    FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _openAjustesSheet(data, u),
                                      icon: const Icon(Icons.tune_outlined),
                                      label: const Text('Ajustes'),
                                    ),
                                    if (!u.pagado)
                                      FilledButton.icon(
                                        onPressed: () => _marcarPagado(data, u),
                                        icon: const Icon(
                                            Icons.check_circle_outline),
                                        label: const Text('Marcar pagado'),
                                      )
                                    else
                                      OutlinedButton.icon(
                                        onPressed: () => _reabrirPago(data, u),
                                        icon: const Icon(
                                            Icons.lock_open_outlined),
                                        label: const Text('Reabrir pago'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _NominaData {
  const _NominaData._({
    required this.allowed,
    required this.quincena,
    required this.items,
    required this.totalSueldos,
    required this.totalComisiones,
    required this.totalAjustes,
    required this.totalNeto,
  });

  const _NominaData.notAllowed()
      : this._(
          allowed: false,
          quincena: null,
          items: const [],
          totalSueldos: 0,
          totalComisiones: 0,
          totalAjustes: 0,
          totalNeto: 0,
        );

  factory _NominaData.allowed({
    required QuincenaInfo quincena,
    required List<_NominaItem> items,
    required double totalSueldos,
    required double totalComisiones,
    required double totalAjustes,
    required double totalNeto,
  }) {
    return _NominaData._(
      allowed: true,
      quincena: quincena,
      items: items,
      totalSueldos: totalSueldos,
      totalComisiones: totalComisiones,
      totalAjustes: totalAjustes,
      totalNeto: totalNeto,
    );
  }

  final bool allowed;
  final QuincenaInfo? quincena;
  final List<_NominaItem> items;
  final double totalSueldos;
  final double totalComisiones;
  final double totalAjustes;
  final double totalNeto;
}

class _NominaItem {
  const _NominaItem({
    required this.usuarioId,
    required this.nombre,
    required this.rol,
    required this.sueldo,
    required this.meta,
    required this.puntos,
    required this.ganancia,
    required this.comision,
    required this.eligible,
    required this.ajustes,
    required this.neto,
    required this.pagado,
  });

  final int usuarioId;
  final String nombre;
  final String rol;

  final double sueldo;
  final double meta;
  final double puntos;
  final double ganancia;

  final double comision;
  final bool eligible;
  final double ajustes;
  final double neto;
  final bool pagado;
}

class _AjustesSheet extends StatefulWidget {
  const _AjustesSheet({
    required this.usuarioId,
    required this.usuarioNombre,
    required this.periodoInicio,
    required this.periodoFin,
    required this.disabled,
  });

  final int usuarioId;
  final String usuarioNombre;
  final int periodoInicio;
  final int periodoFin;
  final bool disabled;

  @override
  State<_AjustesSheet> createState() => _AjustesSheetState();
}

class _AjustesSheetState extends State<_AjustesSheet> {
  final _monto = TextEditingController();
  final _nota = TextEditingController();

  String _tipo = 'Bono';
  bool _saving = false;

  @override
  void dispose() {
    _monto.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> _loadRows() {
    return AppDatabase.instance.db.query(
      'nomina_ajustes',
      where: 'usuario_id = ? AND periodo_inicio = ? AND periodo_fin = ?',
      whereArgs: [widget.usuarioId, widget.periodoInicio, widget.periodoFin],
      orderBy: 'creado_en DESC, id DESC',
    );
  }

  double _signedAmount(double raw) {
    if (_tipo == 'Bono') return raw.abs();
    if (_tipo == 'Descuento') return -raw.abs();
    if (_tipo == 'Falta') return -raw.abs();
    return raw;
  }

  Future<void> _add() async {
    final raw = double.tryParse(_monto.text.trim().replaceAll(',', '.'));
    if (raw == null || raw <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monto inválido.')),
      );
      return;
    }

    setState(() => _saving = true);

    await AppDatabase.instance.insert('nomina_ajustes', {
      'usuario_id': widget.usuarioId,
      'periodo_inicio': widget.periodoInicio,
      'periodo_fin': widget.periodoFin,
      'tipo': _tipo,
      'monto': _signedAmount(raw),
      'nota': _nota.text.trim(),
      'creado_en': DateTime.now().millisecondsSinceEpoch,
    });

    if (!mounted) return;
    setState(() {
      _saving = false;
      _monto.clear();
      _nota.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FullTechSheetHeader(
          title: 'Ajustes',
          subtitle: widget.usuarioNombre,
        ),
        const SizedBox(height: 12),
        if (widget.disabled)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Este usuario ya está marcado como pagado. Los ajustes están bloqueados para este período.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: _tipo,
                  items: const [
                    DropdownMenuItem(value: 'Bono', child: Text('Bono (+)')),
                    DropdownMenuItem(
                        value: 'Descuento', child: Text('Descuento (-)')),
                    DropdownMenuItem(
                        value: 'Falta', child: Text('Falta / ausencia (-)')),
                  ],
                  onChanged: widget.disabled
                      ? null
                      : (v) => setState(() => _tipo = v ?? _tipo),
                  decoration: const InputDecoration(labelText: 'Tipo'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _monto,
                  enabled: !widget.disabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Monto'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nota,
                  enabled: !widget.disabled,
                  decoration:
                      const InputDecoration(labelText: 'Nota (opcional)'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: widget.disabled || _saving ? null : _add,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                  label: const Text('Agregar ajuste'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, Object?>>>(
          future: _loadRows(),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, Object?>>[];
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator()));
            }
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Sin ajustes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54)),
              );
            }

            return Card(
              margin: EdgeInsets.zero,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final id = (r['id'] as int?) ?? 0;
                  final tipo = (r['tipo'] as String?) ?? '';
                  final nota = (r['nota'] as String?)?.trim() ?? '';
                  final monto = (r['monto'] as num?)?.toDouble() ?? 0.0;
                  final txt = nota.isEmpty ? tipo : '$tipo • $nota';

                  return ListTile(
                    title: Text(txt),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _money(monto),
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: monto < 0 ? Colors.red : null),
                        ),
                        if (!widget.disabled) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Eliminar',
                            onPressed: id <= 0
                                ? null
                                : () async {
                                    await AppDatabase.instance
                                        .delete('nomina_ajustes', id: id);
                                    if (context.mounted) setState(() {});
                                  },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DetalleVentasSheet extends StatelessWidget {
  const _DetalleVentasSheet({
    required this.usuarioId,
    required this.usuarioNombre,
    required this.sueldo,
    required this.meta,
    required this.periodoInicio,
    required this.periodoFinExclusive,
  });

  final int usuarioId;
  final String usuarioNombre;
  final double sueldo;
  final double meta;
  final int periodoInicio;
  final int periodoFinExclusive;

  Future<_DetalleVentasData> _load() async {
    final rows = await AppDatabase.instance.db.rawQuery(
      '''
SELECT
  v.id,
  v.codigo,
  v.total,
  v.ganancia,
  v.puntos,
  v.notas,
  v.creado_en,
  c.nombre AS cliente_nombre
FROM ventas v
LEFT JOIN clientes c ON c.id = v.cliente_id
WHERE v.usuario_id = ?
  AND v.creado_en >= ?
  AND v.creado_en < ?
ORDER BY v.creado_en DESC, v.id DESC
''',
      [usuarioId, periodoInicio, periodoFinExclusive],
    );

    double totalSum = 0;
    double gananciaSum = 0;
    double puntosSum = 0;

    for (final r in rows) {
      totalSum += (r['total'] as num?)?.toDouble() ?? 0.0;
      gananciaSum += (r['ganancia'] as num?)?.toDouble() ?? 0.0;
      puntosSum += (r['puntos'] as num?)?.toDouble() ?? 0.0;
    }

    final eligible = meta > 0 && puntosSum >= meta;
    final comision = eligible ? gananciaSum : 0.0;

    return _DetalleVentasData(
      ventas: rows,
      totalSum: totalSum,
      gananciaSum: gananciaSum,
      puntosSum: puntosSum,
      eligible: eligible,
      comision: comision,
    );
  }

  @override
  Widget build(BuildContext context) {
    final endInclusive =
        DateTime.fromMillisecondsSinceEpoch(periodoFinExclusive)
            .subtract(const Duration(days: 1));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FullTechSheetHeader(
          title: 'Detalle',
          subtitle: usuarioNombre,
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoLine(
                  label: 'Período',
                  value:
                      '${fmtDate(DateTime.fromMillisecondsSinceEpoch(periodoInicio))} → ${fmtDate(endInclusive)}',
                ),
                _InfoLine(label: 'Sueldo', value: _money(sueldo)),
                _InfoLine(
                  label: 'Meta',
                  value: meta <= 0 ? '—' : _qty(meta),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<_DetalleVentasData>(
          future: _load(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final data = snapshot.data;
            if (data == null) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No se pudo cargar el detalle.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InfoLine(
                          label: 'Ventas',
                          value: '${data.ventas.length}',
                        ),
                        _InfoLine(
                          label: 'Total ventas',
                          value: _money(data.totalSum),
                        ),
                        _InfoLine(
                          label: 'Ganancia',
                          value: _money(data.gananciaSum),
                        ),
                        _InfoLine(
                          label: 'Puntos',
                          value: _money(data.puntosSum),
                        ),
                        const Divider(height: 20),
                        _InfoLine(
                          label: 'Comisión',
                          value: meta <= 0
                              ? '—'
                              : data.eligible
                                  ? _money(data.comision)
                                  : 'Pendiente (meta)',
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (data.ventas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Sin ventas en este período.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: data.ventas.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = data.ventas[i];
                        final cliente =
                            (r['cliente_nombre'] as String?)?.trim() ?? '—';
                        final codigo = (r['codigo'] as String?)?.trim();
                        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
                        final ganancia =
                            (r['ganancia'] as num?)?.toDouble() ?? 0.0;
                        final puntos = (r['puntos'] as num?)?.toDouble() ?? 0.0;
                        final creadoEn = (r['creado_en'] as int?) ?? 0;

                        final title = codigo == null || codigo.isEmpty
                            ? cliente
                            : '$cliente • $codigo';
                        final subtitle =
                            '${_fmtDateTimeMs(creadoEn)} • G: ${_money(ganancia)} • P: ${_money(puntos)}';

                        return ListTile(
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _money(total),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DetalleVentasData {
  const _DetalleVentasData({
    required this.ventas,
    required this.totalSum,
    required this.gananciaSum,
    required this.puntosSum,
    required this.eligible,
    required this.comision,
  });

  final List<Map<String, Object?>> ventas;
  final double totalSum;
  final double gananciaSum;
  final double puntosSum;
  final bool eligible;
  final double comision;
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(
      {required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.w900)
        : const TextStyle(fontWeight: FontWeight.w800);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child:
                  Text(label, style: const TextStyle(color: Colors.black54))),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

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

String _money(double value) {
  final negative = value < 0;
  final v = value.abs();
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final decPart = parts.length > 1 ? parts[1] : '00';

  final b = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final remaining = intPart.length - i;
    b.write(intPart[i]);
    if (remaining > 1 && remaining % 3 == 1) b.write(',');
  }

  final out = '${b.toString()}.$decPart';
  return negative ? '-$out' : out;
}

String _qty(double value) {
  final isInt = value % 1 == 0;
  return value.toStringAsFixed(isInt ? 0 : 2);
}

String _fmtDateTimeMs(int ms) {
  if (ms <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}
