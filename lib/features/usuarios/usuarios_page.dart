import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../data/cloud_api.dart';
import '../../data/cloud_settings.dart';
import '../../ui/fulltech_widgets.dart';

const _kRoles = <String>[
  'Admin',
  'Vendedor',
  'Tecnico',
  'Marketing',
  'Asistente Administrativo',
];

class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  static Future<void> openAddForm(BuildContext context) {
    return showFullTechFormSheet<void>(
      context: context,
      child: const _UsuarioFormSheet(),
    );
  }

  static Future<void> openEditForm(
    BuildContext context, {
    required Map<String, Object?> row,
  }) {
    return showFullTechFormSheet<void>(
      context: context,
      child: _UsuarioFormSheet(existing: row),
    );
  }

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  final _search = TextEditingController();

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
                .queryAll('usuarios', orderBy: 'creado_en DESC'),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <Map<String, Object?>>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (rows.isEmpty) {
                return const _EmptyState(
                  title: 'Sin usuarios',
                  subtitle: 'Crea usuarios y asígnales un rol.',
                );
              }

              final q = _search.text.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? rows
                  : rows.where((r) {
                      final nombre = (r['nombre'] as String?) ?? '';
                      final usuario = (r['usuario'] as String?) ?? '';
                      final rol = (r['rol'] as String?) ?? '';
                      final email = (r['email'] as String?) ?? '';
                      final cedula = (r['cedula'] as String?) ?? '';
                      final direccion = (r['direccion'] as String?) ?? '';
                      final haystack =
                          '$nombre $usuario $rol $email $cedula $direccion'
                              .toLowerCase();
                      return haystack.contains(q);
                    }).toList(growable: false);

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  children: [
                    _UsuariosHeader(count: rows.length),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Buscar',
                        hintText: 'Nombre, correo, cédula…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      textInputAction: TextInputAction.search,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const _EmptyState(
                              title: 'Sin resultados',
                              subtitle:
                                  'Intenta con otro nombre o nombre de usuario.',
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final r = filtered[i];
                                final nombre = (r['nombre'] as String?)?.trim();
                                final rol =
                                    (r['rol'] as String?)?.trim() ?? '—';
                                final email =
                                    (r['email'] as String?)?.trim() ?? '';
                                final bloqueado =
                                    ((r['bloqueado'] as int?) ?? 0) == 1;

                                final title = (nombre == null || nombre.isEmpty)
                                    ? 'Usuario'
                                    : nombre;
                                final subtitle = [
                                  rol,
                                  if (email.isNotEmpty) email,
                                  if (bloqueado) 'BLOQUEADO',
                                ].join(' • ');

                                return FullTechCard(
                                  icon: bloqueado
                                      ? Icons.lock_outline
                                      : Icons.verified_user_outlined,
                                  title: title,
                                  subtitle: subtitle,
                                  trailing: '#${r['id']}',
                                  badge: bloqueado ? 'Bloqueado' : rol,
                                  onTap: () => _openDetail(context, r),
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

  Future<void> _openDetail(BuildContext context, Map<String, Object?> row) {
    return showFullTechFormSheet<void>(
      context: context,
      child: _UsuarioDetailSheet(row: row),
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

class _UsuariosHeader extends StatelessWidget {
  const _UsuariosHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(31),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.verified_user_outlined,
                  color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Usuarios',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count registrados',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsuarioDetailSheet extends StatelessWidget {
  const _UsuarioDetailSheet({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final id = (row['id'] as int?) ?? 0;
    final myId = AuthService.instance.currentUserId;

    final nombre = (row['nombre'] as String?)?.trim();
    final rol = (row['rol'] as String?)?.trim() ?? '—';
    final email = (row['email'] as String?)?.trim();
    final cedula = (row['cedula'] as String?)?.trim();
    final direccion = (row['direccion'] as String?)?.trim();
    final sueldo = row['sueldo_quincenal'];
    final meta = row['meta_quincenal'];
    final fechaIngresoMs = (row['fecha_ingreso'] as int?);
    final ultimoLoginMs = (row['ultimo_login'] as int?);
    final bloqueado = ((row['bloqueado'] as int?) ?? 0) == 1;

    final curriculumPath = _firstNonEmpty(
      (row['curriculum_url'] as String?)?.trim(),
      (row['curriculum_path'] as String?)?.trim(),
    );
    final cedulaFotoPath = _firstNonEmpty(
      (row['cedula_foto_url'] as String?)?.trim(),
      (row['cedula_foto_path'] as String?)?.trim(),
    );
    final licenciaPath = _firstNonEmpty(
      (row['licencia_url'] as String?)?.trim(),
      (row['licencia_path'] as String?)?.trim(),
    );
    final cartaTrabajoPath = _firstNonEmpty(
      (row['carta_trabajo_url'] as String?)?.trim(),
      (row['carta_trabajo_path'] as String?)?.trim(),
    );

    final safeNombre = (nombre == null || nombre.isEmpty) ? 'Usuario' : nombre;
    final safeEmail = (email == null || email.isEmpty) ? '—' : email;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FullTechSheetHeader(
          title: safeNombre,
          subtitle: '$safeEmail • $rol${bloqueado ? ' • BLOQUEADO' : ''}',
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.alternate_email,
                  label: 'Correo',
                  value: safeEmail,
                  onCopy: safeEmail == '—'
                      ? null
                      : () => Clipboard.setData(ClipboardData(text: safeEmail)),
                ),
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Nombre',
                  value: safeNombre,
                ),
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.credit_card_outlined,
                  label: 'Cédula',
                  value: (cedula == null || cedula.isEmpty) ? '—' : cedula,
                ),
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Dirección',
                  value: (direccion == null || direccion.isEmpty)
                      ? '—'
                      : direccion,
                ),
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.payments_outlined,
                  label: 'Sueldo quincenal',
                  value: _fmtMoney(sueldo),
                ),
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.flag_outlined,
                  label: 'Meta quincenal',
                  value: _fmtMoney(meta),
                ),
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.event_available_outlined,
                  label: 'Fecha de ingreso',
                  value: _fmtDate(fechaIngresoMs),
                ),
                const Divider(height: 16),
                _InfoRow(
                  icon: Icons.login,
                  label: 'Último inicio de sesión',
                  value: _fmtDateTime(ultimoLoginMs),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _DocRow(
                  label: 'Curriculum (obligatorio)',
                  path: curriculumPath,
                  required: true,
                ),
                const Divider(height: 16),
                _DocRow(
                  label: 'Foto cédula (obligatorio)',
                  path: cedulaFotoPath,
                  required: true,
                ),
                const Divider(height: 16),
                _DocRow(
                  label: 'Licencia (opcional)',
                  path: licenciaPath,
                ),
                const Divider(height: 16),
                _DocRow(
                  label: 'Carta último trabajo (opcional)',
                  path: cartaTrabajoPath,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () async {
            Navigator.of(context).pop();
            await UsuariosPage.openEditForm(context, row: row);
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: id <= 0 || id == myId
              ? null
              : () async {
                  await AppDatabase.instance.update(
                    'usuarios',
                    {'bloqueado': bloqueado ? 0 : 1},
                    id: id,
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
          icon: Icon(bloqueado ? Icons.lock_open_outlined : Icons.lock_outline),
          label: Text(bloqueado ? 'Desbloquear' : 'Bloquear'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: id <= 0
              ? null
              : () async {
                  await showFullTechFormSheet<void>(
                    context: context,
                    child: _LoginHistorySheet(userId: id),
                  );
                },
          icon: const Icon(Icons.history),
          label: const Text('Inicios de sesión'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(foregroundColor: colorScheme.error),
          onPressed: (id == 1 || id == myId)
              ? null
              : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Eliminar usuario'),
                      content: const Text(
                        'Esta acción no se puede deshacer. ¿Deseas eliminarlo?',
                      ),
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
                  await AppDatabase.instance.delete('usuarios', id: id);
                  if (context.mounted) Navigator.of(context).pop();
                },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar'),
        ),
        if (id == myId) ...[
          const SizedBox(height: 8),
          const Text(
            'No puedes bloquear/eliminar tu propio usuario.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
        if (id == 1) ...[
          const SizedBox(height: 8),
          const Text(
            'El usuario demo no se puede eliminar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ],
    );
  }
}

class _LoginHistorySheet extends StatelessWidget {
  const _LoginHistorySheet({required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FullTechSheetHeader(
          title: 'Inicios de sesión',
          subtitle: 'Historial reciente',
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, Object?>>>(
          future: AppDatabase.instance.db.query(
            'usuarios_logins',
            where: 'usuario_id = ?',
            whereArgs: [userId],
            orderBy: 'hora DESC',
            limit: 50,
          ),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, Object?>>[];
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (rows.isEmpty) {
              return const _EmptyState(
                title: 'Sin registros',
                subtitle: 'Aún no hay inicios de sesión registrados.',
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = rows[i];
                final hora = (r['hora'] as int?) ?? 0;
                final ok = ((r['exitoso'] as int?) ?? 0) == 1;
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(
                        ok ? Icons.check_circle_outline : Icons.error_outline),
                    title: Text(ok ? 'Exitoso' : 'Fallido'),
                    subtitle: Text(_fmtDateTime(hora)),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _UsuarioFormSheet extends StatefulWidget {
  const _UsuarioFormSheet({this.existing});

  final Map<String, Object?>? existing;

  @override
  State<_UsuarioFormSheet> createState() => _UsuarioFormSheetState();
}

class _UsuarioFormSheetState extends State<_UsuarioFormSheet> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCompleto = TextEditingController();
  final _usuario = TextEditingController();
  final _email = TextEditingController();
  final _cedula = TextEditingController();
  final _direccion = TextEditingController();

  final _sueldo = TextEditingController();
  final _meta = TextEditingController();

  String _rol = _kRoles[1];
  int? _fechaIngresoMs;
  bool _empleadoMes = false;

  String? _curriculumPath;
  String? _licenciaPath;
  String? _cedulaFotoPath;
  String? _cartaTrabajoPath;

  final _password = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nombreCompleto.text = (e['nombre'] as String?)?.trim() ?? '';
      _usuario.text = (e['usuario'] as String?)?.trim() ?? '';
      _email.text = (e['email'] as String?)?.trim() ?? '';
      _cedula.text = (e['cedula'] as String?)?.trim() ?? '';
      _direccion.text = (e['direccion'] as String?)?.trim() ?? '';
      _rol = (e['rol'] as String?)?.trim() ?? _rol;
      final sueldo = e['sueldo_quincenal'];
      final meta = e['meta_quincenal'];
      _sueldo.text = sueldo == null ? '' : '$sueldo';
      _meta.text = meta == null ? '' : '$meta';
      _fechaIngresoMs = e['fecha_ingreso'] as int?;
      _empleadoMes = ((e['empleado_mes'] as int?) ?? 0) == 1;
      _curriculumPath = (e['curriculum_path'] as String?)?.trim();
      _licenciaPath = (e['licencia_path'] as String?)?.trim();
      _cedulaFotoPath = (e['cedula_foto_path'] as String?)?.trim();
      _cartaTrabajoPath = (e['carta_trabajo_path'] as String?)?.trim();

      // Keep legacy `usuario` aligned to email to avoid confusion.
      if (_usuario.text.trim().isEmpty && _email.text.trim().isNotEmpty) {
        _usuario.text = _email.text.trim().toLowerCase();
      }
    }
  }

  @override
  void dispose() {
    _nombreCompleto.dispose();
    _usuario.dispose();
    _email.dispose();
    _cedula.dispose();
    _direccion.dispose();
    _sueldo.dispose();
    _meta.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    final isEditing = e != null;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FullTechSheetHeader(
            title: isEditing ? 'Editar usuario' : 'Nuevo usuario',
            subtitle: isEditing
                ? 'Actualiza información, rol y documentos'
                : 'Crea un usuario con rol y documentos',
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Credenciales',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: isEditing
                          ? 'Contrasena (dejar en blanco para no cambiar)'
                          : 'Contrasena',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                    validator: (v) {
                      final val = (v ?? '').trim();
                      if (isEditing) {
                        if (val.isEmpty) return null;
                        return null;
                      }

                      if (val.isEmpty) return 'Requerido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usuario,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      helperText: 'Ej: junior (puede ser corto).',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final val = (v ?? '').trim();
                      if (val.isEmpty) return 'Requerido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Correo (opcional)',
                      helperText: 'Si lo usas, debe ser valido.',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final val = (v ?? '').trim();
                      if (val.isEmpty) return null;
                      if (!val.contains('@')) return 'Email invalido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _kRoles.contains(_rol) ? _rol : _kRoles.first,
                    items: _kRoles
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(growable: false),
                    onChanged: (v) => setState(() => _rol = v ?? _rol),
                    decoration: const InputDecoration(labelText: 'Rol'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Datos personales',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nombreCompleto,
                    decoration:
                        const InputDecoration(labelText: 'Nombre completo'),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cedula,
                    decoration:
                        const InputDecoration(labelText: 'Número de cédula'),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _direccion,
                    decoration: const InputDecoration(labelText: 'Dirección'),
                    maxLines: 2,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Empresa',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _empleadoMes,
                    onChanged: (v) => setState(() => _empleadoMes = v),
                    title: const Text('Empleado del mes'),
                    subtitle: const Text(
                      'Se mostrará en el Reporte (mural). Solo puede haber uno activo.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sueldo,
                    decoration: const InputDecoration(
                        labelText: 'Sueldo quincenal (monto)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final val = (v ?? '').trim();
                      if (val.isEmpty) return 'Requerido';
                      final n = double.tryParse(val.replaceAll(',', '.'));
                      if (n == null) return 'Número inválido';
                      if (n < 0) return 'Debe ser >= 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _meta,
                    decoration: const InputDecoration(
                        labelText: 'Meta quincenal mínima (monto)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final val = (v ?? '').trim();
                      if (val.isEmpty) return 'Requerido';
                      final n = double.tryParse(val.replaceAll(',', '.'));
                      if (n == null) return 'Número inválido';
                      if (n < 0) return 'Debe ser >= 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: 'Fecha de ingreso',
                    valueMs: _fechaIngresoMs,
                    onPick: (ms) => setState(() => _fechaIngresoMs = ms),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Documentos',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  _PickFileRow(
                    label: 'Curriculum (obligatorio)',
                    required: true,
                    path: _curriculumPath,
                    onPick: () =>
                        _pickFile((p) => setState(() => _curriculumPath = p)),
                    onClear: () => setState(() => _curriculumPath = null),
                  ),
                  const SizedBox(height: 10),
                  _PickFileRow(
                    label: 'Foto de cédula (obligatorio)',
                    required: true,
                    path: _cedulaFotoPath,
                    onPick: () =>
                        _pickFile((p) => setState(() => _cedulaFotoPath = p)),
                    onClear: () => setState(() => _cedulaFotoPath = null),
                  ),
                  const SizedBox(height: 10),
                  _PickFileRow(
                    label: 'Licencia (opcional)',
                    path: _licenciaPath,
                    onPick: () =>
                        _pickFile((p) => setState(() => _licenciaPath = p)),
                    onClear: () => setState(() => _licenciaPath = null),
                  ),
                  const SizedBox(height: 10),
                  _PickFileRow(
                    label: 'Carta último trabajo (opcional)',
                    path: _cartaTrabajoPath,
                    onPick: () =>
                        _pickFile((p) => setState(() => _cartaTrabajoPath = p)),
                    onClear: () => setState(() => _cartaTrabajoPath = null),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    if (_fechaIngresoMs == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Fecha de ingreso requerida.')),
                      );
                      return;
                    }
                    if ((_curriculumPath ?? '').trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Curriculum requerido.')),
                      );
                      return;
                    }
                    if ((_cedulaFotoPath ?? '').trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Foto de cédula requerida.')),
                      );
                      return;
                    }

                    setState(() => _saving = true);

                    final usuario = _usuario.text.trim().toLowerCase();
                    final emailRaw = _email.text.trim();
                    final email =
                        emailRaw.isEmpty ? null : emailRaw.toLowerCase();
                    final existingId = (e?['id'] as int?) ?? 0;
                    final dupUser = await AppDatabase.instance.db.query(
                      'usuarios',
                      where: existingId > 0
                          ? 'LOWER(usuario) = ? AND id != ?'
                          : 'LOWER(usuario) = ?',
                      whereArgs:
                          existingId > 0 ? [usuario, existingId] : [usuario],
                      limit: 1,
                    );
                    if (dupUser.isNotEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Ese usuario ya existe.')),
                        );
                      }
                      if (mounted) setState(() => _saving = false);
                      return;
                    }

                    if (email != null && email.isNotEmpty) {
                      final dupEmail = await AppDatabase.instance.db.query(
                        'usuarios',
                        where: existingId > 0
                            ? 'LOWER(email) = ? AND id != ?'
                            : 'LOWER(email) = ?',
                        whereArgs: existingId > 0
                            ? [email, existingId]
                            : [email],
                        limit: 1,
                      );
                      if (dupEmail.isNotEmpty) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Ese correo ya existe.')),
                          );
                        }
                        if (mounted) setState(() => _saving = false);
                        return;
                      }
                    }

                    final sueldo =
                        double.parse(_sueldo.text.trim().replaceAll(',', '.'));
                    final meta =
                        double.parse(_meta.text.trim().replaceAll(',', '.'));

                    final values = <String, Object?>{
                      'nombre': _nombreCompleto.text.trim(),
                      'usuario': usuario,
                      'rol': _rol,
                      'email': email,
                      'cedula': _cedula.text.trim(),
                      'direccion': _direccion.text.trim(),
                      'sueldo_quincenal': sueldo,
                      'meta_quincenal': meta,
                      'empleado_mes': _empleadoMes ? 1 : 0,
                      'fecha_ingreso': _fechaIngresoMs,
                      'curriculum_path': _curriculumPath,
                      'licencia_path': _licenciaPath,
                      'cedula_foto_path': _cedulaFotoPath,
                      'carta_trabajo_path': _cartaTrabajoPath,
                    };

                    // Garantiza que solo un usuario sea Empleado del mes.
                    if (_empleadoMes) {
                      await AppDatabase.instance.db.rawUpdate(
                        'UPDATE usuarios SET empleado_mes = 0 WHERE id != ?',
                        [existingId > 0 ? existingId : -1],
                      );
                    }

                    final pw = _password.text.trim();
                    if (!isEditing || pw.isNotEmpty) {
                      if (pw.isEmpty) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Contraseña requerida.')),
                          );
                        }
                        if (mounted) setState(() => _saving = false);
                        return;
                      }
                      final salt = AuthService.newSalt();
                      values['password'] = null;
                      values['password_salt'] = salt;
                      values['password_hash'] =
                          AuthService.hashPassword(password: pw, salt: salt);
                    }

                    if (isEditing) {
                      await AppDatabase.instance
                          .update('usuarios', values, id: existingId);
                    } else {
                      await AppDatabase.instance.insert('usuarios', {
                        ...values,
                        'bloqueado': 0,
                        'creado_en': DateTime.now().millisecondsSinceEpoch,
                      });

                      // Create the cloud account automatically (best-effort).
                      // Do NOT store tokens here (this is typically an admin creating
                      // another user, not the current device session).
                      final cloudEmail = (_email.text).trim();
                      final cloudPw = (_password.text).trim();
                      if (cloudEmail.isNotEmpty && cloudPw.isNotEmpty) {
                        // ignore: unawaited_futures
                        Future(() async {
                          try {
                            final settings = await CloudSettings.load();
                            await CloudApi().register(
                              baseUrl: settings.baseUrl,
                              email: cloudEmail,
                              password: cloudPw,
                            );
                          } catch (_) {
                            // ignore
                          }
                        });
                      }
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

  Future<void> _pickFile(ValueChanged<String> onPicked) async {
    final res = await FilePicker.platform.pickFiles(
      withData: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    final path = res?.files.single.path;
    if (path == null || path.trim().isEmpty) return;
    onPicked(path);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.valueMs,
    required this.onPick,
  });

  final String label;
  final int? valueMs;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final txt = _fmtDate(valueMs);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final now = DateTime.now();
        final current = valueMs == null
            ? now
            : DateTime.fromMillisecondsSinceEpoch(valueMs!);
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(now.year + 2),
          initialDate: current,
        );
        if (picked == null) return;
        onPick(DateTime(picked.year, picked.month, picked.day)
            .millisecondsSinceEpoch);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(txt == '—' ? 'Seleccionar' : txt),
      ),
    );
  }
}

class _PickFileRow extends StatelessWidget {
  const _PickFileRow({
    required this.label,
    this.required = false,
    required this.path,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final bool required;
  final String? path;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final has = (path ?? '').trim().isNotEmpty;
    final fileName = has ? p.basename(path!) : 'No seleccionado';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: required && !has
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Subir'),
        ),
        if (has) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Quitar',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;

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
        if (onCopy != null)
          IconButton(
            tooltip: 'Copiar',
            onPressed: onCopy,
            icon: const Icon(Icons.copy),
          ),
      ],
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.label,
    required this.path,
    this.required = false,
  });

  final String label;
  final String? path;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final has = (path ?? '').trim().isNotEmpty;
    final status = has ? p.basename(path!) : (required ? 'Falta' : '—');
    final color = required && !has ? Theme.of(context).colorScheme.error : null;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        if (has)
          IconButton(
            tooltip: 'Copiar ruta',
            onPressed: () => Clipboard.setData(ClipboardData(text: path!)),
            icon: const Icon(Icons.copy),
          ),
      ],
    );
  }
}

String? _firstNonEmpty(String? a, String? b) {
  final v = (a ?? '').trim();
  if (v.isNotEmpty) return v;
  final w = (b ?? '').trim();
  if (w.isNotEmpty) return w;
  return null;
}

String _fmtMoney(Object? v) {
  if (v == null) return '—';
  if (v is num) return v.toStringAsFixed(2);
  final n = double.tryParse('$v');
  if (n == null) return '—';
  return n.toStringAsFixed(2);
}

String _fmtDate(int? ms) {
  if (ms == null || ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _fmtDateTime(int? ms) {
  if (ms == null || ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_fmtDate(ms)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
