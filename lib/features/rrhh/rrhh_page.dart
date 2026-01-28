import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/cloud_http.dart';
import '../../data/cloud_settings.dart';
import '../../ui/fulltech_widgets.dart';

class RrhhPage extends StatefulWidget {
  const RrhhPage({super.key});

  @override
  State<RrhhPage> createState() => _RrhhPageState();
}

class _RrhhPageState extends State<RrhhPage> with TickerProviderStateMixin {
  final _http = CloudHttp();

  late final TabController _tabController;
  final _statuses = const ['PENDING', 'APPROVED', 'REJECTED'];
  final _roles = const [
    {'key': 'tecnico', 'label': 'Técnico'},
    {'key': 'vendedor', 'label': 'Vendedor'},
    {'key': 'marketing', 'label': 'Marketing'},
    {'key': 'asistente', 'label': 'Asistente Administrativo'},
    {'key': 'admin', 'label': 'Administrador'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load(String status) async {
    final resp = await _http.getJson('/rrhh/applications', query: {
      'status': status,
    });
    final data = resp['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<void> _updateStatus(String id, String status) async {
    await _http.patchJson('/rrhh/applications/$id', {'status': status});
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _delete(String id) async {
    await _http.deleteJson('/rrhh/applications/$id');
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RRHH'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pendientes'),
            Tab(text: 'Aprobadas'),
            Tab(text: 'Rechazadas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _statuses
            .map(
              (s) => _StatusList(
                status: s,
                load: _load,
                onApprove: (id) => _updateStatus(id, 'APPROVED'),
                onReject: (id) => _updateStatus(id, 'REJECTED'),
                onDelete: _delete,
                roles: _roles,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _StatusList extends StatelessWidget {
  const _StatusList({
    required this.status,
    required this.load,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
    required this.roles,
  });

  final String status;
  final Future<List<Map<String, dynamic>>> Function(String status) load;
  final Future<void> Function(String id) onApprove;
  final Future<void> Function(String id) onReject;
  final Future<void> Function(String id) onDelete;
  final List<Map<String, String>> roles;

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: load(status),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const [];

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.isEmpty ? 1 : items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == 0) {
                return _LinksCard(roles: roles);
              }
              if (items.isEmpty) {
                return const _EmptyState(
                  title: 'Sin solicitudes',
                  subtitle: 'No hay solicitudes para mostrar.',
                );
              }
              final index = i - 1;
              return _SolicitudCard(
                data: items[index],
                onApprove: onApprove,
                onReject: onReject,
                onDelete: onDelete,
              );
            },
          );
        },
      ),
    );
  }
}

class _LinksCard extends StatelessWidget {
  const _LinksCard({required this.roles});

  final List<Map<String, String>> roles;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudSettingsData>(
      future: CloudSettings.load(),
      builder: (context, snapshot) {
        final settings = snapshot.data;
        final email = (settings?.email ?? '').trim();
        final baseUrl = (settings?.baseUrl ?? '').trim();
        final canShare = email.isNotEmpty && baseUrl.isNotEmpty;

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Formularios virtuales',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  canShare
                      ? 'Comparte los enlaces según el rol.'
                      : 'Inicia sesión en la nube para generar enlaces.',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 10),
                if (canShare)
                  Column(
                    children: roles
                        .map((r) => _RoleLink(
                              label: r['label'] ?? '',
                              link:
                                  '$baseUrl/rrhh/roles/${r['key']}?email=${Uri.encodeComponent(email)}',
                            ))
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoleLink extends StatelessWidget {
  const _RoleLink({required this.label, required this.link});

  final String label;
  final String link;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copiar',
            onPressed: () => Clipboard.setData(ClipboardData(text: link)),
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'Abrir',
            onPressed: () => launchUrl(Uri.parse(link),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
    );
  }
}

class _SolicitudCard extends StatelessWidget {
  const _SolicitudCard({
    required this.data,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final Future<void> Function(String id) onApprove;
  final Future<void> Function(String id) onReject;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    final id = (data['id'] ?? '').toString();
    final name = (data['name'] ?? '').toString().trim();
    final role = (data['role'] ?? '').toString().trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final whatsapp = (data['whatsapp'] ?? '').toString().trim();
    final techType = (data['techType'] ?? '').toString().trim();
    final techAreas = _listFromJson(data['techAreas']);
    final resumeUrl = (data['resumeUrl'] ?? '').toString().trim();
    final idCardUrl = (data['idCardUrl'] ?? '').toString().trim();
    final photoUrl = (data['photoUrl'] ?? '').toString().trim();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name.isEmpty ? 'Solicitante' : name,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              role.isEmpty ? 'Rol' : role,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            _infoRow('Teléfono', phone),
            _infoRow('WhatsApp', whatsapp),
            if (techType.isNotEmpty) _infoRow('Tipo técnico', techType),
            if (techAreas.isNotEmpty)
              _infoRow('Áreas', techAreas.join(', ')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _docButton('Currículum', resumeUrl),
                _docButton('Cédula', idCardUrl),
                _docButton('Foto', photoUrl),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if ((data['status'] ?? '') == 'PENDING') ...[
                  FilledButton.tonal(
                    onPressed: id.isEmpty ? null : () => onApprove(id),
                    child: const Text('Aprobar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: id.isEmpty ? null : () => onReject(id),
                    child: const Text('Rechazar'),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: id.isEmpty ? null : () => onDelete(id),
                  child: const Text('Eliminar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final v = value.isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $v', style: const TextStyle(color: Colors.black87)),
    );
  }

  Widget _docButton(String label, String url) {
    return OutlinedButton.icon(
      onPressed: url.isEmpty ? null : () => _openUrl(url),
      icon: const Icon(Icons.open_in_new, size: 18),
      label: Text(label),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<String> _listFromJson(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
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
                  style:
                      const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
