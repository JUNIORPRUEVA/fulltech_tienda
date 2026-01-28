import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../ui/fulltech_widgets.dart';

class PonchePage extends StatefulWidget {
  const PonchePage({super.key});

  static Future<void> openAddForm(BuildContext context) {
    return showFullTechFormSheet<void>(
      context: context,
      child: const _PoncheQuickSheet(),
    );
  }

  @override
  State<PonchePage> createState() => _PonchePageState();
}

class _PonchePageState extends State<PonchePage> {
  DateTimeRange? _range;
  String? _tipoFilter;

  DateTimeRange _effectiveSummaryRange() {
    final now = DateTime.now();
    final r = _range;
    if (r != null) return r;
    final start = DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: start, end: now);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _range ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
    );
    if (picked == null) return;
    setState(() => _range = picked);
  }

  void _quickRange(Duration duration) {
    final now = DateTime.now();
    setState(() {
      _range = DateTimeRange(start: now.subtract(duration), end: now);
    });
  }

  void _clearFilters() {
    setState(() {
      _range = null;
      _tipoFilter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) {
      return const Center(child: Text('Sesión no válida. Vuelve a iniciar sesión.'));
    }

    return CenteredList(
      child: StreamBuilder<void>(
        stream: AppDatabase.instance.changes,
        builder: (context, _) {
          return FutureBuilder<_PoncheData>(
            future: _loadData(userId),
            builder: (context, snapshot) {
              final data = snapshot.data;
              final rows = data?.rows ?? const <Map<String, Object?>>[];
              final summary = data?.summary;
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: _FiltersBar(
                      range: _range,
                      tipoFilter: _tipoFilter,
                      onPickRange: _pickRange,
                      onTipoChanged: (v) => setState(() => _tipoFilter = v),
                      onClear: _clearFilters,
                      onQuickHoy: () => _quickRange(const Duration(days: 0)),
                      onQuick7: () => _quickRange(const Duration(days: 7)),
                      onQuick30: () => _quickRange(const Duration(days: 30)),
                    ),
                  ),
                  if (summary != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _SummaryCard(summary: summary),
                    ),
                  Expanded(
                    child: rows.isEmpty
                        ? const _EmptyState(
                            title: 'Sin registros',
                            subtitle:
                                'Aquí verás tus ponches de entrada, salida, almuerzo y permisos.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final r = rows[i];
                              final rawTipo = (r['tipo'] as String?) ?? 'Entrada';
                              final tipo = _normalizeTipo(rawTipo);
                              final horaMs = (r['hora'] as int?) ?? 0;
                              final dt = DateTime.fromMillisecondsSinceEpoch(horaMs);
                              final time = TimeOfDay.fromDateTime(dt);
                              final formatted =
                                  '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}  ${time.format(context)}';
                              final ubicacion = (r['ubicacion'] as String?)?.trim();

                              final meta = _tipoMeta(tipo);

                              return FullTechCard(
                                icon: meta.icon,
                                title: meta.label,
                                subtitle: (ubicacion == null || ubicacion.isEmpty)
                                    ? meta.subtitle
                                    : ubicacion,
                                trailing: formatted,
                                badge: meta.badge,
                                onTap: () => _openActions(context, r),
                              );
                            },
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

  Future<_PoncheData> _loadData(int userId) async {
    final user = await AuthService.instance.currentUser();
    final isAdmin = AuthService.isAdminRole(user?['rol'] as String?);
    final rows = await _queryPonches(userId, isAdmin: isAdmin);
    final summary = isAdmin ? null : await _computeSummary(userId);
    return _PoncheData(rows: rows, summary: summary);
  }

  Future<List<Map<String, Object?>>> _queryPonches(
    int userId, {
    required bool isAdmin,
  }) async {
    final where = <String>[];
    final args = <Object?>[];

    if (!isAdmin) {
      where.add('p.usuario_id = ?');
      args.add(userId);
    }

    final r = _range;
    if (r != null) {
      final start = DateTime(r.start.year, r.start.month, r.start.day);
      final end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59, 999);
      where.add('p.hora BETWEEN ? AND ?');
      args.addAll([start.millisecondsSinceEpoch, end.millisecondsSinceEpoch]);
    }

    final tipo = _tipoFilter;
    if (tipo != null && tipo.isNotEmpty) {
      where.add('p.tipo = ?');
      args.add(tipo);
    }

    return AppDatabase.instance.db.rawQuery(
      '''
SELECT p.*, u.nombre AS usuario_nombre
FROM ponches p
LEFT JOIN usuarios u ON u.id = p.usuario_id
${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
ORDER BY p.hora DESC
''',
      args,
    );
  }

  Future<_PoncheSummary> _computeSummary(int userId) async {
    final r = _effectiveSummaryRange();
    final start = DateTime(r.start.year, r.start.month, r.start.day);
    final end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59, 999);

    final rows = await AppDatabase.instance.db.query(
      'ponches',
      where: 'usuario_id = ? AND hora BETWEEN ? AND ?',
      whereArgs: [
        userId,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'hora ASC',
    );

    Duration labor = Duration.zero;
    Duration almuerzo = Duration.zero;
    Duration permiso = Duration.zero;

    DateTime? laborStart;
    DateTime? almuerzoStart;
    DateTime? permisoStart;

    for (final r in rows) {
      final tipo = _normalizeTipo((r['tipo'] as String?) ?? '');
      final horaMs = (r['hora'] as int?) ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(horaMs);

      if (tipo == PoncheTipo.laborEntrada) {
        laborStart = dt;
      } else if (tipo == PoncheTipo.laborSalida) {
        if (laborStart != null && dt.isAfter(laborStart)) {
          labor += dt.difference(laborStart);
        }
        laborStart = null;
        // Cierra sub-flujos si quedaron abiertos.
        almuerzoStart = null;
        permisoStart = null;
      } else if (tipo == PoncheTipo.almuerzoSalida) {
        almuerzoStart = dt;
      } else if (tipo == PoncheTipo.almuerzoEntrada) {
        if (almuerzoStart != null && dt.isAfter(almuerzoStart)) {
          almuerzo += dt.difference(almuerzoStart);
        }
        almuerzoStart = null;
      } else if (tipo == PoncheTipo.permisoSalida) {
        permisoStart = dt;
      } else if (tipo == PoncheTipo.permisoEntrada) {
        if (permisoStart != null && dt.isAfter(permisoStart)) {
          permiso += dt.difference(permisoStart);
        }
        permisoStart = null;
      }
    }

    final abiertos = <String>[];
    if (laborStart != null) abiertos.add('Labor');
    if (almuerzoStart != null) abiertos.add('Almuerzo');
    if (permisoStart != null) abiertos.add('Permiso');

    return _PoncheSummary(
      range: r,
      totalRegistros: rows.length,
      labor: labor,
      almuerzo: almuerzo,
      permiso: permiso,
      abiertos: abiertos,
    );
  }

  Future<void> _openActions(BuildContext context, Map<String, Object?> row) {
    return showFullTechFormSheet<void>(
      context: context,
      child: _PoncheActionsSheet(row: row),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.range,
    required this.tipoFilter,
    required this.onPickRange,
    required this.onTipoChanged,
    required this.onClear,
    required this.onQuickHoy,
    required this.onQuick7,
    required this.onQuick30,
  });

  final DateTimeRange? range;
  final String? tipoFilter;
  final VoidCallback onPickRange;
  final ValueChanged<String?> onTipoChanged;
  final VoidCallback onClear;
  final VoidCallback onQuickHoy;
  final VoidCallback onQuick7;
  final VoidCallback onQuick30;

  @override
  Widget build(BuildContext context) {
    final hasFilters = range != null || (tipoFilter != null && tipoFilter!.isNotEmpty);

    final rangeText = range == null
        ? 'Rango: Todo'
        : 'Rango: ${_d(range!.start)} → ${_d(range!.end)}';

    final tipoText = (tipoFilter == null || tipoFilter!.isEmpty)
        ? 'Tipo: Todos'
        : 'Tipo: ${_tipoMeta(_normalizeTipo(tipoFilter!)).label}';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: onPickRange,
                icon: const Icon(Icons.date_range_outlined),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(rangeText, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String?>(
                tooltip: 'Filtrar por tipo',
                onSelected: onTipoChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem<String?>(value: null, child: Text('Todos')),
                  PopupMenuDivider(),
                  PopupMenuItem<String?>(value: PoncheTipo.laborEntrada, child: Text('Entrada (Laboral)')),
                  PopupMenuItem<String?>(value: PoncheTipo.laborSalida, child: Text('Salida (Laboral)')),
                  PopupMenuItem<String?>(value: PoncheTipo.almuerzoSalida, child: Text('Salida a almorzar')),
                  PopupMenuItem<String?>(value: PoncheTipo.almuerzoEntrada, child: Text('Entrada de almorzar')),
                  PopupMenuItem<String?>(value: PoncheTipo.permisoSalida, child: Text('Salida por permiso')),
                  PopupMenuItem<String?>(value: PoncheTipo.permisoEntrada, child: Text('Entrada de permiso')),
                ],
                child: FilledButton.tonalIcon(
                  onPressed: null,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(tipoText, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _QuickChip(label: 'Hoy', onTap: onQuickHoy),
              const SizedBox(width: 8),
              _QuickChip(label: '7 días', onTap: onQuick7),
              const SizedBox(width: 8),
              _QuickChip(label: '30 días', onTap: onQuick30),
              const SizedBox(width: 10),
              if (hasFilters)
                IconButton.filledTonal(
                  tooltip: 'Limpiar filtros',
                  onPressed: onClear,
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }
}

String _d(DateTime dt) {
  return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoncheFormSheet extends StatefulWidget {
  const _PoncheFormSheet();

  @override
  State<_PoncheFormSheet> createState() => _PoncheFormSheetState();
}

class _PoncheFormSheetState extends State<_PoncheFormSheet> {
  final _formKey = GlobalKey<FormState>();
  String _tipo = PoncheTipo.laborEntrada;

  bool _saving = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Sesión no válida. Vuelve a iniciar sesión.'),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FullTechSheetHeader(
            title: 'Nuevo ponche',
            subtitle: 'Entrada/Salida • Almuerzo • Permiso',
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TipoChoice(
                    selected: _tipo == PoncheTipo.laborEntrada,
                    label: 'Entrada',
                    icon: Icons.login,
                    onTap: () => setState(() => _tipo = PoncheTipo.laborEntrada),
                  ),
                  _TipoChoice(
                    selected: _tipo == PoncheTipo.laborSalida,
                    label: 'Salida',
                    icon: Icons.logout,
                    onTap: () => setState(() => _tipo = PoncheTipo.laborSalida),
                  ),
                  _TipoChoice(
                    selected: _tipo == PoncheTipo.almuerzoSalida,
                    label: 'Salir a almorzar',
                    icon: Icons.restaurant_outlined,
                    onTap: () => setState(() => _tipo = PoncheTipo.almuerzoSalida),
                  ),
                  _TipoChoice(
                    selected: _tipo == PoncheTipo.almuerzoEntrada,
                    label: 'Entrar de almorzar',
                    icon: Icons.restaurant,
                    onTap: () => setState(() => _tipo = PoncheTipo.almuerzoEntrada),
                  ),
                  _TipoChoice(
                    selected: _tipo == PoncheTipo.permisoSalida,
                    label: 'Salida permiso',
                    icon: Icons.directions_walk_outlined,
                    onTap: () => setState(() => _tipo = PoncheTipo.permisoSalida),
                  ),
                  _TipoChoice(
                    selected: _tipo == PoncheTipo.permisoEntrada,
                    label: 'Entrada permiso',
                    icon: Icons.directions_walk,
                    onTap: () => setState(() => _tipo = PoncheTipo.permisoEntrada),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    if (!(_formKey.currentState?.validate() ?? true)) return;
                    setState(() => _saving = true);
                    final err = await validateAndInsertPonche(userId: userId, tipo: _tipo);
                    if (context.mounted) {
                      if (err == null) {
                        Navigator.of(context).pop();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err)),
                        );
                      }
                    }
                    if (mounted) setState(() => _saving = false);
                  },
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Registrar ponche'),
          ),
        ],
      ),
    );
  }
}

class _PoncheQuickSheet extends StatefulWidget {
  const _PoncheQuickSheet();

  @override
  State<_PoncheQuickSheet> createState() => _PoncheQuickSheetState();
}

class _PoncheQuickSheetState extends State<_PoncheQuickSheet> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Sesión no válida. Vuelve a iniciar sesión.'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FullTechSheetHeader(
          title: 'Ponchar',
          subtitle: 'Rápido y sin ubicación',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _quickBtn(context, userId, PoncheTipo.laborEntrada, Icons.login, 'Entrada (Labor)'),
            _quickBtn(context, userId, PoncheTipo.laborSalida, Icons.logout, 'Salida (Labor)'),
            _quickBtn(context, userId, PoncheTipo.almuerzoSalida, Icons.restaurant_outlined, 'Salir a almorzar'),
            _quickBtn(context, userId, PoncheTipo.almuerzoEntrada, Icons.restaurant, 'Entrar de almorzar'),
            _quickBtn(context, userId, PoncheTipo.permisoSalida, Icons.directions_walk_outlined, 'Salida permiso'),
            _quickBtn(context, userId, PoncheTipo.permisoEntrada, Icons.directions_walk, 'Entrada permiso'),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Se registra la hora exacta automáticamente.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _quickBtn(BuildContext context, int userId, String tipo, IconData icon, String label) {
    return SizedBox(
      width: 210,
      child: FilledButton.tonalIcon(
        onPressed: _saving
            ? null
            : () async {
                setState(() => _saving = true);
                final err = await validateAndInsertPonche(userId: userId, tipo: tipo);
                if (context.mounted) {
                  if (err == null) {
                    Navigator.of(context).pop();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err)),
                    );
                  }
                }
                if (mounted) setState(() => _saving = false);
              },
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

Future<String?> validateAndInsertPonche({
  required int userId,
  required String tipo,
  String? ubicacion,
}) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  final todayRows = await AppDatabase.instance.db.query(
    'ponches',
    where: 'usuario_id = ? AND hora BETWEEN ? AND ?',
    whereArgs: [userId, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    orderBy: 'hora DESC',
  );

  String? lastOf(List<String> tipos) {
    for (final r in todayRows) {
      final t = _normalizeTipo((r['tipo'] as String?) ?? '');
      if (tipos.contains(t)) return t;
    }
    return null;
  }

  bool isOpen(String entrada, String salida) {
    final last = lastOf([entrada, salida]);
    return last == entrada;
  }

  final laborOpen = isOpen(PoncheTipo.laborEntrada, PoncheTipo.laborSalida);
  final almuerzoOpen = isOpen(PoncheTipo.almuerzoSalida, PoncheTipo.almuerzoEntrada);
  final permisoOpen = isOpen(PoncheTipo.permisoSalida, PoncheTipo.permisoEntrada);

  String? error;
  switch (tipo) {
    case PoncheTipo.laborEntrada:
      if (laborOpen) {
        error = 'Ya tienes una Entrada laboral sin Salida hoy.';
      }
      break;
    case PoncheTipo.laborSalida:
      if (!laborOpen) {
        error = 'Primero registra la Entrada laboral.';
      } else if (almuerzoOpen) {
        error = 'Cierra el Almuerzo antes de la Salida laboral.';
      } else if (permisoOpen) {
        error = 'Cierra el Permiso antes de la Salida laboral.';
      }
      break;
    case PoncheTipo.almuerzoSalida:
      if (!laborOpen) {
        error = 'Para salir a almorzar, primero registra Entrada laboral.';
      } else if (almuerzoOpen) {
        error = 'Ya hay un Almuerzo abierto (falta Entrada de almorzar).';
      } else if (permisoOpen) {
        error = 'Cierra el Permiso antes de salir a almorzar.';
      }
      break;
    case PoncheTipo.almuerzoEntrada:
      if (!almuerzoOpen) {
        error = 'Primero registra Salida a almorzar.';
      }
      break;
    case PoncheTipo.permisoSalida:
      if (!laborOpen) {
        error = 'Para salir por permiso, primero registra Entrada laboral.';
      } else if (permisoOpen) {
        error = 'Ya hay un Permiso abierto (falta Entrada de permiso).';
      } else if (almuerzoOpen) {
        error = 'Cierra el Almuerzo antes de salir por permiso.';
      }
      break;
    case PoncheTipo.permisoEntrada:
      if (!permisoOpen) {
        error = 'Primero registra Salida por permiso.';
      }
      break;
  }

  if (error != null) {
    return error;
  }

  final u = (ubicacion ?? '').trim();

  await AppDatabase.instance.insert('ponches', {
    'usuario_id': userId,
    'tipo': tipo,
    'hora': DateTime.now().millisecondsSinceEpoch,
    'ubicacion': u.isEmpty ? null : u,
  });
  return null;
}

class _TipoChoice extends StatelessWidget {
  const _TipoChoice({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (_) => onTap(),
    );
  }
}

class _PoncheActionsSheet extends StatelessWidget {
  const _PoncheActionsSheet({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final rawTipo = (row['tipo'] as String?) ?? 'Ponche';
    final tipo = _tipoMeta(_normalizeTipo(rawTipo)).label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FullTechSheetHeader(title: tipo, subtitle: 'Registro (no editable)'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () async {
            final userId = AuthService.instance.currentUserId;
            if (userId == null) return;
            final id = (row['id'] as int?) ?? 0;
            await AppDatabase.instance.db.delete(
              'ponches',
              where: 'id = ? AND usuario_id = ?',
              whereArgs: [id, userId],
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar'),
        ),
      ],
    );
  }
}

class PoncheTipo {
  static const laborEntrada = 'LABOR_ENTRADA';
  static const laborSalida = 'LABOR_SALIDA';
  static const almuerzoSalida = 'ALMUERZO_SALIDA';
  static const almuerzoEntrada = 'ALMUERZO_ENTRADA';
  static const permisoSalida = 'PERMISO_SALIDA';
  static const permisoEntrada = 'PERMISO_ENTRADA';
}

class _PoncheData {
  const _PoncheData({required this.rows, required this.summary});

  final List<Map<String, Object?>> rows;
  final _PoncheSummary? summary;
}

class _PoncheSummary {
  const _PoncheSummary({
    required this.range,
    required this.totalRegistros,
    required this.labor,
    required this.almuerzo,
    required this.permiso,
    required this.abiertos,
  });

  final DateTimeRange range;
  final int totalRegistros;
  final Duration labor;
  final Duration almuerzo;
  final Duration permiso;
  final List<String> abiertos;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final _PoncheSummary summary;

  @override
  Widget build(BuildContext context) {
    final openText = summary.abiertos.isEmpty ? '—' : summary.abiertos.join(', ');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Resumen ${_d(summary.range.start)} → ${_d(summary.range.end)}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(label: 'Labor', value: _fmt(summary.labor)),
                _MetricChip(label: 'Almuerzo', value: _fmt(summary.almuerzo)),
                _MetricChip(label: 'Permiso', value: _fmt(summary.permiso)),
                _MetricChip(label: 'Registros', value: '${summary.totalRegistros}'),
                _MetricChip(label: 'Abiertos', value: openText),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
    );
  }
}

String _fmt(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

String _normalizeTipo(String raw) {
  final t = raw.trim();
  if (t == 'Entrada') return PoncheTipo.laborEntrada;
  if (t == 'Salida') return PoncheTipo.laborSalida;
  return t;
}

({String label, String badge, String subtitle, IconData icon}) _tipoMeta(String tipo) {
  switch (tipo) {
    case PoncheTipo.laborEntrada:
      return (label: 'Entrada (Laboral)', badge: 'Labor', subtitle: 'Registro de entrada', icon: Icons.login);
    case PoncheTipo.laborSalida:
      return (label: 'Salida (Laboral)', badge: 'Labor', subtitle: 'Registro de salida', icon: Icons.logout);
    case PoncheTipo.almuerzoSalida:
      return (label: 'Salida a almorzar', badge: 'Almuerzo', subtitle: 'Salida a almuerzo', icon: Icons.restaurant_outlined);
    case PoncheTipo.almuerzoEntrada:
      return (label: 'Entrada de almorzar', badge: 'Almuerzo', subtitle: 'Entrada de almuerzo', icon: Icons.restaurant);
    case PoncheTipo.permisoSalida:
      return (label: 'Salida por permiso', badge: 'Permiso', subtitle: 'Salida autorizada', icon: Icons.directions_walk_outlined);
    case PoncheTipo.permisoEntrada:
      return (label: 'Entrada de permiso', badge: 'Permiso', subtitle: 'Regreso de permiso', icon: Icons.directions_walk);
    default:
      final lower = tipo.toLowerCase();
      return (
        label: tipo,
        badge: 'Ponche',
        subtitle: 'Registro',
        icon: lower.contains('sal') ? Icons.logout : Icons.login,
      );
  }
}
