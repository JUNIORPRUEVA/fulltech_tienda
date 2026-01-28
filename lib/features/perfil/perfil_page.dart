import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../data/cloud_settings.dart';
import '../usuarios/usuarios_page.dart';
import '../../ui/fulltech_widgets.dart';

class PerfilPage extends StatelessWidget {
  const PerfilPage({super.key});

  static Future<void> openEditForm(BuildContext context) {
    return showFullTechFormSheet<void>(
      context: context,
      child: const _CredencialesFormSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: StreamBuilder<void>(
        stream: AppDatabase.instance.changes,
        builder: (context, _) {
          return FutureBuilder<Map<String, Object?>?>(
            future: AuthService.instance.currentUser(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (user == null) {
                return const _EmptyState(
                  title: 'Sin sesión',
                  subtitle: 'Inicia sesión para ver tu perfil.',
                );
              }

          final nombre = (user['nombre'] as String?)?.trim();
          final rol = (user['rol'] as String?)?.trim() ?? '—';
          final isAdmin = AuthService.isAdminRole(rol);
          final email = (user['email'] as String?)?.trim();
          final cedula = (user['cedula'] as String?)?.trim();
          final direccion = (user['direccion'] as String?)?.trim();
          final sueldo = user['sueldo_quincenal'];
          final meta = user['meta_quincenal'];
          final fechaIngreso = user['fecha_ingreso'] as int?;
          final ultimoLogin = user['ultimo_login'] as int?;

          final curriculumPath = _firstNonEmpty(
            (user['curriculum_url'] as String?)?.trim(),
            (user['curriculum_path'] as String?)?.trim(),
          );
          final cedulaFotoPath = _firstNonEmpty(
            (user['cedula_foto_url'] as String?)?.trim(),
            (user['cedula_foto_path'] as String?)?.trim(),
          );
          final licenciaPath = _firstNonEmpty(
            (user['licencia_url'] as String?)?.trim(),
            (user['licencia_path'] as String?)?.trim(),
          );
          final cartaTrabajoPath = _firstNonEmpty(
            (user['carta_trabajo_url'] as String?)?.trim(),
            (user['carta_trabajo_path'] as String?)?.trim(),
          );

          final safeNombre =
              (nombre == null || nombre.isEmpty) ? 'Usuario' : nombre;
          final initials = _initials(safeNombre);

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            children: [
              if (Navigator.of(context).canPop()) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Volver'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        child: Text(
                          initials,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              safeNombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$rol${(email ?? '').isEmpty ? '' : ' • $email'}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _CloudCard(
                userDisplayName: safeNombre,
                suggestedEmail: email,
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.credit_card_outlined,
                        label: 'Cédula',
                        value:
                            (cedula == null || cedula.isEmpty) ? '—' : cedula,
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
                        value: _fmtDate(fechaIngreso),
                      ),
                      const Divider(height: 16),
                      _InfoRow(
                        icon: Icons.login,
                        label: 'Último inicio de sesión',
                        value: _fmtDateTime(ultimoLogin),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (isAdmin) ...[
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings_outlined),
                        title: const Text('Editar perfil (completo)'),
                        subtitle: const Text('Como Admin puedes editar todos los campos'),
                        onTap: () => UsuariosPage.openEditForm(context, row: user),
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: const Text('Cambiar email / contraseña'),
                      subtitle: const Text('Solo credenciales'),
                      onTap: () => openEditForm(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('Inicios de sesión'),
                      subtitle: const Text('Historial reciente'),
                      onTap: () async {
                        final id = (user['id'] as int?) ?? 0;
                        if (id <= 0) return;
                        await showFullTechFormSheet<void>(
                          context: context,
                          child: _LoginHistorySheet(userId: id),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.folder_open_outlined),
                      title: Text('Documentos'),
                      subtitle: Text('Archivos del usuario'),
                    ),
                    const Divider(height: 1),
                    _DocTile(
                      icon: Icons.description_outlined,
                      label: 'Curriculum',
                      required: true,
                      path: curriculumPath,
                    ),
                    const Divider(height: 1),
                    _DocTile(
                      icon: Icons.badge_outlined,
                      label: 'Foto de cédula',
                      required: true,
                      path: cedulaFotoPath,
                    ),
                    const Divider(height: 1),
                    _DocTile(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Licencia',
                      path: licenciaPath,
                    ),
                    const Divider(height: 1),
                    _DocTile(
                      icon: Icons.work_outline,
                      label: 'Carta último trabajo',
                      path: cartaTrabajoPath,
                    ),
                  ],
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

class _CloudCard extends StatelessWidget {
  const _CloudCard({required this.userDisplayName, required this.suggestedEmail});

  final String userDisplayName;
  final String? suggestedEmail;

  String _fmtServerTime(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '—';
    final dt = DateTime.tryParse(v);
    if (dt == null) return v;
    final local = dt.toLocal();
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudSettingsData>(
      future: CloudSettings.load(),
      builder: (context, snapshot) {
        final settings = snapshot.data;
        final hasSession = settings?.hasSession ?? false;
        final email = (settings?.email ?? '').trim();
        final lastSync = settings?.lastServerTime ?? '';

        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: Icon(hasSession ? Icons.cloud_done : Icons.cloud_off),
                title: const Text('Nube'),
                subtitle: Text(
                  hasSession
                      ? '${email.isEmpty ? userDisplayName : email} • Última sync: ${_fmtServerTime(lastSync)}'
                      : 'Se conectará automáticamente al iniciar sesión.',
                ),
                onTap: null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sincronización automática'),
                subtitle: Text(
                  hasSession
                      ? 'Activa (se ejecuta al entrar y en segundo plano).'
                      : 'Inicia sesión para activarla.',
                ),
                onTap: null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CredencialesFormSheet extends StatefulWidget {
  const _CredencialesFormSheet();

  @override
  State<_CredencialesFormSheet> createState() => _CredencialesFormSheetState();
}

class _CredencialesFormSheetState extends State<_CredencialesFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _newPassword = TextEditingController();
  bool _obscure = true;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.currentUser().then((u) {
      if (!mounted) return;
      final email = (u?['email'] as String?)?.trim() ?? '';
      _email.text = email;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FullTechSheetHeader(
            title: 'Credenciales',
            subtitle: 'Edita tu email y/o contraseña',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (v) {
              final val = (v ?? '').trim();
              if (val.isEmpty) return 'Requerido';
              if (!val.contains('@')) return 'Email inválido';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _newPassword,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Nueva contraseña (opcional)',
              helperText: 'Para sincronizar con nube: mínimo 8 caracteres.',
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
              if (val.isEmpty) return null;
              if (val.length < 8) return 'Mínimo 8 caracteres (requerido para nube)';
              return null;
            },
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    setState(() => _saving = true);

                    await AuthService.instance.updateMyEmailPassword(
                      email: _email.text,
                      newPassword: _newPassword.text,
                    );

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

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.icon,
    required this.label,
    required this.path,
    this.required = false,
  });

  final IconData icon;
  final String label;
  final String? path;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final has = (path ?? '').trim().isNotEmpty;
    final fileName = has ? p.basename(path!) : (required ? 'Requerido' : '—');
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleColor = required && !has ? colorScheme.error : Colors.black54;
    final isRemote = has && _isRemote(path!);

    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: subtitleColor),
        ),
        trailing: has
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isImage(path!) && (isRemote || File(path!).existsSync()))
                    IconButton(
                      tooltip: 'Ver',
                      onPressed: () => _previewImage(context, path!),
                      icon: const Icon(Icons.image_outlined),
                    ),
                IconButton(
                  tooltip: 'Copiar ruta',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: path!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ruta copiada.')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            )
          : null,
      onTap: !has
          ? null
          : () => showFullTechFormSheet<void>(
                context: context,
                child: _DocumentoActionsSheet(label: label, path: path!),
              ),
    );
  }
}

class _DocumentoActionsSheet extends StatelessWidget {
  const _DocumentoActionsSheet({required this.label, required this.path});

  final String label;
  final String path;

    @override
    Widget build(BuildContext context) {
      final isRemote = _isRemote(path);
      final exists = isRemote ? false : File(path).existsSync();
      final name = p.basename(path);

      return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FullTechSheetHeader(title: label, subtitle: name),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(path),
          ),
        ),
          if (!exists) ...[
            const SizedBox(height: 10),
            Text(
              isRemote
                  ? 'Archivo en la nube. Copia el enlace para abrirlo.'
                  : 'El archivo no existe en esta ruta (posible cambio de dispositivo).',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: exists ? () => _openFile(context, path) : null,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir archivo'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _isImage(path) && (exists || isRemote)
                ? () => _previewImage(context, path)
                : null,
            icon: const Icon(Icons.image_outlined),
            label: const Text('Previsualizar'),
          ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: path));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ruta copiada.')),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar ruta'),
        ),
      ],
    );
  }
}

bool _isImage(String path) {
  final ext = p.extension(path).toLowerCase();
  return ext == '.png' || ext == '.jpg' || ext == '.jpeg';
}

Future<void> _previewImage(BuildContext context, String path) async {
  if (_isRemote(path)) {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.basename(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Image.network(path, fit: BoxFit.contain),
            ],
          ),
        );
      },
    );
    return;
  }

  if (!File(path).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Archivo no encontrado.')),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.basename(path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: InteractiveViewer(
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _openFile(BuildContext context, String path) async {
  if (!File(path).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Archivo no encontrado.')),
    );
    return;
  }

  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) {
    final message = result.message.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message.isEmpty ? 'No se pudo abrir el archivo.' : message,
        ),
      ),
    );
  }
}

bool _isRemote(String path) {
  final p = path.toLowerCase();
  return p.startsWith('http://') || p.startsWith('https://');
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

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'FT';
  final first = parts.first.characters.first;
  final second = parts.length >= 2 ? parts[1].characters.first : '';
  return (first + second).toUpperCase();
}
