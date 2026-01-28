import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../ui/fulltech_widgets.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  static Future<void> openAddForm(BuildContext context) {
    return showFullTechFormSheet<void>(
      context: context,
      child: const _ClienteFormSheet(),
    );
  }

  static Future<void> openEditForm(
    BuildContext context, {
    required Map<String, Object?> row,
  }) {
    return showFullTechFormSheet<void>(
      context: context,
      child: _ClienteFormSheet(existing: row),
    );
  }

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _search = TextEditingController();
  String _filter = 'Todos';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: StreamBuilder<void>(
        stream: AppDatabase.instance.changes,
        builder: (context, _) {
          return FutureBuilder(
            future: AppDatabase.instance
                .queryAll('clientes', orderBy: 'creado_en DESC'),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <Map<String, Object?>>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              final query = _search.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? rows
                  : rows.where((r) {
                      final nombre = (r['nombre'] as String?) ?? '';
                      final telefono = (r['telefono'] as String?) ?? '';
                      final email = (r['email'] as String?) ?? '';
                      final direccion = (r['direccion'] as String?) ?? '';
                      final haystack =
                          '$nombre $telefono $email $direccion'.toLowerCase();
                      return haystack.contains(query);
                    }).toList(growable: false);

                final filteredByFilter = _applyFilter(filtered);

              if (rows.isEmpty) {
                return const _EmptyState(
                  title: 'Sin clientes',
                  subtitle:
                      'Usa el botón Agregar para crear tu primer cliente.',
                );
              }

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Buscar',
                              hintText: 'Nombre o teléfono',
                              prefixIcon: Icon(Icons.search),
                            ),
                            textInputAction: TextInputAction.search,
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          tooltip: 'Filtro',
                          onPressed: _openFilterDialog,
                          icon: const Icon(Icons.filter_alt_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredByFilter.isEmpty
                          ? const _EmptyState(
                              title: 'Sin resultados',
                              subtitle: 'Intenta con otro nombre o teléfono.',
                            )
                          : ListView.separated(
                              itemCount: filteredByFilter.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final r = filteredByFilter[i];
                                final nombre =
                                    (r['nombre'] as String?) ?? 'Cliente';
                                final telefono =
                                    (r['telefono'] as String?) ?? '';
                                final email = (r['email'] as String?) ?? '';
                                final subtitle = [telefono, email]
                                    .where((e) => e.trim().isNotEmpty)
                                    .join(' • ');
                                return FullTechCard(
                                  icon: Icons.people_alt_outlined,
                                  title: nombre,
                                  subtitle: subtitle.isEmpty ? '—' : subtitle,
                                  trailing: '#${r['id']}',
                                  badge: 'Cliente',
                                  onTap: () => _openDetails(context, r),
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
    );
  }

  Future<void> _openDetails(BuildContext context, Map<String, Object?> row) {
    return showFullTechFormSheet<void>(
      context: context,
      child: _ClienteDetailSheet(row: row),
    );
  }

  List<Map<String, Object?>> _applyFilter(List<Map<String, Object?>> input) {
    if (_filter == 'Todos') return input;

    bool hasValue(String? v) => (v ?? '').trim().isNotEmpty;

    return input.where((r) {
      final telefono = (r['telefono'] as String?);
      final email = (r['email'] as String?);
      final direccion = (r['direccion'] as String?);

      if (_filter == 'Con teléfono') return hasValue(telefono);
      if (_filter == 'Con email') return hasValue(email);
      if (_filter == 'Con dirección') return hasValue(direccion);
      return true;
    }).toList(growable: false);
  }

  Future<void> _openFilterDialog() async {
    final options = const <String>[
      'Todos',
      'Con teléfono',
      'Con email',
      'Con dirección',
    ];

    var selected = _filter;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Filtro de clientes'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: options
                  .map(
                    (o) => RadioListTile<String>(
                      value: o,
                      groupValue: selected,
                      onChanged: (v) => setLocal(() => selected = v ?? selected),
                      title: Text(o),
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                  .toList(growable: false),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'Todos'),
                child: const Text('Limpiar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    setState(() => _filter = result);
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
              const SizedBox(height: 4),
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

class _ClienteFormSheet extends StatefulWidget {
  const _ClienteFormSheet({this.existing});

  final Map<String, Object?>? existing;

  @override
  State<_ClienteFormSheet> createState() => _ClienteFormSheetState();
}

class _ClienteFormSheetState extends State<_ClienteFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _direccion = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _email.dispose();
    _direccion.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nombre.text = (existing['nombre'] as String?)?.trim() ?? '';
      _telefono.text = (existing['telefono'] as String?)?.trim() ?? '';
      _email.text = (existing['email'] as String?)?.trim() ?? '';
      _direccion.text = (existing['direccion'] as String?)?.trim() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isEditing = existing != null;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FullTechSheetHeader(
            title: isEditing ? 'Editar cliente' : 'Nuevo cliente',
            subtitle: isEditing
                ? 'Actualiza la información del cliente'
                : 'Crea un registro básico del cliente',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nombre,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telefono,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Teléfono'),
            keyboardType: TextInputType.phone,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Opcional',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('Email y dirección'),
            children: [
              const SizedBox(height: 8),
              TextFormField(
                controller: _email,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _direccion,
                decoration: const InputDecoration(labelText: 'Dirección'),
                maxLines: 2,
              ),
              const SizedBox(height: 4),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    setState(() => _saving = true);

                    final payload = {
                      'nombre': _nombre.text.trim(),
                      'telefono': _telefono.text.trim(),
                      'email': _email.text.trim(),
                      'direccion': _direccion.text.trim(),
                    };

                    if (isEditing) {
                      final id = (existing['id'] as int?) ?? 0;
                      await AppDatabase.instance.update(
                        'clientes',
                        payload,
                        id: id,
                      );
                    } else {
                      await AppDatabase.instance.insert('clientes', {
                        ...payload,
                        'creado_en': DateTime.now().millisecondsSinceEpoch,
                      });
                    }
                    if (context.mounted) Navigator.of(context).pop();
                  },
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _ClienteDetailSheet extends StatelessWidget {
  const _ClienteDetailSheet({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nombre = (row['nombre'] as String?)?.trim();
    final telefono = (row['telefono'] as String?)?.trim();
    final email = (row['email'] as String?)?.trim();
    final direccion = (row['direccion'] as String?)?.trim();
    final id = (row['id'] as int?) ?? 0;

    final safeNombre = (nombre == null || nombre.isEmpty) ? 'Cliente' : nombre;
    final safeTelefono =
        (telefono == null || telefono.isEmpty) ? '—' : telefono;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FullTechSheetHeader(title: safeNombre, subtitle: safeTelefono),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Teléfono',
                  value: safeTelefono,
                ),
                if (email != null && email.isNotEmpty) ...[
                  const Divider(height: 16),
                  _InfoRow(
                    icon: Icons.alternate_email,
                    label: 'Email',
                    value: email,
                  ),
                ],
                if (direccion != null && direccion.isNotEmpty) ...[
                  const Divider(height: 16),
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Dirección',
                    value: direccion,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () async {
            Navigator.of(context).pop();
            await ClientesPage.openEditForm(context, row: row);
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            foregroundColor: colorScheme.error,
          ),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Eliminar cliente'),
                content: const Text(
                    'Esta acción no se puede deshacer. ¿Deseas eliminarlo?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            );
            if (ok != true) return;

            final db = AppDatabase.instance.db;
            final hasVentas = (await db.query(
              'ventas',
              where: 'cliente_id = ?',
              whereArgs: [id],
              limit: 1,
            ))
                .isNotEmpty;
            final hasPresupuestos = (await db.query(
              'presupuestos',
              where: 'cliente_id = ?',
              whereArgs: [id],
              limit: 1,
            ))
                .isNotEmpty;
            final hasOperaciones = (await db.query(
              'operaciones',
              where: 'cliente_id = ?',
              whereArgs: [id],
              limit: 1,
            ))
                .isNotEmpty;
            if (hasVentas || hasPresupuestos || hasOperaciones) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'No se puede eliminar: el cliente tiene registros relacionados.'),
                ),
              );
              return;
            }

            await AppDatabase.instance.delete('clientes', id: id);
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colorScheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colorScheme.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
