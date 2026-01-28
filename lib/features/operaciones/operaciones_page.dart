import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../ui/fulltech_widgets.dart';
import 'operacion_detail_page.dart';
import 'operacion_form_page.dart';
import 'operaciones_types.dart';

class OperacionesPage extends StatefulWidget {
  const OperacionesPage({super.key, this.initialClienteId});

  final int? initialClienteId;

  static Future<void> openAddForm(BuildContext context) async {
    final opId = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const OperacionCreatePage()),
    );
    if (opId == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OperacionDetailPage(operacionId: opId)),
    );
  }

  @override
  State<OperacionesPage> createState() => _OperacionesPageState();
}

class _OperacionesPageState extends State<OperacionesPage> {
  final _db = AppDatabase.instance;
  final _search = TextEditingController();

  String? _estado;
  int? _tecnicoUsuarioId;
  String? _tipoServicio;
  DateTimeRange? _range;

  int? _clienteId;

  @override
  void initState() {
    super.initState();
    _clienteId = widget.initialClienteId;
    _range = _todayRange();
  }

  static DateTimeRange _todayRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return DateTimeRange(start: start, end: end);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 950;

    return CenteredList(
      child: StreamBuilder<void>(
        stream: _db.changes,
        builder: (context, _) {
          return FutureBuilder<List<_OperacionRow>>(
            future: _queryOperaciones(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <_OperacionRow>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Control operativo',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Filters(
                      search: _search,
                      estado: _estado,
                      tipoServicio: _tipoServicio,
                      tecnicoUsuarioId: _tecnicoUsuarioId,
                      range: _range,
                      onChanged: (f) => setState(() {
                        _estado = f.estado;
                        _tipoServicio = f.tipoServicio;
                        _tecnicoUsuarioId = f.tecnicoUsuarioId;
                        _range = f.range;
                      }),
                      onClear: () => setState(() {
                        _search.clear();
                        _estado = null;
                        _tipoServicio = null;
                        _tecnicoUsuarioId = null;
                        _range = _todayRange();
                        _clienteId = widget.initialClienteId;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: rows.isEmpty
                          ? const _EmptyState(
                              title: 'Sin operaciones',
                              subtitle:
                                  'Registra servicios y da seguimiento de forma profesional.',
                            )
                          : wide
                              ? _OperacionesTable(rows: rows)
                              : _OperacionesCards(rows: rows),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<_OperacionRow>> _queryOperaciones() async {
    final where = <String>[];
    final args = <Object?>[];

    if (_clienteId != null) {
      where.add('o.cliente_id = ?');
      args.add(_clienteId);
    }

    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      where.add(
          '(LOWER(o.codigo) LIKE ? OR LOWER(c.nombre) LIKE ? OR LOWER(o.tipo_servicio) LIKE ?)');
      args.add('%$q%');
      args.add('%$q%');
      args.add('%$q%');
    }

    if (_estado != null && _estado!.isNotEmpty) {
      where.add('o.estado = ?');
      args.add(_estado);
    }
    if (_tipoServicio != null && _tipoServicio!.isNotEmpty) {
      where.add('o.tipo_servicio = ?');
      args.add(_tipoServicio);
    }
    if (_tecnicoUsuarioId != null) {
      where.add('o.tecnico_usuario_id = ?');
      args.add(_tecnicoUsuarioId);
    }
    if (_range != null) {
      where.add('o.creado_en BETWEEN ? AND ?');
      args.add(_range!.start.millisecondsSinceEpoch);
      args.add(_range!.end.millisecondsSinceEpoch);
    }

    final sql = '''
SELECT o.id, o.codigo, o.estado, o.prioridad, o.tipo_servicio, o.programado_en,
       c.nombre AS cliente_nombre,
       COALESCE(u.nombre, t.nombre, '—') AS tecnico_nombre
FROM operaciones o
LEFT JOIN clientes c ON c.id = o.cliente_id
  LEFT JOIN usuarios u ON u.id = o.tecnico_usuario_id
LEFT JOIN tecnicos t ON t.id = o.tecnico_id
${where.isEmpty ? '' : 'WHERE ' + where.join(' AND ')}
ORDER BY o.creado_en DESC
''';

    final rows = await _db.db.rawQuery(sql, args);
    return rows.map(_OperacionRow.fromRow).toList(growable: false);
  }
}

class _OperacionRow {
  _OperacionRow({
    required this.id,
    required this.codigo,
    required this.cliente,
    required this.tipoServicio,
    required this.estado,
    required this.tecnico,
    required this.prioridad,
    required this.programadoEn,
  });

  final int id;
  final String codigo;
  final String cliente;
  final String tipoServicio;
  final String estado;
  final String tecnico;
  final String prioridad;
  final int? programadoEn;

  static _OperacionRow fromRow(Map<String, Object?> r) {
    return _OperacionRow(
      id: (r['id'] as int?) ?? 0,
      codigo: (r['codigo'] as String?) ?? '—',
      cliente: (r['cliente_nombre'] as String?) ?? '—',
      tipoServicio: (r['tipo_servicio'] as String?) ?? '—',
      estado: (r['estado'] as String?) ?? 'Pendiente',
      tecnico: (r['tecnico_nombre'] as String?) ?? '—',
      prioridad: (r['prioridad'] as String?) ?? 'Normal',
      programadoEn: r['programado_en'] as int?,
    );
  }
}

class _OperacionesCards extends StatelessWidget {
  const _OperacionesCards({required this.rows});

  final List<_OperacionRow> rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final r = rows[i];
        final subtitle = [
          r.cliente,
          r.tipoServicio,
          if (r.tecnico.trim().isNotEmpty && r.tecnico != '—')
            'Técnico: ${r.tecnico}',
        ].join(' • ');

        return FullTechCard(
          icon: Icons.manage_accounts_outlined,
          title: r.codigo,
          subtitle: subtitle,
          trailing: r.prioridad,
          badge: r.estado,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => OperacionDetailPage(operacionId: r.id)),
          ),
        );
      },
    );
  }
}

class _OperacionesTable extends StatelessWidget {
  const _OperacionesTable({required this.rows});

  final List<_OperacionRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Código')),
            DataColumn(label: Text('Cliente')),
            DataColumn(label: Text('Servicio')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Técnico')),
            DataColumn(label: Text('Prioridad')),
          ],
          rows: rows
              .map(
                (r) => DataRow(
                  onSelectChanged: (_) => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => OperacionDetailPage(operacionId: r.id)),
                  ),
                  cells: [
                    DataCell(Text(r.codigo)),
                    DataCell(Text(r.cliente)),
                    DataCell(Text(r.tipoServicio)),
                    DataCell(Text(r.estado)),
                    DataCell(Text(r.tecnico)),
                    DataCell(Text(r.prioridad)),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _FiltersValue {
  const _FiltersValue(
      {required this.estado,
      required this.tipoServicio,
      required this.tecnicoUsuarioId,
      required this.range});

  final String? estado;
  final String? tipoServicio;
  final int? tecnicoUsuarioId;
  final DateTimeRange? range;
}

class _Filters extends StatefulWidget {
  const _Filters({
    required this.search,
    required this.estado,
    required this.tipoServicio,
    required this.tecnicoUsuarioId,
    required this.range,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController search;
  final String? estado;
  final String? tipoServicio;
  final int? tecnicoUsuarioId;
  final DateTimeRange? range;
  final ValueChanged<_FiltersValue> onChanged;
  final VoidCallback onClear;

  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  static DateTimeRange _normalizeRangeInclusive(DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final endDayStart =
        DateTime(range.end.year, range.end.month, range.end.day);
    final end = endDayStart
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return DateTimeRange(start: start, end: end);
  }

  static DateTimeRange _todayRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return DateTimeRange(start: start, end: end);
  }

  static bool _isTodayRange(DateTimeRange range) {
    final today = _todayRange();
    return range.start == today.start && range.end == today.end;
  }

  Future<void> _openFiltersSheet() async {
    String? estado = widget.estado;
    String? tipoServicio = widget.tipoServicio;
    int? tecnicoUsuarioId = widget.tecnicoUsuarioId;
    DateTimeRange? range = widget.range;

    final res = await showModalBottomSheet<_FiltersValue>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final rangeLabel = range == null
                ? 'Todas'
                : '${_fmt(range!.start)} → ${_fmt(range!.end)}';

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filtros',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: estado,
                        decoration: const InputDecoration(
                          labelText: 'Estado',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...kOperacionEstados.map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          ),
                        ],
                        onChanged: (v) => setModalState(() => estado = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: tipoServicio,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de servicio',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...kOperacionTiposServicio
                              .where((e) => e != 'Otro')
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e),
                                ),
                              ),
                        ],
                        onChanged: (v) => setModalState(() => tipoServicio = v),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<Map<String, Object?>>>(
                        future: AppDatabase.instance.db.query(
                          'usuarios',
                          where:
                              '(rol = ? COLLATE NOCASE OR rol = ? COLLATE NOCASE) AND bloqueado = 0',
                          whereArgs: ['Tecnico', 'Técnico'],
                          orderBy: 'nombre COLLATE NOCASE',
                        ),
                        builder: (context, snapshot) {
                          final tecnicos =
                              snapshot.data ?? const <Map<String, Object?>>[];
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final safeTecnicoId = (tecnicoUsuarioId != null &&
                                  tecnicos.any((t) =>
                                      (t['id'] as int?) == tecnicoUsuarioId))
                              ? tecnicoUsuarioId
                              : null;
                          if (safeTecnicoId != tecnicoUsuarioId) {
                            tecnicoUsuarioId = null;
                          }

                          return DropdownButtonFormField<int>(
                            value: safeTecnicoId,
                            decoration: const InputDecoration(
                              labelText: 'Técnico',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('Todos'),
                              ),
                              ...tecnicos.map(
                                (t) => DropdownMenuItem<int>(
                                  value: t['id'] as int,
                                  child: Text((t['nombre'] ?? '') as String),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setModalState(() => tecnicoUsuarioId = v),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(rangeLabel)),
                            TextButton.icon(
                              onPressed: () =>
                                  setModalState(() => range = _todayRange()),
                              icon: const Icon(Icons.today_outlined),
                              label: const Text('Hoy'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () =>
                                  setModalState(() => range = null),
                              icon: const Icon(Icons.all_inbox_outlined),
                              label: const Text('Todas'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () async {
                                final now = DateTime.now();
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(now.year - 1),
                                  lastDate: DateTime(now.year + 5),
                                );
                                if (picked == null) return;
                                setModalState(() {
                                  range = _normalizeRangeInclusive(picked);
                                });
                              },
                              icon: const Icon(Icons.date_range_outlined),
                              label: const Text('Rango…'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setModalState(() {
                                estado = null;
                                tipoServicio = null;
                                tecnicoUsuarioId = null;
                                range = _todayRange();
                              }),
                              icon: const Icon(Icons.restart_alt_outlined),
                              label: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(
                                context,
                                _FiltersValue(
                                  estado: estado,
                                  tipoServicio: tipoServicio,
                                  tecnicoUsuarioId: tecnicoUsuarioId,
                                  range: range,
                                ),
                              ),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Aplicar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || res == null) return;
    widget.onChanged(res);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;

        if (compact) {
          final activeFilters = <bool>[
            widget.estado != null,
            widget.tipoServicio != null,
            widget.tecnicoUsuarioId != null,
            widget.range != null && !_isTodayRange(widget.range!),
          ].where((v) => v).length;

          final filtersButton = IconButton.filledTonal(
            tooltip: 'Filtros',
            onPressed: _openFiltersSheet,
            icon: const Icon(Icons.tune_outlined),
            visualDensity: VisualDensity.compact,
          );

          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.search,
                      onChanged: (_) => widget.onChanged(
                        _FiltersValue(
                          estado: widget.estado,
                          tipoServicio: widget.tipoServicio,
                          tecnicoUsuarioId: widget.tecnicoUsuarioId,
                          range: widget.range,
                        ),
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Buscar',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  activeFilters > 0
                      ? Badge(
                          label: Text(activeFilters.toString()),
                          child: filtersButton,
                        )
                      : filtersButton,
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Limpiar filtros',
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          );
        }

        // Layout "normal" (tablets/escritorio)
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: widget.search,
                  onChanged: (_) => widget.onChanged(
                    _FiltersValue(
                      estado: widget.estado,
                      tipoServicio: widget.tipoServicio,
                      tecnicoUsuarioId: widget.tecnicoUsuarioId,
                      range: widget.range,
                    ),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Buscar',
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Código, cliente o servicio…',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: widget.estado,
                        decoration: const InputDecoration(labelText: 'Estado'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...kOperacionEstados.map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          ),
                        ],
                        onChanged: (v) => widget.onChanged(
                          _FiltersValue(
                            estado: v,
                            tipoServicio: widget.tipoServicio,
                            tecnicoUsuarioId: widget.tecnicoUsuarioId,
                            range: widget.range,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: widget.tipoServicio,
                        decoration: const InputDecoration(
                            labelText: 'Tipo de servicio'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...kOperacionTiposServicio
                              .where((e) => e != 'Otro')
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e))),
                        ],
                        onChanged: (v) => widget.onChanged(
                          _FiltersValue(
                            estado: widget.estado,
                            tipoServicio: v,
                            tecnicoUsuarioId: widget.tecnicoUsuarioId,
                            range: widget.range,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<List<Map<String, Object?>>>(
                        future: AppDatabase.instance.db.query(
                          'usuarios',
                          where:
                              '(rol = ? COLLATE NOCASE OR rol = ? COLLATE NOCASE) AND bloqueado = 0',
                          whereArgs: ['Tecnico', 'Técnico'],
                          orderBy: 'nombre COLLATE NOCASE',
                        ),
                        builder: (context, snapshot) {
                          final tecnicos =
                              snapshot.data ?? const <Map<String, Object?>>[];
                          final safeTecnicoId =
                              (widget.tecnicoUsuarioId != null &&
                                      tecnicos.any((t) =>
                                          (t['id'] as int?) ==
                                          widget.tecnicoUsuarioId))
                                  ? widget.tecnicoUsuarioId
                                  : null;
                          return DropdownButtonFormField<int>(
                            value: safeTecnicoId,
                            decoration:
                                const InputDecoration(labelText: 'Técnico'),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('Todos'),
                              ),
                              ...tecnicos.map(
                                (t) => DropdownMenuItem<int>(
                                  value: t['id'] as int,
                                  child: Text((t['nombre'] ?? '') as String),
                                ),
                              ),
                            ],
                            onChanged: (v) => widget.onChanged(
                              _FiltersValue(
                                estado: widget.estado,
                                tipoServicio: widget.tipoServicio,
                                tecnicoUsuarioId: v,
                                range: widget.range,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 5),
                          );
                          widget.onChanged(
                            _FiltersValue(
                              estado: widget.estado,
                              tipoServicio: widget.tipoServicio,
                              tecnicoUsuarioId: widget.tecnicoUsuarioId,
                              range: picked == null
                                  ? widget.range
                                  : _normalizeRangeInclusive(picked),
                            ),
                          );
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Fecha',
                            prefixIcon: Icon(Icons.date_range_outlined),
                          ),
                          child: Text(
                            widget.range == null
                                ? 'Todas'
                                : '${_fmt(widget.range!.start)} → ${_fmt(widget.range!.end)}',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: widget.onClear,
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('Limpiar filtros'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
